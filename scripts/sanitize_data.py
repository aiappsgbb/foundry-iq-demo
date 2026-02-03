#!/usr/bin/env python3
"""
Sanitize exported Azure AI Search data files for safe GitHub commits.

Removes/redacts:
- API keys
- Connection strings  
- Azure service endpoint URLs (search, OpenAI, cognitive services, blob storage)
- OAuth context URLs

Preserves:
- Resource structure and configuration
- Container/folder names
- Deployment IDs and model names
- Field mappings and skillset definitions
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List

# Patterns to redact
AZURE_URL_PATTERNS = [
    r"https://[a-zA-Z0-9\-]+\.search\.windows\.net/?[^\s\"]*",
    r"https://[a-zA-Z0-9\-]+\.openai\.azure\.com/?[^\s\"]*",
    r"https://[a-zA-Z0-9\-]+\.cognitiveservices\.azure\.com/?[^\s\"]*",
    r"https://[a-zA-Z0-9\-]+\.blob\.core\.windows\.net/?[^\s\"]*",
    r"https://[a-zA-Z0-9\-]+\.documents\.azure\.com/?[^\s\"]*",
]

# Keys that should be redacted (case-insensitive match)
SENSITIVE_KEYS = {
    "apikey",
    "api_key",
    "key",
    "connectionstring",
    "connection_string",
    "secret",
    "password",
    "token",
    "accesskey",
    "primarykey",
    "secondarykey",
}

# Keys that contain URLs to redact
URL_KEYS = {
    "@odata.context",
    "resourceuri",
    "resource_uri",
    "uri",
    "url",
    "endpoint",
    "subdomainurl",
}

REDACTED_PLACEHOLDER = "<REDACTED>"
URL_PLACEHOLDER = "<AZURE_ENDPOINT_PLACEHOLDER>"
CONTAINER_PLACEHOLDER = "<BLOB_CONTAINER_PLACEHOLDER>"

# Legacy container names to replace with placeholder
LEGACY_CONTAINER_NAMES = {"kr-demos", "sample-documents", "foundry-iq-data"}


def should_redact_key(key: str) -> bool:
    """Check if a key name indicates a sensitive value."""
    key_lower = key.lower().replace("-", "").replace("_", "")
    return key_lower in {k.replace("_", "") for k in SENSITIVE_KEYS}


def should_redact_url_key(key: str) -> bool:
    """Check if a key name indicates a URL value."""
    key_lower = key.lower().replace("-", "").replace("_", "")
    return key_lower in {k.replace("_", "").replace(".", "") for k in URL_KEYS}


def is_azure_url(value: str) -> bool:
    """Check if a string is an Azure service URL."""
    if not isinstance(value, str):
        return False
    for pattern in AZURE_URL_PATTERNS:
        if re.match(pattern, value, re.IGNORECASE):
            return True
    return False


def sanitize_value(key: str, value: Any) -> Any:
    """Sanitize a single value based on its key and content."""
    if value is None:
        return None

    # Check if key indicates sensitive data
    if should_redact_key(key):
        if isinstance(value, str) and value and value != "null":
            return REDACTED_PLACEHOLDER
        return value

    # Check if key indicates URL data
    if should_redact_url_key(key):
        if isinstance(value, str) and is_azure_url(value):
            return URL_PLACEHOLDER
        return value

    # Check if value is an Azure URL even if key doesn't indicate it
    if isinstance(value, str) and is_azure_url(value):
        return URL_PLACEHOLDER

    return value


def sanitize_dict(data: Dict[str, Any], parent_key: str = "") -> Dict[str, Any]:
    """Recursively sanitize a dictionary."""
    result = {}
    for key, value in data.items():
        if isinstance(value, dict):
            result[key] = sanitize_dict(value, key)
        elif isinstance(value, list):
            result[key] = sanitize_list(key, value)
        else:
            # Special handling for container name fields
            key_lower = key.lower()
            if key_lower in ("name", "containername"):
                # Check if this is a container name field
                if parent_key.lower() == "container" or key_lower == "containername":
                    if isinstance(value, str) and value in LEGACY_CONTAINER_NAMES:
                        result[key] = CONTAINER_PLACEHOLDER
                        continue
            result[key] = sanitize_value(key, value)
    return result


def sanitize_list(parent_key: str, data: List[Any]) -> List[Any]:
    """Recursively sanitize a list."""
    result = []
    for item in data:
        if isinstance(item, dict):
            result.append(sanitize_dict(item, parent_key))
        elif isinstance(item, list):
            result.append(sanitize_list(parent_key, item))
        else:
            result.append(sanitize_value(parent_key, item))
    return result


def sanitize_file(file_path: Path, dry_run: bool = False) -> bool:
    """Sanitize a single JSON file."""
    try:
        with file_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        print(f"  ⚠ Skipping {file_path.name}: {e}")
        return False

    sanitized = sanitize_dict(data, "") if isinstance(data, dict) else sanitize_list("", data)

    if dry_run:
        # Show diff summary
        original = json.dumps(data, indent=2)
        modified = json.dumps(sanitized, indent=2)
        if original != modified:
            print(f"  ✎ Would modify: {file_path.name}")
            return True
        else:
            print(f"  ○ No changes: {file_path.name}")
            return False
    else:
        with file_path.open("w", encoding="utf-8") as f:
            json.dump(sanitized, f, indent=2, ensure_ascii=False)
        print(f"  ✔ Sanitized: {file_path.name}")
        return True


def main():
    parser = argparse.ArgumentParser(
        description="Sanitize Azure AI Search data exports for safe GitHub commits"
    )
    parser.add_argument(
        "--data-dir",
        default="../infra/modules/az_search",
        help="Path to Azure Search config directory (default: ../infra/modules/az_search)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be changed without modifying files",
    )
    parser.add_argument(
        "--exclude",
        nargs="*",
        default=["blob"],
        help="Subdirectories to exclude (default: blob)",
    )
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    if not data_dir.exists():
        print(f"Error: Data directory not found: {data_dir}", file=sys.stderr)
        sys.exit(1)

    exclude_dirs = set(args.exclude)
    modified_count = 0
    total_count = 0

    print("=" * 50)
    print("Sanitizing Azure AI Search Data Exports")
    print("=" * 50)
    if args.dry_run:
        print("(DRY RUN - no files will be modified)\n")
    else:
        print()

    # Process each subdirectory
    for subdir in sorted(data_dir.iterdir()):
        if not subdir.is_dir():
            continue
        if subdir.name in exclude_dirs:
            print(f"⊘ Skipping excluded directory: {subdir.name}/")
            continue

        json_files = list(subdir.glob("*.json"))
        if not json_files:
            continue

        print(f"\n► {subdir.name}/")
        for json_file in sorted(json_files):
            total_count += 1
            if sanitize_file(json_file, dry_run=args.dry_run):
                modified_count += 1

    print("\n" + "=" * 50)
    action = "Would modify" if args.dry_run else "Sanitized"
    print(f"✅ {action} {modified_count}/{total_count} files")
    print("=" * 50)

    if args.dry_run and modified_count > 0:
        print("\nRun without --dry-run to apply changes.")


if __name__ == "__main__":
    main()
