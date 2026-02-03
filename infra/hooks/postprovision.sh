#!/bin/bash

# Post-provision hook for Azure Developer CLI (azd)
# This script configures RBAC permissions and sets up the deployed resources

set -e

echo "======================================"
echo "Post-Provision Configuration"
echo "======================================"
echo ""

# azd provides these environment variables from the provisioned infrastructure
# These come from the Bicep outputs prefixed with AZURE_
echo "Configuration from azd:"
echo "  Environment: ${AZURE_ENV_NAME:-not set}"
echo "  Resource Group: ${AZURE_RESOURCE_GROUP:-not set}"
echo "  Location: ${AZURE_LOCATION:-not set}"
echo ""

# Verify required environment variables from azd
if [ -z "$AZURE_RESOURCE_GROUP" ]; then
    echo "Error: AZURE_RESOURCE_GROUP is not set. This should be set by azd."
    exit 1
fi

# Get the Static Web App principal ID for RBAC assignments
STATIC_WEB_APP_NAME="${AZURE_STATIC_WEB_APP_NAME:-}"
if [ -z "$STATIC_WEB_APP_NAME" ]; then
    echo "Warning: AZURE_STATIC_WEB_APP_NAME not set, attempting to get from outputs..."
    STATIC_WEB_APP_NAME=$(az staticwebapp list -g "$AZURE_RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
fi

if [ -z "$STATIC_WEB_APP_NAME" ]; then
    echo "Error: Could not determine Static Web App name"
    exit 1
fi

echo "[1/4] Retrieving Static Web App identity..."
STATIC_WEB_APP_PRINCIPAL=$(az staticwebapp show -n "$STATIC_WEB_APP_NAME" -g "$AZURE_RESOURCE_GROUP" --query "identity.principalId" -o tsv 2>/dev/null || echo "")

if [ -z "$STATIC_WEB_APP_PRINCIPAL" ] || [ "$STATIC_WEB_APP_PRINCIPAL" == "null" ]; then
    echo "  Enabling managed identity on Static Web App..."
    az staticwebapp identity assign -n "$STATIC_WEB_APP_NAME" -g "$AZURE_RESOURCE_GROUP" --output none
    STATIC_WEB_APP_PRINCIPAL=$(az staticwebapp show -n "$STATIC_WEB_APP_NAME" -g "$AZURE_RESOURCE_GROUP" --query "identity.principalId" -o tsv)
    echo "✓ Static Web App managed identity enabled"
else
    echo "✓ Static Web App managed identity already enabled (skipped)"
fi
echo "  Principal ID: $STATIC_WEB_APP_PRINCIPAL"

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)

# Role GUIDs (Azure built-in roles)
# Reference: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
COGNITIVE_SERVICES_USER="a97b65f3-24c7-4388-baec-2e87135dc908"      # Cognitive Services User
SEARCH_INDEX_DATA_CONTRIBUTOR="8ebe5a00-799e-43f5-93ac-243d3dce84a7" # Search Index Data Contributor
STORAGE_BLOB_DATA_CONTRIBUTOR="ba92f5b4-2d11-453d-a403-e96b0029c9fe" # Storage Blob Data Contributor

