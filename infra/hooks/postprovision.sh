#!/bin/bash

# Post-provision hook for Azure Developer CLI (azd)
# 
# This script runs AFTER Azure infrastructure provisioning to deploy Azure AI Search
# knowledge sources and knowledge bases via REST API.
#
# ARCHITECTURE NOTE:
# - RBAC role assignments are now handled in Bicep (infra/modules/rbac.bicep)
# - Blob container creation is now handled in Bicep (infra/modules/storage.bicep)
# - This script ONLY deploys Azure AI Search objects (not supported in Bicep/ARM)
#
# Usage:
#   ./postprovision.sh           # Run full provisioning (Python script for Search objects)
#   ./postprovision.sh --skip-search  # Skip Search objects deployment

set -e

# Parse command line arguments
SKIP_SEARCH=false
for arg in "$@"; do
    case $arg in
        --skip-search)
            SKIP_SEARCH=true
            shift
            ;;
    esac
done

echo "======================================"
echo "Post-Provision Configuration"
echo "======================================"
echo ""

# azd provides these environment variables from the provisioned infrastructure
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

echo "[INFO] RBAC role assignments are configured via Bicep (infra/modules/rbac.bicep)"
echo "[INFO] Blob containers are created via Bicep (infra/modules/storage.bicep)"
echo ""

# ============================================
# Deploy Azure AI Search Objects
# ============================================
# Knowledge Sources and Knowledge Bases are NOT supported in ARM/Bicep.
# They must be deployed via REST API (Azure AI Search 2025-11-01-preview).

if [ "$SKIP_SEARCH" = true ]; then
    echo "[1/1] Skipping Azure AI Search Objects deployment (--skip-search mode)"
    echo ""
    echo "======================================"
    echo "✓ Post-Provision Configuration Complete!"
    echo "======================================"
    exit 0
fi

echo "[1/1] Deploying Azure AI Search Objects..."
echo "      (Knowledge Sources and Knowledge Bases via REST API)"
echo ""

# Run Python script for Knowledge Sources and Knowledge Bases deployment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/configure_search_objects.py"
REQUIREMENTS_FILE="$SCRIPT_DIR/requirements.txt"

if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "  ✗ ERROR: Python script not found: $PYTHON_SCRIPT"
    echo "    Azure Search knowledge bases and sources cannot be configured."
    exit 1
fi

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
# These are discovered by the script using Azure Management APIs
export AZURE_RESOURCE_GROUP
export AZURE_SEARCH_SERVICE_NAME="${AZURE_SEARCH_SERVICE_NAME:-}"
export AZURE_STORAGE_ACCOUNT_NAME="${AZURE_STORAGE_ACCOUNT_NAME:-}"
export AZURE_OPENAI_NAME="${AZURE_OPENAI_NAME:-}"
export AZURE_BLOB_CONTAINER_NAME="${AZURE_BLOB_CONTAINER_NAME:-foundry-iq-data}"

# Run the Python script
$PYTHON_CMD "$PYTHON_SCRIPT"
PYTHON_EXIT_CODE=$?

if [ $PYTHON_EXIT_CODE -ne 0 ]; then
    echo "  ✗ ERROR: Python script failed with exit code $PYTHON_EXIT_CODE"
    echo "    Azure Search knowledge bases and sources were NOT deployed."
    exit 1
fi

echo ""
echo "======================================"
echo "✓ Post-Provision Configuration Complete!"
echo "======================================"
echo ""
echo "What was configured:"
echo "  ✓ Knowledge Sources (via REST API)"
echo "  ✓ Knowledge Bases (via REST API)"
echo ""
echo "What is handled by Bicep:"
echo "  ✓ RBAC Role Assignments (infra/modules/rbac.bicep)"
echo "  ✓ Blob Containers (infra/modules/storage.bicep)"
echo ""
echo "Next steps:"
echo "  1. Run 'azd deploy' to deploy the application"
echo "  2. Visit your Static Web App URL"
echo ""
