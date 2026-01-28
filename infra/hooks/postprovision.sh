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

# Role GUIDs
COGNITIVE_SERVICES_USER="a97b65f3-24c7-4388-baec-2e87135dc908"
SEARCH_INDEX_DATA_CONTRIBUTOR="8ebe5a00-799e-43f5-93ac-243d3dce84a7"
STORAGE_BLOB_DATA_CONTRIBUTOR="ba92f5b4-2d11-453d-a403-e96b0029c9fe"

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
