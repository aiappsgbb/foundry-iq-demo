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
    echo "Warning: Static Web App has no managed identity. Enabling..."
    az staticwebapp identity assign -n "$STATIC_WEB_APP_NAME" -g "$AZURE_RESOURCE_GROUP" --output none
    STATIC_WEB_APP_PRINCIPAL=$(az staticwebapp show -n "$STATIC_WEB_APP_NAME" -g "$AZURE_RESOURCE_GROUP" --query "identity.principalId" -o tsv)
fi

echo "✓ Static Web App Principal ID: $STATIC_WEB_APP_PRINCIPAL"

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
    az role assignment create \
        --assignee "$STATIC_WEB_APP_PRINCIPAL" \
        --role "$SEARCH_INDEX_DATA_CONTRIBUTOR" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Search/searchServices/$SEARCH_SERVICE_NAME" \
        --output none 2>/dev/null || echo "  (Search role already assigned or failed)"
    echo "✓ Search Index Data Contributor role assigned"
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
    az role assignment create \
        --assignee "$STATIC_WEB_APP_PRINCIPAL" \
        --role "$STORAGE_BLOB_DATA_CONTRIBUTOR" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
        --output none 2>/dev/null || echo "  (Storage role already assigned or failed)"
    echo "✓ Storage Blob Data Contributor role assigned"
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
    az role assignment create \
        --assignee "$STATIC_WEB_APP_PRINCIPAL" \
        --role "$COGNITIVE_SERVICES_USER" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$OPENAI_NAME" \
        --output none 2>/dev/null || echo "  (OpenAI role already assigned or failed)"
    echo "✓ Cognitive Services User role assigned"
else
    echo "⚠ No OpenAI service found, skipping RBAC"
fi

# ============================================
# Step 5: Deploy Azure AI Search Objects
# ============================================
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
    # Get bearer token for Search API
    SEARCH_TOKEN=$(az account get-access-token --resource "https://search.azure.com" --query "accessToken" -o tsv 2>/dev/null || echo "")
    
    if [ -z "$SEARCH_TOKEN" ]; then
        echo "⚠ Could not get Search bearer token, skipping Azure Search deployment"
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
        
        echo "  Configuration:"
        echo "    Search Endpoint: $SEARCH_ENDPOINT"
        [ -n "$STORAGE_CONNECTION_STRING" ] && echo "    Storage: Connected" || echo "    Storage: Not available"
        [ -n "$OPENAI_ENDPOINT" ] && echo "    OpenAI Endpoint: $OPENAI_ENDPOINT" || echo "    OpenAI: Not available"
        
        # Find Azure Search config directory
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
        AZ_SEARCH_DIR="$REPO_ROOT/infra/modules/az_search"
        
        API_VERSION="2025-11-01-preview"
        
        # Function to replace placeholders in JSON content
        replace_placeholders() {
            local content="$1"
            
            # Replace endpoint placeholders
            if [ -n "$OPENAI_ENDPOINT" ]; then
                content=$(echo "$content" | sed "s|<AZURE_ENDPOINT_PLACEHOLDER>|$OPENAI_ENDPOINT|g")
            fi
            
            # Replace API key placeholders (for OpenAI in skillsets/knowledge-sources)
            if [ -n "$OPENAI_KEY" ]; then
                content=$(echo "$content" | sed "s|\"apiKey\": \"<REDACTED>\"|\"apiKey\": \"$OPENAI_KEY\"|g")
            fi
            
            # Replace connection string placeholders (for datasources)
            if [ -n "$STORAGE_CONNECTION_STRING" ]; then
                # Escape special characters in connection string for sed
                escaped_conn=$(printf '%s\n' "$STORAGE_CONNECTION_STRING" | sed 's/[&/\]/\\&/g')
                content=$(echo "$content" | sed "s|\"connectionString\": \"<REDACTED>\"|\"connectionString\": \"$escaped_conn\"|g")
            fi
            
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
                
                # Read and process content
                local content=$(cat "$json_file")
                content=$(replace_placeholders "$content")
                
                # PUT to Azure Search - capture both response body and HTTP code
                local response_file=$(mktemp)
                local http_code=$(curl -s -w "%{http_code}" \
                    -o "$response_file" \
                    -X PUT "${SEARCH_ENDPOINT}/${api_path}/${obj_name}?api-version=${API_VERSION}" \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $SEARCH_TOKEN" \
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
            
            # Deploy in dependency order:
            # 1. Synonym Maps (no dependencies)
            deploy_objects "synonymmaps" "synonymmaps" "Synonym Map"
            
            # 2. Data Sources (no dependencies)
            deploy_objects "datasources" "datasources" "Data Source"
            
            # 3. Indexes (may reference synonym maps)
            deploy_objects "indexes" "indexes" "Index"
            
            # 4. Skillsets (may reference external AI services)
            deploy_objects "skillsets" "skillsets" "Skillset"
            
            # 5. Indexers (depend on indexes, datasources, skillsets)
            deploy_objects "indexers" "indexers" "Indexer"
            
            # 6. Knowledge Sources (depend on indexes, may have indexers)
            deploy_objects "knowledge-sources" "knowledgesources" "Knowledge Source"
            
            # 7. Knowledge Bases (depend on knowledge sources)
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
