#!/bin/bash

# Post-provision hook for Azure Developer CLI (azd)
# This script configures RBAC permissions and sets up the deployed resources
#
# Usage:
#   ./postprovision.sh           # Run full provisioning (RBAC + Azure Search objects)
#   ./postprovision.sh --rbac-only  # Run only RBAC configuration (skip Python/Search objects)

set -e

# Parse command line arguments
RBAC_ONLY=false
for arg in "$@"; do
    case $arg in
        --rbac-only)
            RBAC_ONLY=true
            shift
            ;;
    esac
done

echo "======================================"
echo "Post-Provision Configuration"
if [ "$RBAC_ONLY" = true ]; then
    echo "(RBAC configuration only)"
fi
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
# Use Python script for reliable placeholder replacement and Azure SDK access

# Skip this step if --rbac-only flag is set (Python runs in GitHub Actions runner, not in azure/cli container)
if [ "$RBAC_ONLY" = true ]; then
    echo ""
    echo "[5/5] Skipping Azure AI Search Objects deployment (--rbac-only mode)"
    echo "      Python script will be run separately in GitHub Actions runner."
    echo ""
    echo "======================================"
    echo "✓ RBAC Configuration Complete!"
    echo "======================================"
    echo ""
    echo "Resources configured:"
    echo "  - Static Web App: $STATIC_WEB_APP_NAME"
    [ -n "$SEARCH_SERVICE_NAME" ] && echo "  - Search Service: $SEARCH_SERVICE_NAME"
    [ -n "$STORAGE_ACCOUNT_NAME" ] && echo "  - Storage Account: $STORAGE_ACCOUNT_NAME"
    [ -n "$OPENAI_NAME" ] && echo "  - OpenAI Service: $OPENAI_NAME"
    echo ""
    exit 0
fi

echo ""
echo "[5/5] Deploying Azure AI Search Objects..."

# Create required blob container before deploying knowledge sources
BLOB_CONTAINER_NAME="${AZURE_BLOB_CONTAINER_NAME:-foundry-iq-data}"
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

# Run Python script for Knowledge Sources and Knowledge Bases deployment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/configure_search_objects.py"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "  ✗ ERROR: Python script not found: $PYTHON_SCRIPT"
    echo "    Azure Search knowledge bases and sources cannot be configured."
    exit 1
fi

echo ""
echo "  Running Python script for Azure AI Search configuration..."

# Check if Python is available
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "  ✗ ERROR: Python not found."
    echo "    Install Python 3.8+ and run: pip install -r $REQUIREMENTS_FILE"
    echo "    Then run: python $PYTHON_SCRIPT"
    exit 1
fi

# Install dependencies if requirements.txt exists
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "  Installing Python dependencies..."
    $PYTHON_CMD -m pip install -r "$REQUIREMENTS_FILE" --quiet 2>/dev/null || {
        echo "  ⚠ Warning: Failed to install some dependencies. Attempting to continue..."
    }
fi

# Export environment variables for the Python script
export AZURE_RESOURCE_GROUP
export AZURE_SEARCH_SERVICE_NAME
export AZURE_STORAGE_ACCOUNT_NAME
export AZURE_OPENAI_NAME
export AZURE_BLOB_CONTAINER_NAME="$BLOB_CONTAINER_NAME"

# Run the Python script
$PYTHON_CMD "$PYTHON_SCRIPT"
PYTHON_EXIT_CODE=$?

if [ $PYTHON_EXIT_CODE -ne 0 ]; then
    echo "  ✗ ERROR: Python script failed with exit code $PYTHON_EXIT_CODE"
    echo "    Azure Search knowledge bases and sources were NOT deployed."
    exit 1
fi

echo "  ✓ Azure AI Search objects deployed successfully"

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
