#!/usr/bin/env python3
"""
Post-Provision Script for Azure AI Search Knowledge Bases and Sources

This script runs after Azure infrastructure provisioning (azd provision) to:
1. Create/update knowledge sources with correct Azure resource endpoints
2. Create/update knowledge bases with correct Azure OpenAI connections

Environment variables are automatically set by azd from Bicep outputs.
The script retrieves additional credentials using Azure Management APIs.
"""

import os
import sys
import json
import logging
from pathlib import Path
from typing import Any

import requests
from azure.identity import AzureDeveloperCliCredential
from azure.mgmt.search import SearchManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient

# Configure logging — suppress verbose Azure SDK HTTP traces
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)
logging.getLogger("azure").setLevel(logging.WARNING)
logging.getLogger("urllib3").setLevel(logging.WARNING)

# API Version for Azure AI Search agentic retrieval
API_VERSION = "2025-11-01-preview"

# Default blob container name
DEFAULT_BLOB_CONTAINER = "foundry-iq-data"


def get_env_or_fail(name: str) -> str:
    """Get environment variable or exit with error."""
    value = os.environ.get(name)
    if not value:
        logger.error(f"ERROR: Required environment variable {name} is not set")
        sys.exit(1)
    return value


def get_search_endpoint(
    credential: AzureDeveloperCliCredential,
    subscription_id: str,
    resource_group: str,
    search_service_name: str
) -> str:
    """
    Get Azure AI Search endpoint using Azure Management API.
    
    Returns:
        Search endpoint URL
    """
    client = SearchManagementClient(credential, subscription_id)
    search_service = client.services.get(resource_group, search_service_name)
    return f"https://{search_service.name}.search.windows.net"


def get_search_bearer_token(credential: AzureDeveloperCliCredential) -> str:
    """Get a Bearer token scoped to Azure AI Search."""
    token = credential.get_token("https://search.azure.com/.default")
    return token.token


def get_storage_resource_id_connection_string(
    subscription_id: str,
    resource_group: str,
    storage_account_name: str
) -> str:
    """Build a ResourceId-based connection string for managed identity access."""
    return (
        f"ResourceId=/subscriptions/{subscription_id}"
        f"/resourceGroups/{resource_group}"
        f"/providers/Microsoft.Storage/storageAccounts/{storage_account_name};"
    )


def get_openai_endpoint(
    credential: AzureDeveloperCliCredential,
    subscription_id: str,
    resource_group: str,
    openai_name: str
) -> str:
    """
    Get Azure OpenAI / AI Services endpoint using Azure Management API.
    No API key needed — knowledge sources use Search service's managed identity.
    """
    client = CognitiveServicesManagementClient(credential, subscription_id)
    account = client.accounts.get(resource_group, openai_name)
    return account.properties.endpoint.rstrip("/")


def get_ai_services_endpoint(
    credential: AzureDeveloperCliCredential,
    subscription_id: str,
    resource_group: str
) -> str | None:
    """
    Get Azure AI Services endpoint (for built-in skills like OCR).
    No API key needed — uses Search service's managed identity.
    """
    try:
        client = CognitiveServicesManagementClient(credential, subscription_id)
        for account in client.accounts.list_by_resource_group(resource_group):
            if account.kind in ("CognitiveServices", "AIServices"):
                return account.properties.endpoint.rstrip("/")
        return None
    except Exception as e:
        logger.warning(f"  AI Services not available: {e}")
        return None