echo ""
echo "[2/4] Configuring Search Service RBAC..."
SEARCH_SERVICE_NAME="${AZURE_SEARCH_SERVICE_NAME:-}"
if [ -z "$SEARCH_SERVICE_NAME" ]; then
    SEARCH_SERVICE_NAME=$(az search service list -g "$AZURE_RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
fi

if [ -n "$SEARCH_SERVICE_NAME" ]; then
    SEARCH_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Search/searchServices/$SEARCH_SERVICE_NAME"
    # Check if role already assigned (idempotent)
    EXISTING_ROLE=$(az role assignment list --assignee "$STATIC_WEB_APP_PRINCIPAL" --role "$SEARCH_INDEX_DATA_CONTRIBUTOR" --scope "$SEARCH_SCOPE" --query "[0].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_ROLE" ]; then
        echo "✓ Search Index Data Contributor role already assigned (skipped)"
    else
        az role assignment create \
            --assignee "$STATIC_WEB_APP_PRINCIPAL" \
            --role "$SEARCH_INDEX_DATA_CONTRIBUTOR" \
            --scope "$SEARCH_SCOPE" \
            --output none 2>/dev/null && echo "✓ Search Index Data Contributor role assigned" || echo "⚠ Search role assignment failed (may already exist)"
    fi
else
    echo "⚠ No Search service found, skipping RBAC"
fi

echo ""
echo "[3/4] Configuring Storage Account RBAC..."
STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT_NAME:-}"
if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    STORAGE_ACCOUNT_NAME=$(az storage account list -g "$AZURE_RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
fi

if [ -n "$STORAGE_ACCOUNT_NAME" ]; then
    STORAGE_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
    # Check if role already assigned (idempotent)
    EXISTING_ROLE=$(az role assignment list --assignee "$STATIC_WEB_APP_PRINCIPAL" --role "$STORAGE_BLOB_DATA_CONTRIBUTOR" --scope "$STORAGE_SCOPE" --query "[0].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_ROLE" ]; then
        echo "✓ Storage Blob Data Contributor role already assigned (skipped)"
    else
        az role assignment create \
            --assignee "$STATIC_WEB_APP_PRINCIPAL" \
            --role "$STORAGE_BLOB_DATA_CONTRIBUTOR" \
            --scope "$STORAGE_SCOPE" \
            --output none 2>/dev/null && echo "✓ Storage Blob Data Contributor role assigned" || echo "⚠ Storage role assignment failed (may already exist)"
    fi
else
    echo "⚠ No Storage account found, skipping RBAC"
fi

echo ""
echo "[4/4] Configuring OpenAI Service RBAC..."
OPENAI_NAME="${AZURE_OPENAI_NAME:-}"
if [ -z "$OPENAI_NAME" ]; then
    OPENAI_NAME=$(az cognitiveservices account list -g "$AZURE_RESOURCE_GROUP" --query "[?kind=='OpenAI'].name | [0]" -o tsv 2>/dev/null || echo "")
fi

if [ -n "$OPENAI_NAME" ]; then
    OPENAI_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$OPENAI_NAME"
    # Check if role already assigned (idempotent)
    EXISTING_ROLE=$(az role assignment list --assignee "$STATIC_WEB_APP_PRINCIPAL" --role "$COGNITIVE_SERVICES_USER" --scope "$OPENAI_SCOPE" --query "[0].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$EXISTING_ROLE" ]; then
        echo "✓ Cognitive Services User role already assigned (skipped)"
    else
        az role assignment create \
            --assignee "$STATIC_WEB_APP_PRINCIPAL" \
            --role "$COGNITIVE_SERVICES_USER" \
            --scope "$OPENAI_SCOPE" \
            --output none 2>/dev/null && echo "✓ Cognitive Services User role assigned" || echo "⚠ OpenAI role assignment failed (may already exist)"
    fi
else
    echo "⚠ No OpenAI service found, skipping RBAC"
fi

# ============================================
# Step 5: Deploy Azure AI Search Objects
# ============================================
# NOTE: All Azure Search operations are idempotent:
# - PUT creates resource if not exists, updates if exists
# - Running this script multiple times is safe
echo ""
echo "[5/5] Deploying Azure AI Search Objects..."

# Get Search endpoint and credentials
SEARCH_ENDPOINT="${AZURE_SEARCH_ENDPOINT:-}"
if [ -z "$SEARCH_ENDPOINT" ] && [ -n "$SEARCH_SERVICE_NAME" ]; then
    SEARCH_ENDPOINT="https://${SEARCH_SERVICE_NAME}.search.windows.net"
fi

if [ -z "$SEARCH_ENDPOINT" ]; then
    echo "⚠ No Search endpoint available, skipping Azure Search deployment"
else
    # Get Search Admin API Key (required for management operations like creating indexes, knowledge bases)
    SEARCH_ADMIN_KEY=""
    if [ -n "$SEARCH_SERVICE_NAME" ]; then
        SEARCH_ADMIN_KEY=$(az search admin-key show \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --service-name "$SEARCH_SERVICE_NAME" \
            --query "primaryKey" -o tsv 2>/dev/null || echo "")
    fi
    
    if [ -z "$SEARCH_ADMIN_KEY" ]; then
        echo "⚠ Could not get Search admin key, skipping Azure Search deployment"
        echo "  Ensure you have 'Search Service Contributor' role on the Search service"
    else
        # Get Storage connection string for data sources
        STORAGE_CONNECTION_STRING=""
        if [ -n "$STORAGE_ACCOUNT_NAME" ]; then
            STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
                -n "$STORAGE_ACCOUNT_NAME" \
                -g "$AZURE_RESOURCE_GROUP" \
                --query "connectionString" -o tsv 2>/dev/null || echo "")
        fi
        
        # Get OpenAI endpoint and key
        OPENAI_ENDPOINT=""
        OPENAI_KEY=""
        if [ -n "$OPENAI_NAME" ]; then
            OPENAI_ENDPOINT=$(az cognitiveservices account show \
                -n "$OPENAI_NAME" \
                -g "$AZURE_RESOURCE_GROUP" \
                --query "properties.endpoint" -o tsv 2>/dev/null || echo "")
            OPENAI_KEY=$(az cognitiveservices account keys list \
                -n "$OPENAI_NAME" \
                -g "$AZURE_RESOURCE_GROUP" \
                --query "key1" -o tsv 2>/dev/null || echo "")
        fi
        
        # Remove trailing slash from OpenAI endpoint if present
        OPENAI_ENDPOINT="${OPENAI_ENDPOINT%/}"
        
        # Get AI Services (Cognitive Services multi-service) endpoint and key
        # This is different from Azure OpenAI - used for built-in skills like OCR, language detection
        AI_SERVICES_NAME=$(az cognitiveservices account list -g "$AZURE_RESOURCE_GROUP" \
            --query "[?kind=='CognitiveServices'].name | [0]" -o tsv 2>/dev/null || echo "")
        AI_SERVICES_ENDPOINT=""
        AI_SERVICES_KEY=""
        if [ -n "$AI_SERVICES_NAME" ]; then
            AI_SERVICES_ENDPOINT=$(az cognitiveservices account show \
                -n "$AI_SERVICES_NAME" \
                -g "$AZURE_RESOURCE_GROUP" \
                --query "properties.endpoint" -o tsv 2>/dev/null || echo "")
            AI_SERVICES_KEY=$(az cognitiveservices account keys list \
                -n "$AI_SERVICES_NAME" \
                -g "$AZURE_RESOURCE_GROUP" \
                --query "key1" -o tsv 2>/dev/null || echo "")
            AI_SERVICES_ENDPOINT="${AI_SERVICES_ENDPOINT%/}"
        fi
        
        echo "  Configuration:"
        echo "    Search Endpoint: $SEARCH_ENDPOINT"
        echo "    Search Admin Key: ****"
        [ -n "$STORAGE_CONNECTION_STRING" ] && echo "    Storage: Connected" || echo "    Storage: Not available"
        [ -n "$OPENAI_ENDPOINT" ] && echo "    OpenAI Endpoint: $OPENAI_ENDPOINT" || echo "    OpenAI: Not available"
        [ -n "$OPENAI_KEY" ] && echo "    OpenAI Key: ****" || echo "    OpenAI Key: Not available"
        [ -n "$AI_SERVICES_ENDPOINT" ] && echo "    AI Services Endpoint: $AI_SERVICES_ENDPOINT" || echo "    AI Services: Not available (skillsets will use free tier)"
        [ -n "$AI_SERVICES_KEY" ] && echo "    AI Services Key: ****" || true
        
        # Find Azure Search config directory
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        AZ_SEARCH_DIR="$REPO_ROOT/infra/modules/az_search"
        
        API_VERSION="2025-11-01-preview"
        
        # Default blob container name for all datasources/knowledge-sources
        # Can be overridden via AZURE_BLOB_CONTAINER_NAME environment variable
        BLOB_CONTAINER_NAME="${AZURE_BLOB_CONTAINER_NAME:-foundry-iq-data}"
        echo "    Blob Container: $BLOB_CONTAINER_NAME"
        
        # ============================================
        # Create required blob container before deploying datasources
        # ============================================
        if [ -n "$STORAGE_ACCOUNT_NAME" ]; then
            echo ""
            echo "  Creating blob container..."
            
            # Check if container exists (idempotent)
            EXISTS=$(az storage container exists \
                --account-name "$STORAGE_ACCOUNT_NAME" \
                --name "$BLOB_CONTAINER_NAME" \
                --auth-mode login \
                --query "exists" -o tsv 2>/dev/null || echo "false")
            
            if [ "$EXISTS" = "true" ]; then
                echo "    ✓ Container '$BLOB_CONTAINER_NAME' already exists (skipped)"
            else
                az storage container create \
                    --account-name "$STORAGE_ACCOUNT_NAME" \
                    --name "$BLOB_CONTAINER_NAME" \
                    --auth-mode login \
                    --output none 2>/dev/null && echo "    ✓ Container '$BLOB_CONTAINER_NAME' created" || echo "    ⚠ Failed to create container"
            fi
        fi
        
        # Function to replace placeholders in JSON content
        replace_placeholders() {
            local content="$1"
            local object_type="$2"  # datasources, skillsets, knowledge-sources, etc.
            
            # Use jq for all replacements - safer and handles nested structures
            # Build a jq filter based on object type
            
            case "$object_type" in
                "datasources")
                    # Datasources: set credentials.connectionString and container name
                    content=$(echo "$content" | jq \
                        --arg cs "${STORAGE_CONNECTION_STRING:-}" \
                        --arg container "${BLOB_CONTAINER_NAME:-}" '
                        # Set connection string
                        if $cs != "" then .credentials.connectionString = $cs else . end |
                        # Replace container name placeholder
                        if .container.name == "<BLOB_CONTAINER_PLACEHOLDER>" and $container != "" then
                            .container.name = $container
                        else . end
                    ')
                    ;;
                    
                "skillsets")
                    # Skillsets: replace apiKey, key, resourceUri, uri, subdomainUrl in various locations
                    # NOTE: cognitiveServices uses AI Services (multi-service), not OpenAI
                    content=$(echo "$content" | jq \
                        --arg endpoint "${OPENAI_ENDPOINT:-}" \
                        --arg apikey "${OPENAI_KEY:-}" \
                        --arg ai_endpoint "${AI_SERVICES_ENDPOINT:-}" \
                        --arg ai_key "${AI_SERVICES_KEY:-}" '
                        # Walk through all skills and replace placeholders
                        (.skills // []) |= map(
                            # Replace resourceUri in embedding skills (Azure OpenAI)
                            if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                            # Replace uri in ChatCompletionSkill (Azure OpenAI)
                            if .uri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .uri = $endpoint else . end |
                            # Replace apiKey for Azure OpenAI skills
                            if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                        ) |
                        # Replace cognitiveServices settings (uses AI Services, not OpenAI!)
                        if .cognitiveServices then
                            if $ai_endpoint != "" and $ai_key != "" then
                                .cognitiveServices |= (
                                    if .subdomainUrl == "<AZURE_ENDPOINT_PLACEHOLDER>" then .subdomainUrl = $ai_endpoint else . end |
                                    if .key == "<REDACTED>" then .key = $ai_key else . end
                                )
                            else
                                # No AI Services available - remove cognitiveServices to use free tier
                                del(.cognitiveServices)
                            end
                        else . end
                    ')
                    ;;
                    
                "knowledge-sources")
                    # Knowledge Sources: replace connectionString, containerName, and nested OpenAI params
                    content=$(echo "$content" | jq \
                        --arg cs "${STORAGE_CONNECTION_STRING:-}" \
                        --arg endpoint "${OPENAI_ENDPOINT:-}" \
                        --arg apikey "${OPENAI_KEY:-}" \
                        --arg container "${BLOB_CONTAINER_NAME:-}" '
                        # Azure Blob parameters
                        if .azureBlobParameters then
                            .azureBlobParameters |= (
                                # Connection string
                                if (.connectionString == "<REDACTED>" or .connectionString == null) and $cs != "" then .connectionString = $cs else . end |
                                # Container name placeholder
                                if .containerName == "<BLOB_CONTAINER_PLACEHOLDER>" and $container != "" then .containerName = $container else . end |
                                # Embedding model
                                if .ingestionParameters.embeddingModel.azureOpenAIParameters then
                                    .ingestionParameters.embeddingModel.azureOpenAIParameters |= (
                                        if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                                        if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                                    )
                                else . end |
                                # Chat completion model
                                if .ingestionParameters.chatCompletionModel.azureOpenAIParameters then
                                    .ingestionParameters.chatCompletionModel.azureOpenAIParameters |= (
                                        if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                                        if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                                    )
                                else . end |
                                # AI Services
                                if .ingestionParameters.aiServices then
                                    .ingestionParameters.aiServices |= (
                                        if .uri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .uri = $endpoint else . end |
                                        if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                                    )
                                else . end
                            )
                        else . end |
                        # Indexed OneLake parameters (similar structure)
                        if .indexedOneLakeParameters.ingestionParameters then
                            .indexedOneLakeParameters.ingestionParameters |= (
                                if .embeddingModel.azureOpenAIParameters then
                                    .embeddingModel.azureOpenAIParameters |= (
                                        if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                                        if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                                    )
                                else . end
                            )
                        else . end |
                        # Indexed SharePoint parameters (similar structure)
                        if .indexedSharePointParameters.ingestionParameters then
                            .indexedSharePointParameters.ingestionParameters |= (
                                if .embeddingModel.azureOpenAIParameters then
                                    .embeddingModel.azureOpenAIParameters |= (
                                        if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                                        if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                                    )
                                else . end
                            )
                        else . end
                    ')
                    ;;
                    
                "knowledge-bases")
                    # Knowledge Bases: replace OpenAI params in models array
                    content=$(echo "$content" | jq \
                        --arg endpoint "${OPENAI_ENDPOINT:-}" \
                        --arg apikey "${OPENAI_KEY:-}" '
                        # Models array (inference model)
                        (.models // []) |= map(
                            if .azureOpenAIParameters then
                                .azureOpenAIParameters |= (
                                    if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                                    if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                                )
                            else . end
                        ) |
                        # Also check inferenceParameters if present (older schema)
                        if .inferenceParameters.azureOpenAIParameters then
                            .inferenceParameters.azureOpenAIParameters |= (
                                if .resourceUri == "<AZURE_ENDPOINT_PLACEHOLDER>" and $endpoint != "" then .resourceUri = $endpoint else . end |
                                if .apiKey == "<REDACTED>" and $apikey != "" then .apiKey = $apikey else . end
                            )
                        else . end
                    ')
                    ;;
                    
                *)
                    # For other types (indexes, indexers, synonymmaps)
                    # Just do basic endpoint replacement if needed
                    if [ -n "$OPENAI_ENDPOINT" ]; then
                        content=$(echo "$content" | sed "s|<AZURE_ENDPOINT_PLACEHOLDER>|$OPENAI_ENDPOINT|g")
                    fi
                    ;;
            esac
            
            # Remove OData metadata properties (not allowed in PUT)
            content=$(echo "$content" | jq 'del(.["@odata.context"], .["@odata.etag"])')
            
            echo "$content"
        }
        
        # Function to deploy objects of a specific type
        deploy_objects() {
            local object_type="$1"      # e.g., "indexes", "indexers"
            local api_path="$2"         # e.g., "indexes", "indexers"
            local display_name="$3"     # e.g., "Index", "Indexer"
            local dir_path="$AZ_SEARCH_DIR/$object_type"
            
            if [ ! -d "$dir_path" ]; then
                return
            fi
            
            local file_count=$(find "$dir_path" -name "*.json" 2>/dev/null | wc -l)
            if [ "$file_count" -eq 0 ]; then
                return
            fi
            
            echo ""
            echo "  Deploying ${display_name}s ($file_count files)..."
            
            for json_file in "$dir_path"/*.json; do
                [ -f "$json_file" ] || continue
                local obj_name=$(basename "$json_file" .json)
                
                # Skip files starting with "zava" (legacy test data)
                if [[ "$obj_name" == zava* ]]; then
                    echo "    ○ Skipping: $obj_name (excluded)"
                    continue
                fi
                
                # Read and process content (pass object_type for type-specific replacements)
                local content=$(cat "$json_file")
                content=$(replace_placeholders "$content" "$object_type")
                
                # PUT to Azure Search - capture both response body and HTTP code
                local response_file=$(mktemp)
                local http_code=$(curl -s -w "%{http_code}" \
                    -o "$response_file" \
                    -X PUT "${SEARCH_ENDPOINT}/${api_path}/${obj_name}?api-version=${API_VERSION}" \
                    -H "Content-Type: application/json" \
                    -H "api-key: $SEARCH_ADMIN_KEY" \
                    -d "$content" 2>/dev/null)
                
                if [ "$http_code" = "200" ] || [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
                    echo "    ✓ ${display_name}: $obj_name"
                    rm -f "$response_file"
                else
                    echo ""
                    echo "    ✗ FAILED: ${display_name} '$obj_name' (HTTP $http_code)"
                    echo ""
                    echo "    Request URL: ${SEARCH_ENDPOINT}/${api_path}/${obj_name}?api-version=${API_VERSION}"
                    echo "    Source file: $json_file"
                    echo ""
                    echo "    Response body:"
                    echo "    ----------------------------------------"
                    cat "$response_file" | jq . 2>/dev/null || cat "$response_file"
                    echo ""
                    echo "    ----------------------------------------"
                    rm -f "$response_file"
                    echo ""
                    echo "ERROR: Azure Search deployment failed. Stopping."
                    exit 1
                fi
            done
        }
        
        if [ -d "$AZ_SEARCH_DIR" ]; then
            echo ""
            echo "  Deploying Azure Search objects from: $AZ_SEARCH_DIR"
            
            # Deploy Knowledge Sources and Knowledge Bases only
            # Note: Knowledge Sources with indexed types (azureBlob, indexedOneLake, indexedSharePoint)
            # automatically create their own indexes, datasources, indexers, and skillsets
            
            # 1. Knowledge Sources (creates indexes, datasources, indexers, skillsets automatically)
            deploy_objects "knowledge-sources" "knowledgesources" "Knowledge Source"
            
            # 2. Knowledge Bases (depend on knowledge sources)
            deploy_objects "knowledge-bases" "knowledgebases" "Knowledge Base"
            
            echo ""
            echo "  ✓ Azure Search deployment complete"
        else
            echo "  ⚠ Azure Search config directory not found: $AZ_SEARCH_DIR"
        fi
    fi
fi

echo ""
echo "======================================"
echo "✓ Post-Provision Configuration Complete!"
echo "======================================"
echo ""
echo "Resources configured:"
echo "  - Static Web App: $STATIC_WEB_APP_NAME"
[ -n "$SEARCH_SERVICE_NAME" ] && echo "  - Search Service: $SEARCH_SERVICE_NAME"
[ -n "$STORAGE_ACCOUNT_NAME" ] && echo "  - Storage Account: $STORAGE_ACCOUNT_NAME"
[ -n "$OPENAI_NAME" ] && echo "  - OpenAI Service: $OPENAI_NAME"
echo ""
echo "Next steps:"
echo "  1. Run 'azd deploy' to deploy the application"
echo "  2. Configure additional environment variables if needed"
echo ""
