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
from azure.identity import DefaultAzureCredential
from azure.mgmt.search import SearchManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.cognitiveservices import CognitiveServicesManagementClient

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

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


def get_search_credentials(
    credential: DefaultAzureCredential,
    subscription_id: str,
    resource_group: str,
    search_service_name: str
) -> tuple[str, str]:
    """
    Get Azure AI Search endpoint and admin key using Azure Management API.
    
    Returns:
        Tuple of (endpoint, admin_key)
    """
    client = SearchManagementClient(credential, subscription_id)
    
    # Get the search service
    search_service = client.services.get(resource_group, search_service_name)
    endpoint = f"https://{search_service.name}.search.windows.net"
    
    # Get admin key
    keys = client.admin_keys.get(resource_group, search_service_name)
    admin_key = keys.primary_key
    
    return endpoint, admin_key


def get_storage_connection_string(
    credential: DefaultAzureCredential,
    subscription_id: str,
    resource_group: str,
    storage_account_name: str
) -> str:
    """Get storage account connection string using Azure Management API."""
    client = StorageManagementClient(credential, subscription_id)
    keys = client.storage_accounts.list_keys(resource_group, storage_account_name)
    key = keys.keys[0].value
    
    return (
        f"DefaultEndpointsProtocol=https;"
        f"AccountName={storage_account_name};"
        f"AccountKey={key};"
        f"EndpointSuffix=core.windows.net"
    )


def get_openai_credentials(
    credential: DefaultAzureCredential,
    subscription_id: str,
    resource_group: str,
    openai_name: str
) -> tuple[str, str]:
    """
    Get Azure OpenAI endpoint and API key using Azure Management API.
    
    Returns:
        Tuple of (endpoint, api_key)
    """
    client = CognitiveServicesManagementClient(credential, subscription_id)
    
    # Get account details for endpoint
    account = client.accounts.get(resource_group, openai_name)
    endpoint = account.properties.endpoint.rstrip("/")
    
    # Get API key
    keys = client.accounts.list_keys(resource_group, openai_name)
    api_key = keys.key1
    
    return endpoint, api_key


def get_ai_services_credentials(
    credential: DefaultAzureCredential,
    subscription_id: str,
    resource_group: str
) -> tuple[str | None, str | None]:
    """
    Get Azure AI Services (Cognitive Services multi-service) endpoint and key.
    Used for built-in skills like OCR, language detection.
    
    Returns:
        Tuple of (endpoint, api_key) or (None, None) if not found
    """
    try:
        client = CognitiveServicesManagementClient(credential, subscription_id)
        
        # Find CognitiveServices (multi-service) or AIServices account
        for account in client.accounts.list_by_resource_group(resource_group):
            if account.kind in ("CognitiveServices", "AIServices"):
                endpoint = account.properties.endpoint.rstrip("/")
                keys = client.accounts.list_keys(resource_group, account.name)
                return endpoint, keys.key1
        
        return None, None
    except Exception as e:
        logger.warning(f"  AI Services not available: {e}")
        return None, None