def _substitute_deployment_ids(data: Any, embedding_deployment: str, chat_deployment: str) -> Any:
    """Recursively walk JSON and replace deploymentId/modelName in any azureOpenAIParameters block.
    
    Uses AZURE_EMBEDDING_DEPLOYMENT_NAME and AZURE_CHAT_DEPLOYMENT_NAME from azd env
    to override whatever model names are in the template JSON files.
    """
    if isinstance(data, dict):
        if "azureOpenAIParameters" in data and isinstance(data["azureOpenAIParameters"], dict):
            aoai = data["azureOpenAIParameters"]
            current = aoai.get("deploymentId", "")
            # Embedding models start with "text-embedding"
            if current.startswith("text-embedding") and embedding_deployment:
                aoai["deploymentId"] = embedding_deployment
                if "modelName" in aoai:
                    aoai["modelName"] = embedding_deployment
            elif not current.startswith("text-embedding") and chat_deployment:
                aoai["deploymentId"] = chat_deployment
                if "modelName" in aoai:
                    aoai["modelName"] = chat_deployment
        for v in data.values():
            _substitute_deployment_ids(v, embedding_deployment, chat_deployment)
    elif isinstance(data, list):
        for item in data:
            _substitute_deployment_ids(item, embedding_deployment, chat_deployment)
    return data


