import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, Optional, Set

import requests
from dotenv import load_dotenv

load_dotenv(override=True)

API_VERSION = "2025-11-01-preview"

# Knowledge source kinds (from MS Learn 2025-11-01-preview API)
# Indexed sources (generate indexer pipeline):
#   - searchIndex: wraps existing index
#   - azureBlob: generates indexer pipeline from blob storage
#   - indexedOneLake: generates indexer pipeline from OneLake
#   - indexedSharePoint: generates indexer pipeline from SharePoint
# Remote sources (no indexer pipeline):
#   - remoteSharePoint: queries SharePoint directly
#   - web: queries Bing search directly

INDEXED_KINDS = {"searchIndex", "azureBlob", "indexedOneLake", "indexedSharePoint"}
REMOTE_KINDS = {"remoteSharePoint", "web"}


# -----------------------
# Utils
# -----------------------
def env(name: str) -> str:
    v = os.getenv(name)
    if not v:
        print(f"Missing env var: {name}", file=sys.stderr)
        sys.exit(1)
    return v


def http_get(endpoint: str, key: str, path: str) -> Optional[Dict]:
    """GET request with error handling. Returns None on 404."""
    url = f"{endpoint}/{path}"
    r = requests.get(
        url,
        headers={"api-key": key},
        params={"api-version": API_VERSION},
    )
    if r.status_code == 404:
        return None
    r.raise_for_status()
    return r.json()


def dump(obj: Dict, path: Path, label: str):
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
    print(f"  ✔ dumped {label}: {path.name}")


# -----------------------
# Azure Search API
# -----------------------
def list_kbs(ep, key):
    return [x["name"] for x in http_get(ep, key, "knowledgebases").get("value", [])]


def get_kb(ep, key, name):
    return http_get(ep, key, f"knowledgebases/{name}")


def get_ks(ep, key, name):
    return http_get(ep, key, f"knowledgesources/{name}")


def get_index(ep, key, name):
    return http_get(ep, key, f"indexes/{name}")


def get_indexer(ep, key, name):
    return http_get(ep, key, f"indexers/{name}")


def get_datasource(ep, key, name):
    return http_get(ep, key, f"datasources/{name}")


def get_skillset(ep, key, name):
    return http_get(ep, key, f"skillsets/{name}")


def get_synmap(ep, key, name):
    return http_get(ep, key, f"synonymmaps/{name}")