def replace_placeholders_in_knowledge_source(
    source_data: dict[str, Any],
    openai_endpoint: str,
    openai_key: str,
    storage_connection_string: str,
    blob_container: str,
    ai_services_endpoint: str | None,
    ai_services_key: str | None
) -> dict[str, Any]:
    """
    Replace placeholders in knowledge source JSON with actual values.
    
    Handles:
    - connectionString for blob storage
    - containerName placeholder
    - Azure OpenAI endpoints and keys for embedding models
    - AI Services endpoints and keys
    """
    # Remove OData metadata (not allowed in PUT requests)
    source_data.pop("@odata.context", None)
    source_data.pop("@odata.etag", None)
    
    # Process Azure Blob parameters
    if "azureBlobParameters" in source_data and source_data["azureBlobParameters"]:
        blob_params = source_data["azureBlobParameters"]
        
        # Set connection string
        if blob_params.get("connectionString") in ("<REDACTED>", None, ""):
            blob_params["connectionString"] = storage_connection_string
        
        # Set container name
        if blob_params.get("containerName") == "<BLOB_CONTAINER_PLACEHOLDER>":
            blob_params["containerName"] = blob_container
        
        # Process ingestion parameters
        if "ingestionParameters" in blob_params and blob_params["ingestionParameters"]:
            ingest_params = blob_params["ingestionParameters"]
            
            # Embedding model (Azure OpenAI)
            if "embeddingModel" in ingest_params and ingest_params["embeddingModel"]:
                embed_model = ingest_params["embeddingModel"]
                if "azureOpenAIParameters" in embed_model and embed_model["azureOpenAIParameters"]:
                    aoai_params = embed_model["azureOpenAIParameters"]
                    if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        aoai_params["resourceUri"] = openai_endpoint
                    if aoai_params.get("apiKey") == "<REDACTED>":
                        aoai_params["apiKey"] = openai_key
            
            # Chat completion model (Azure OpenAI)
            if "chatCompletionModel" in ingest_params and ingest_params["chatCompletionModel"]:
                chat_model = ingest_params["chatCompletionModel"]
                if "azureOpenAIParameters" in chat_model and chat_model["azureOpenAIParameters"]:
                    aoai_params = chat_model["azureOpenAIParameters"]
                    if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        aoai_params["resourceUri"] = openai_endpoint
                    if aoai_params.get("apiKey") == "<REDACTED>":
                        aoai_params["apiKey"] = openai_key
            
            # AI Services (for built-in skills)
            if "aiServices" in ingest_params and ingest_params["aiServices"]:
                if ai_services_endpoint and ai_services_key:
                    ai_svc = ingest_params["aiServices"]
                    if ai_svc.get("uri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                        ai_svc["uri"] = ai_services_endpoint
                    if ai_svc.get("apiKey") == "<REDACTED>":
                        ai_svc["apiKey"] = ai_services_key
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
                    if aoai_params.get("apiKey") == "<REDACTED>":
                        aoai_params["apiKey"] = openai_key
    
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
                    if aoai_params.get("apiKey") == "<REDACTED>":
                        aoai_params["apiKey"] = openai_key
    
    return source_data


def replace_placeholders_in_knowledge_base(
    kb_data: dict[str, Any],
    openai_endpoint: str,
    openai_key: str
) -> dict[str, Any]:
    """
    Replace placeholders in knowledge base JSON with actual values.
    
    Handles:
    - Azure OpenAI endpoints and keys in models array
    """
    # Remove OData metadata (not allowed in PUT requests)
    kb_data.pop("@odata.context", None)
    kb_data.pop("@odata.etag", None)
    
    # Process models array (inference model for answer synthesis)
    if "models" in kb_data and kb_data["models"]:
        for model in kb_data["models"]:
            if "azureOpenAIParameters" in model and model["azureOpenAIParameters"]:
                aoai_params = model["azureOpenAIParameters"]
                if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                    aoai_params["resourceUri"] = openai_endpoint
                if aoai_params.get("apiKey") == "<REDACTED>":
                    aoai_params["apiKey"] = openai_key
    
    # Process inferenceParameters (older schema)
    if "inferenceParameters" in kb_data and kb_data["inferenceParameters"]:
        if "azureOpenAIParameters" in kb_data["inferenceParameters"]:
            aoai_params = kb_data["inferenceParameters"]["azureOpenAIParameters"]
            if aoai_params.get("resourceUri") == "<AZURE_ENDPOINT_PLACEHOLDER>":
                aoai_params["resourceUri"] = openai_endpoint
            if aoai_params.get("apiKey") == "<REDACTED>":
                aoai_params["apiKey"] = openai_key
    
    return kb_data


def deploy_knowledge_source(
    search_endpoint: str,
    search_key: str,
    source_name: str,
    source_data: dict[str, Any]
) -> bool:
    """
    Deploy a knowledge source to Azure AI Search using REST API.
    
    The Python SDK doesn't fully support knowledge sources yet,
    so we use the REST API directly.
    
    Returns:
        True if successful, False otherwise
    """
    url = f"{search_endpoint}/knowledgesources/{source_name}?api-version={API_VERSION}"
    headers = {
        "Content-Type": "application/json",
        "api-key": search_key
    }
    
    try:
        response = requests.put(
            url,
            headers=headers,
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


def deploy_knowledge_base(
    search_endpoint: str,
    search_key: str,
    kb_name: str,
    kb_data: dict[str, Any]
) -> bool:
    """
    Deploy a knowledge base to Azure AI Search using REST API.
    
    Returns:
        True if successful, False otherwise
    """
    url = f"{search_endpoint}/knowledgebases/{kb_name}?api-version={API_VERSION}"
    headers = {
        "Content-Type": "application/json",
        "api-key": search_key
    }
    
    try:
        response = requests.put(
            url,
            headers=headers,
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
    
    logger.info(f"  Subscription: {subscription_id}")
    logger.info(f"  Resource Group: {resource_group}")
    logger.info(f"  Search Service: {search_service_name or '(will discover)'}")
    logger.info(f"  Storage Account: {storage_account_name or '(will discover)'}")
    logger.info(f"  OpenAI Account: {openai_name or '(will discover)'}")
    logger.info(f"  Blob Container: {blob_container}")
    
    # Authenticate using DefaultAzureCredential (works with azd login, Azure CLI, managed identity)
    logger.info("")
    logger.info("[2/5] Authenticating with Azure...")
    
    try:
        credential = DefaultAzureCredential()
        # Test credential by getting a token
        credential.get_token("https://management.azure.com/.default")
        logger.info("  ✓ Authentication successful")
    except Exception as e:
        logger.error(f"  ✗ Authentication failed: {e}")
        logger.error("  Ensure you're logged in with 'azd auth login' or 'az login'")
        sys.exit(1)
    
    # Discover resources if not provided
    logger.info("")
    logger.info("[3/5] Retrieving Azure resource credentials...")
    
    try:
        # Get Search credentials
        if not search_service_name:
            logger.info("  Discovering Search service...")
            search_client = SearchManagementClient(credential, subscription_id)
            for service in search_client.services.list_by_resource_group(resource_group):
                search_service_name = service.name
                break
            if not search_service_name:
                logger.error("  ✗ No Search service found in resource group")
                sys.exit(1)
        
        search_endpoint, search_key = get_search_credentials(
            credential, subscription_id, resource_group, search_service_name
        )
        logger.info(f"  ✓ Search: {search_endpoint}")
        
        # Get Storage credentials
        if not storage_account_name:
            logger.info("  Discovering Storage account...")
            storage_client = StorageManagementClient(credential, subscription_id)
            for account in storage_client.storage_accounts.list_by_resource_group(resource_group):
                storage_account_name = account.name
                break
            if not storage_account_name:
                logger.error("  ✗ No Storage account found in resource group")
                sys.exit(1)
        
        storage_connection_string = get_storage_connection_string(
            credential, subscription_id, resource_group, storage_account_name
        )
        logger.info(f"  ✓ Storage: {storage_account_name}")
        
        # Get OpenAI/AI Services credentials (Foundry uses AIServices kind)
        if not openai_name:
            logger.info("  Discovering OpenAI/AI Services account...")
            cog_client = CognitiveServicesManagementClient(credential, subscription_id)
            for account in cog_client.accounts.list_by_resource_group(resource_group):
                # Support both standalone OpenAI and Foundry's AIServices
                if account.kind in ("OpenAI", "AIServices"):
                    openai_name = account.name
                    break
            if not openai_name:
                logger.error("  ✗ No OpenAI or AI Services account found in resource group")
                sys.exit(1)
        
        openai_endpoint, openai_key = get_openai_credentials(
            credential, subscription_id, resource_group, openai_name
        )
        logger.info(f"  ✓ OpenAI: {openai_endpoint}")
        
        # Get AI Services credentials (optional)
        ai_services_endpoint, ai_services_key = get_ai_services_credentials(
            credential, subscription_id, resource_group
        )
        if ai_services_endpoint:
            logger.info(f"  ✓ AI Services: {ai_services_endpoint}")
        else:
            logger.info("  ○ AI Services: Not found (will use free tier for skills)")
        
    except Exception as e:
        logger.error(f"  ✗ Failed to retrieve credentials: {e}")
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
        logger.warning(f"  ⚠ Knowledge sources directory not found: {knowledge_sources_dir}")
    else:
        source_files = sorted(knowledge_sources_dir.glob("*.json"))
        logger.info(f"  Found {len(source_files)} knowledge source(s)")
        
        for source_file in source_files:
            source_name = source_file.stem
            logger.info(f"  Deploying: {source_name}")
            
            try:
                with open(source_file, "r", encoding="utf-8") as f:
                    source_data = json.load(f)
                
                # Replace placeholders with actual values
                source_data = replace_placeholders_in_knowledge_source(
                    source_data,
                    openai_endpoint,
                    openai_key,
                    storage_connection_string,
                    blob_container,
                    ai_services_endpoint,
                    ai_services_key
                )
                
                # Deploy to Azure AI Search
                if deploy_knowledge_source(search_endpoint, search_key, source_name, source_data):
                    logger.info(f"    ✓ {source_name}")
                else:
                    logger.error(f"    ✗ {source_name} - deployment failed")
                    sys.exit(1)
                    
            except Exception as e:
                logger.error(f"    ✗ {source_name} - {e}")
                import traceback
                traceback.print_exc()
                sys.exit(1)
    
    # Deploy Knowledge Bases
    logger.info("")
    logger.info("[5/5] Deploying Knowledge Bases...")
    
    if not knowledge_bases_dir.exists():
        logger.warning(f"  ⚠ Knowledge bases directory not found: {knowledge_bases_dir}")
    else:
        kb_files = sorted(knowledge_bases_dir.glob("*.json"))
        logger.info(f"  Found {len(kb_files)} knowledge base(s)")
        
        for kb_file in kb_files:
            kb_name = kb_file.stem
            logger.info(f"  Deploying: {kb_name}")
            
            try:
                with open(kb_file, "r", encoding="utf-8") as f:
                    kb_data = json.load(f)
                
                # Replace placeholders with actual values
                kb_data = replace_placeholders_in_knowledge_base(
                    kb_data,
                    openai_endpoint,
                    openai_key
                )
                
                # Deploy to Azure AI Search
                if deploy_knowledge_base(search_endpoint, search_key, kb_name, kb_data):
                    logger.info(f"    ✓ {kb_name}")
                else:
                    logger.error(f"    ✗ {kb_name} - deployment failed")
                    sys.exit(1)
                    
            except Exception as e:
                logger.error(f"    ✗ {kb_name} - {e}")
                import traceback
                traceback.print_exc()
                sys.exit(1)
    
    logger.info("")
    logger.info("=" * 50)
    logger.info("✓ Azure AI Search configuration complete!")
    logger.info("=" * 50)
    logger.info("")


if __name__ == "__main__":
    main()