def replace_placeholders_in_knowledge_source(
    source_data: dict[str, Any],
    openai_endpoint: str,
    storage_connection_string: str,
    blob_container: str,
    ai_services_endpoint: str | None,
    embedding_deployment: str = "",
    chat_deployment: str = "",
) -> dict[str, Any]:
    """
    Replace placeholders in knowledge source JSON with actual values.
    
    Uses identity-based auth (Search service managed identity) for:
    - Azure OpenAI: apiKey=null, authIdentity=null (system-assigned)
    - Blob Storage: ResourceId connection string
    - AI Services: apiKey=null, identity=null (system-assigned)
    """
    # Remove OData metadata and read-only fields (not allowed in PUT requests)
    source_data.pop("@odata.context", None)
    source_data.pop("@odata.etag", None)
    # createdResources is read-only output — remove if present
    if "azureBlobParameters" in source_data and source_data["azureBlobParameters"]:
        source_data["azureBlobParameters"].pop("createdResources", None)
    
    # Substitute deployment IDs from azd env values
    _substitute_deployment_ids(source_data, embedding_deployment, chat_deployment)
    
    # Process Azure Blob parameters
    if "azureBlobParameters" in source_data and source_data["azureBlobParameters"]:
        blob_params = source_data["azureBlobParameters"]
        
        # Set ResourceId-based connection string (managed identity auth)
        if blob_params.get("connectionString") in ("<REDACTED>", None, ""):
            blob_params["connectionString"] = storage_connection_string
        
        # Set container name
        if blob_params.get("containerName") == "<BLOB_CONTAINER_PLACEHOLDER>":
            blob_params["containerName"] = blob_container
        
        # Process ingestion parameters
        if "ingestionParameters" in blob_params and blob_params["ingestionParameters"]:
            ingest_params = blob_params["ingestionParameters"]
            
            # Embedding model (Azure OpenAI) — identity-based auth
            if "embeddingModel" in ingest_params and ingest_params["embeddingModel"]:
                embed_model = ingest_params["embeddingModel"]
                if "azureOpenAIParameters" in embed_model and embed_model["azureOpenAIParameters"]:
                    aoai_params = embed_model["azureOpenAIParameters"]
                    if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        aoai_params["resourceUri"] = openai_endpoint
                    # Identity-based auth: null apiKey, null authIdentity = system-assigned
                    aoai_params["apiKey"] = None
                    aoai_params["authIdentity"] = None
            
            # Chat completion model (Azure OpenAI) — identity-based auth
            if "chatCompletionModel" in ingest_params and ingest_params["chatCompletionModel"]:
                chat_model = ingest_params["chatCompletionModel"]
                if "azureOpenAIParameters" in chat_model and chat_model["azureOpenAIParameters"]:
                    aoai_params = chat_model["azureOpenAIParameters"]
                    if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        aoai_params["resourceUri"] = openai_endpoint
                    aoai_params["apiKey"] = None
                    aoai_params["authIdentity"] = None
            
            # AI Services (for built-in skills) — identity-based auth
            if "aiServices" in ingest_params and ingest_params["aiServices"]:
                if ai_services_endpoint:
                    ai_svc = ingest_params["aiServices"]
                    if ai_svc.get("uri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        ai_svc["uri"] = ai_services_endpoint
                    # Null apiKey = use Search service's managed identity
                    ai_svc["apiKey"] = None
                else:
                    # No AI Services available - remove to use free tier
                    ingest_params["aiServices"] = None
    
    # Process indexed OneLake parameters (similar structure)
    if "indexedOneLakeParameters" in source_data and source_data["indexedOneLakeParameters"]:
        onelake_params = source_data["indexedOneLakeParameters"]
        if "ingestionParameters" in onelake_params and onelake_params["ingestionParameters"]:
            ingest_params = onelake_params["ingestionParameters"]
            if "embeddingModel" in ingest_params and ingest_params["embeddingModel"]:
                embed_model = ingest_params["embeddingModel"]
                if "azureOpenAIParameters" in embed_model and embed_model["azureOpenAIParameters"]:
                    aoai_params = embed_model["azureOpenAIParameters"]
                    if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        aoai_params["resourceUri"] = openai_endpoint
                    aoai_params["apiKey"] = None
                    aoai_params["authIdentity"] = None
    
    # Process indexed SharePoint parameters (similar structure)
    if "indexedSharePointParameters" in source_data and source_data["indexedSharePointParameters"]:
        sp_params = source_data["indexedSharePointParameters"]
        if "ingestionParameters" in sp_params and sp_params["ingestionParameters"]:
            ingest_params = sp_params["ingestionParameters"]
            if "embeddingModel" in ingest_params and ingest_params["embeddingModel"]:
                embed_model = ingest_params["embeddingModel"]
                if "azureOpenAIParameters" in embed_model and embed_model["azureOpenAIParameters"]:
                    aoai_params = embed_model["azureOpenAIParameters"]
                    if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        aoai_params["resourceUri"] = openai_endpoint
                    aoai_params["apiKey"] = None
                    aoai_params["authIdentity"] = None
    
    return source_data


def replace_placeholders_in_knowledge_base(
    kb_data: dict[str, Any],
    openai_endpoint: str,
    embedding_deployment: str = "",
    chat_deployment: str = "",
) -> dict[str, Any]:
    """
    Replace placeholders in knowledge base JSON with actual values.
    Uses identity-based auth (apiKey=null, authIdentity=null).
    """
    # Remove OData metadata (not allowed in PUT requests)
    kb_data.pop("@odata.context", None)
    kb_data.pop("@odata.etag", None)
    
    # Substitute deployment IDs from azd env values
    _substitute_deployment_ids(kb_data, embedding_deployment, chat_deployment)
    
    # Process models array (inference model for answer synthesis) — identity-based auth
    if "models" in kb_data and kb_data["models"]:
        for model in kb_data["models"]:
            if "azureOpenAIParameters" in model and model["azureOpenAIParameters"]:
                aoai_params = model["azureOpenAIParameters"]
                if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                    aoai_params["resourceUri"] = openai_endpoint
                aoai_params["apiKey"] = None
                aoai_params["authIdentity"] = None
    
    # Process inferenceParameters (older schema) — identity-based auth
    if "inferenceParameters" in kb_data and kb_data["inferenceParameters"]:
        if "azureOpenAIParameters" in kb_data["inferenceParameters"]:
            aoai_params = kb_data["inferenceParameters"]["azureOpenAIParameters"]
            if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                aoai_params["resourceUri"] = openai_endpoint
            aoai_params["apiKey"] = None
            aoai_params["authIdentity"] = None
    
    return kb_data


def _search_headers(bearer_token: str) -> dict[str, str]:
    """Return standard headers for Azure AI Search REST API calls using Entra ID."""
    return {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {bearer_token}",
    }


def knowledge_source_exists(
    search_endpoint: str,
    bearer_token: str,
    source_name: str
) -> bool:
    """
    Check if a knowledge source already exists in Azure AI Search.
    
    Returns:
        True if exists, False otherwise
    """
    url = f"{search_endpoint}/knowledgesources/{source_name}?api-version={API_VERSION}"
    
    try:
        response = requests.get(url, headers=_search_headers(bearer_token), timeout=30)
        return response.status_code == 200
    except requests.RequestException:
        return False


def deploy_knowledge_source(
    search_endpoint: str,
    bearer_token: str,
    source_name: str,
    source_data: dict[str, Any]
) -> bool:
    """
    Deploy a knowledge source to Azure AI Search using REST API.
    
    The Python SDK doesn't fully support knowledge sources yet,
    so we use the REST API directly with Entra ID Bearer tokens.
    
    Returns:
        True if successful, False otherwise
    """
    url = f"{search_endpoint}/knowledgesources/{source_name}?api-version={API_VERSION}"
    
    try:
        response = requests.put(
            url,
            headers=_search_headers(bearer_token),
            json=source_data,
            timeout=60
        )
        
        if response.status_code in (200, 201, 204):
            return True
        else:
            logger.error(f"    HTTP {response.status_code}")
            try:
                error_detail = response.json()
                logger.error(f"    Error: {json.dumps(error_detail, indent=2)}")
            except json.JSONDecodeError:
                logger.error(f"    Response: {response.text}")
            return False
            
    except requests.RequestException as e:
        logger.error(f"    Request failed: {e}")
        return False


def knowledge_base_exists(
    search_endpoint: str,
    bearer_token: str,
    kb_name: str
) -> bool:
    """
    Check if a knowledge base already exists in Azure AI Search.
    
    Returns:
        True if exists, False otherwise
    """
    url = f"{search_endpoint}/knowledgebases/{kb_name}?api-version={API_VERSION}"
    
    try:
        response = requests.get(url, headers=_search_headers(bearer_token), timeout=30)
        return response.status_code == 200
    except requests.RequestException:
        return False


def deploy_knowledge_base(
    search_endpoint: str,
    bearer_token: str,
    kb_name: str,
    kb_data: dict[str, Any]
) -> bool:
    """
    Deploy a knowledge base to Azure AI Search using REST API.
    
    Returns:
        True if successful, False otherwise
    """
    url = f"{search_endpoint}/knowledgebases/{kb_name}?api-version={API_VERSION}"
    
    try:
        response = requests.put(
            url,
            headers=_search_headers(bearer_token),
            json=kb_data,
            timeout=60
        )
        
        if response.status_code in (200, 201, 204):
            return True
        else:
            logger.error(f"    HTTP {response.status_code}")
            try:
                error_detail = response.json()
                logger.error(f"    Error: {json.dumps(error_detail, indent=2)}")
            except json.JSONDecodeError:
                logger.error(f"    Response: {response.text}")
            return False
            
    except requests.RequestException as e:
        logger.error(f"    Request failed: {e}")
        return False


def main():
    """Main entry point for the post-provision script."""
    logger.info("")
    logger.info("=" * 50)
    logger.info("Azure AI Search Knowledge Bases Configuration")
    logger.info("=" * 50)
    logger.info("")
    
    # Get environment variables from azd provision
    logger.info("[1/5] Collecting environment variables from azd...")
    
    # Required variables
    resource_group = get_env_or_fail("AZURE_RESOURCE_GROUP")
    subscription_id = os.environ.get("AZURE_SUBSCRIPTION_ID")
    
    # Get subscription ID from Azure CLI if not set
    if not subscription_id:
        import subprocess
        result = subprocess.run(
            ["az", "account", "show", "--query", "id", "-o", "tsv"],
            capture_output=True,
            text=True
        )
        subscription_id = result.stdout.strip()
        if not subscription_id:
            logger.error("ERROR: Could not determine Azure subscription ID")
            sys.exit(1)
    
    # Optional variables with fallback discovery
    search_service_name = os.environ.get("AZURE_SEARCH_SERVICE_NAME", "")
    storage_account_name = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME", "")
    openai_name = os.environ.get("AZURE_OPENAI_NAME", "")
    blob_container = os.environ.get("AZURE_BLOB_CONTAINER_NAME", DEFAULT_BLOB_CONTAINER)
    
    # Deployed model names from azd env (Bicep outputs → env vars automatically)
    embedding_deployment = os.environ.get("AZURE_EMBEDDING_DEPLOYMENT_NAME", "")
    chat_deployment = os.environ.get("AZURE_CHAT_DEPLOYMENT_NAME", "")
    
    logger.info(f"  Subscription: {subscription_id}")
    logger.info(f"  Resource Group: {resource_group}")
    logger.info(f"  Search Service: {search_service_name or '(will discover)'}")
    logger.info(f"  Storage Account: {storage_account_name or '(will discover)'}")
    logger.info(f"  OpenAI Account: {openai_name or '(will discover)'}")
    logger.info(f"  Blob Container: {blob_container}")
    logger.info(f"  Embedding Model: {embedding_deployment or '(use template default)'}")
    logger.info(f"  Chat Model: {chat_deployment or '(use template default)'}")
    
    # Authenticate using AzureDeveloperCliCredential (matches azd's tenant context)
    logger.info("")
    logger.info("[2/5] Authenticating with Azure (Entra ID via azd)...")
    
    tenant_id = os.environ.get("AZURE_TENANT_ID", "")
    
    try:
        credential = AzureDeveloperCliCredential(tenant_id=tenant_id) if tenant_id else AzureDeveloperCliCredential()
        # Test credential
        credential.get_token("https://management.azure.com/.default")
        logger.info(f"  OK Authentication successful (tenant: {tenant_id or 'default'})")
    except Exception as e:
        logger.error(f"  FAIL Authentication failed: {e}")
        logger.error("  Ensure you're logged in with 'azd auth login'")
        sys.exit(1)
    
    # Discover resources if not provided
    logger.info("")
    logger.info("[3/5] Retrieving Azure resource credentials...")
    
    try:
        # Get Search endpoint (no admin key needed — we use Bearer tokens)
        if not search_service_name:
            logger.info("  Discovering Search service...")
            search_client = SearchManagementClient(credential, subscription_id)
            for service in search_client.services.list_by_resource_group(resource_group):
                search_service_name = service.name
                break
            if not search_service_name:
                logger.error("  FAIL No Search service found in resource group")
                sys.exit(1)
        
        search_endpoint = get_search_endpoint(
            credential, subscription_id, resource_group, search_service_name
        )
        # Get Bearer token for Search data-plane API
        search_token = get_search_bearer_token(credential)
        logger.info(f"  OK Search: {search_endpoint} (Bearer token)")
        
        # Get Storage credentials
        if not storage_account_name:
            logger.info("  Discovering Storage account...")
            storage_client = StorageManagementClient(credential, subscription_id)
            for account in storage_client.storage_accounts.list_by_resource_group(resource_group):
                storage_account_name = account.name
                break
            if not storage_account_name:
                logger.error("  FAIL No Storage account found in resource group")
                sys.exit(1)
        
        storage_connection_string = get_storage_resource_id_connection_string(
            subscription_id, resource_group, storage_account_name
        )
        logger.info(f"  OK Storage: {storage_account_name} (ResourceId auth)")
        
        # Get OpenAI/AI Services endpoint (no key needed — identity-based auth)
        if not openai_name:
            logger.info("  Discovering OpenAI/AI Services account...")
            cog_client = CognitiveServicesManagementClient(credential, subscription_id)
            for account in cog_client.accounts.list_by_resource_group(resource_group):
                # Support both standalone OpenAI and Foundry's AIServices
                if account.kind in ("OpenAI", "AIServices"):
                    openai_name = account.name
                    break
            if not openai_name:
                logger.error("  FAIL No OpenAI or AI Services account found in resource group")
                sys.exit(1)
        
        openai_endpoint = get_openai_endpoint(
            credential, subscription_id, resource_group, openai_name
        )
        logger.info(f"  OK OpenAI: {openai_endpoint} (managed identity auth)")
        
        # Get AI Services endpoint (optional, no key)
        ai_services_endpoint = get_ai_services_endpoint(
            credential, subscription_id, resource_group
        )
        if ai_services_endpoint:
            logger.info(f"  OK AI Services: {ai_services_endpoint} (managed identity auth)")
        else:
            logger.info("  -- AI Services: Not found (will use free tier for skills)")
        
    except Exception as e:
        logger.error(f"  FAIL Failed to retrieve credentials: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    
    # Find config files
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    az_search_dir = repo_root / "infra" / "modules" / "az_search"
    
    knowledge_sources_dir = az_search_dir / "knowledge-sources"
    knowledge_bases_dir = az_search_dir / "knowledge-bases"
    
    # Deploy Knowledge Sources
    logger.info("")
    logger.info("[4/5] Deploying Knowledge Sources...")
    
    if not knowledge_sources_dir.exists():
        logger.warning(f"  WARN Knowledge sources directory not found: {knowledge_sources_dir}")
    else:
        source_files = sorted(knowledge_sources_dir.glob("*.json"))
        logger.info(f"  Found {len(source_files)} knowledge source(s)")
        
        for source_file in source_files:
            source_name = source_file.stem
            logger.info(f"  Processing: {source_name}")
            
            # Always deploy (PUT is idempotent — creates or updates)
            exists = knowledge_source_exists(search_endpoint, search_token, source_name)
            action = "Updating" if exists else "Creating"
            logger.info(f"    {action}: {source_name}")
            
            try:
                with open(source_file, "r", encoding="utf-8") as f:
                    source_data = json.load(f)
                
                # Replace placeholders with actual values (identity-based auth)
                source_data = replace_placeholders_in_knowledge_source(
                    source_data,
                    openai_endpoint,
                    storage_connection_string,
                    blob_container,
                    ai_services_endpoint,
                    embedding_deployment,
                    chat_deployment,
                )
                
                # Deploy to Azure AI Search
                if deploy_knowledge_source(search_endpoint, search_token, source_name, source_data):
                    logger.info(f"    OK {source_name}")
                else:
                    logger.error(f"    FAIL {source_name} - deployment failed")
                    sys.exit(1)
                    
            except Exception as e:
                logger.error(f"    FAIL {source_name} - {e}")
                import traceback
                traceback.print_exc()
                sys.exit(1)
    
    # Deploy Knowledge Bases
    logger.info("")
    logger.info("[5/5] Deploying Knowledge Bases...")
    
    if not knowledge_bases_dir.exists():
        logger.warning(f"  WARN Knowledge bases directory not found: {knowledge_bases_dir}")
    else:
        kb_files = sorted(knowledge_bases_dir.glob("*.json"))
        logger.info(f"  Found {len(kb_files)} knowledge base(s)")
        
        for kb_file in kb_files:
            kb_name = kb_file.stem
            logger.info(f"  Processing: {kb_name}")
            
            # Always deploy (PUT is idempotent — creates or updates)
            exists = knowledge_base_exists(search_endpoint, search_token, kb_name)
            action = "Updating" if exists else "Creating"
            logger.info(f"    {action}: {kb_name}")
            
            try:
                with open(kb_file, "r", encoding="utf-8") as f:
                    kb_data = json.load(f)
                
                # Replace placeholders with actual values (identity-based auth)
                kb_data = replace_placeholders_in_knowledge_base(
                    kb_data,
                    openai_endpoint,
                    embedding_deployment,
                    chat_deployment,
                )
                
                # Deploy to Azure AI Search
                if deploy_knowledge_base(search_endpoint, search_token, kb_name, kb_data):
                    logger.info(f"    OK {kb_name}")
                else:
                    logger.error(f"    FAIL {kb_name} - deployment failed")
                    sys.exit(1)
                    
            except Exception as e:
                logger.error(f"    FAIL {kb_name} - {e}")
                import traceback
                traceback.print_exc()
                sys.exit(1)
    
    logger.info("")
    logger.info("=" * 50)
    logger.info("OK Azure AI Search configuration complete!")
    logger.info("=" * 50)
    logger.info("")


if __name__ == "__main__":
    main()