# -----------------------
# Main
# -----------------------
def extract_resources_from_ks(ks: Dict) -> Dict[str, Optional[str]]:
    """
    Extract resource names from a knowledge source based on its kind.
    
    Per Azure AI Search 2025-11-01-preview API (verified structure):
    - searchIndex: uses searchIndexParameters.searchIndexName (no generated resources)
    - azureBlob: resources in azureBlobParameters.createdResources
    - indexedOneLake: resources in indexedOneLakeParameters.createdResources  
    - indexedSharePoint: resources in indexedSharePointParameters.createdResources
    - remoteSharePoint/web: remote sources with no indexer pipeline
    
    createdResources contains: index, indexer, skillset, datasource
    """
    kind = ks.get("kind", "")
    result = {
        "indexName": None,
        "indexerName": None,
        "dataSourceName": None,
        "skillsetName": None,
    }
    
    if kind == "searchIndex":
        # searchIndex wraps existing index - index name in searchIndexParameters
        params = ks.get("searchIndexParameters", {})
        if params:
            result["indexName"] = params.get("searchIndexName")
        # searchIndex kind doesn't generate indexer/datasource/skillset
        
    elif kind == "azureBlob":
        # Resources in azureBlobParameters.createdResources
        params = ks.get("azureBlobParameters", {})
        created = params.get("createdResources", {}) if params else {}
        result["indexName"] = created.get("index")
        result["indexerName"] = created.get("indexer")
        result["dataSourceName"] = created.get("datasource")
        result["skillsetName"] = created.get("skillset")
        
    elif kind == "indexedOneLake":
        # Resources in indexedOneLakeParameters.createdResources
        params = ks.get("indexedOneLakeParameters", {})
        created = params.get("createdResources", {}) if params else {}
        result["indexName"] = created.get("index")
        result["indexerName"] = created.get("indexer")
        result["dataSourceName"] = created.get("datasource")
        result["skillsetName"] = created.get("skillset")
        
    elif kind == "indexedSharePoint":
        # Resources in indexedSharePointParameters.createdResources
        params = ks.get("indexedSharePointParameters", {})
        created = params.get("createdResources", {}) if params else {}
        result["indexName"] = created.get("index")
        result["indexerName"] = created.get("indexer")
        result["dataSourceName"] = created.get("datasource")
        result["skillsetName"] = created.get("skillset")
        
    elif kind in {"remoteSharePoint", "web"}:
        # Remote sources - no index or indexer pipeline
        print(f"    ⓘ Remote knowledge source (kind={kind}), no indexer pipeline")
    else:
        print(f"    ⚠ Unknown knowledge source kind: {kind}")
    
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Full dump of Azure AI Search graph (KB → KS → Index → Indexer → Datasource → Skillset)"
    )
    parser.add_argument("--kb", nargs="+", required=True, help="KB names to dump, or '*' for all")
    parser.add_argument("--out", default="../infra/modules/az_search", help="Output directory")
    args = parser.parse_args()

    endpoint = env("AZURE_SEARCH_ENDPOINT").rstrip("/")
    key = env("AZURE_SEARCH_ADMIN_KEY")

    base = Path(args.out)
    dirs = {
        "datasources": base / "datasources",
        "skillsets": base / "skillsets",
        "indexes": base / "indexes",
        "indexers": base / "indexers",
        "synonymmaps": base / "synonymmaps",
        "ks": base / "knowledge-sources",
        "kb": base / "knowledge-bases",
    }
    for d in dirs.values():
        d.mkdir(parents=True, exist_ok=True)

    # Resolve KB list
    kb_names = list_kbs(endpoint, key) if args.kb == ["*"] else args.kb

    seen_indexes: Set[str] = set()
    seen_indexers: Set[str] = set()
    seen_datasources: Set[str] = set()
    seen_skillsets: Set[str] = set()
    seen_synmaps: Set[str] = set()
    seen_ks: Set[str] = set()

    for kb_name in kb_names:
        print(f"\n▶ KB: {kb_name}")
        kb = get_kb(endpoint, key, kb_name)
        if not kb:
            print(f"  ⚠ Knowledge base '{kb_name}' not found, skipping")
            continue
        dump(kb, dirs["kb"] / f"{kb_name}.json", "knowledge-base")

        for ks_ref in kb.get("knowledgeSources", []):
            ks_name = ks_ref.get("name")
            if not ks_name or ks_name in seen_ks:
                continue

            print(f"  ├─ KS: {ks_name}")
            ks = get_ks(endpoint, key, ks_name)
            if not ks:
                print(f"    ⚠ Knowledge source '{ks_name}' not found, skipping")
                continue
            dump(ks, dirs["ks"] / f"{ks_name}.json", "knowledge-source")
            seen_ks.add(ks_name)

            # Extract resource names based on knowledge source kind
            resources = extract_resources_from_ks(ks)
            
            # Dump Index
            index_name = resources["indexName"]
            if index_name and index_name not in seen_indexes:
                index = get_index(endpoint, key, index_name)
                if index:
                    dump(index, dirs["indexes"] / f"{index_name}.json", "index")
                    seen_indexes.add(index_name)

                    # Dump Synonym Maps referenced by the index
                    for sm in index.get("synonymMaps", []):
                        if sm and sm not in seen_synmaps:
                            syn = get_synmap(endpoint, key, sm)
                            if syn:
                                dump(syn, dirs["synonymmaps"] / f"{sm}.json", "synonym-map")
                            seen_synmaps.add(sm)
                else:
                    print(f"    ⚠ Index '{index_name}' not found")

            # Dump Indexer
            indexer_name = resources["indexerName"]
            if indexer_name and indexer_name not in seen_indexers:
                indexer = get_indexer(endpoint, key, indexer_name)
                if indexer:
                    dump(indexer, dirs["indexers"] / f"{indexer_name}.json", "indexer")
                    seen_indexers.add(indexer_name)
                else:
                    print(f"    ⚠ Indexer '{indexer_name}' not found")

            # Dump Data Source
            ds_name = resources["dataSourceName"]
            if ds_name and ds_name not in seen_datasources:
                datasource = get_datasource(endpoint, key, ds_name)
                if datasource:
                    dump(datasource, dirs["datasources"] / f"{ds_name}.json", "datasource")
                    seen_datasources.add(ds_name)
                else:
                    print(f"    ⚠ Datasource '{ds_name}' not found")

            # Dump Skillset
            ss_name = resources["skillsetName"]
            if ss_name and ss_name not in seen_skillsets:
                skillset = get_skillset(endpoint, key, ss_name)
                if skillset:
                    dump(skillset, dirs["skillsets"] / f"{ss_name}.json", "skillset")
                    seen_skillsets.add(ss_name)
                else:
                    print(f"    ⚠ Skillset '{ss_name}' not found")

    print("\n" + "=" * 50)
    print("✅ FULL DUMP COMPLETED")
    print(f"   Knowledge Bases: {len(kb_names)}")
    print(f"   Knowledge Sources: {len(seen_ks)}")
    print(f"   Indexes: {len(seen_indexes)}")
    print(f"   Indexers: {len(seen_indexers)}")
    print(f"   Data Sources: {len(seen_datasources)}")
    print(f"   Skillsets: {len(seen_skillsets)}")
    print(f"   Synonym Maps: {len(seen_synmaps)}")
    print("=" * 50)


if __name__ == "__main__":
    main()
