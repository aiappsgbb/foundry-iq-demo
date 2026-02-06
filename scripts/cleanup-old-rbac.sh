#!/bin/bash
# Cleanup script: Remove RBAC role assignments previously created by postprovision.sh
# so that Bicep can recreate them with deterministic GUIDs.
#
# This script is idempotent - safe to run multiple times.
# Run ONCE before the next `azd provision`, then delete this script.
#
# Usage: bash scripts/cleanup-old-rbac.sh

set -e

echo "======================================"
echo "Cleanup: Old RBAC Role Assignments"
echo "======================================"
echo ""

# Determine resource group
RG="${AZURE_RESOURCE_GROUP:-}"
if [ -z "$RG" ]; then
    # Try azd
    RG=$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || echo "")
fi
if [ -z "$RG" ]; then
    echo "Error: Set AZURE_RESOURCE_GROUP or run inside an azd environment."
    exit 1
fi
echo "Resource Group: $RG"

# Get SWA principal ID
SWA_NAME=$(az staticwebapp list -g "$RG" --query "[0].name" -o tsv 2>/dev/null || echo "")
if [ -z "$SWA_NAME" ]; then
    echo "No Static Web App found in $RG — nothing to clean up."
    exit 0
fi

PRINCIPAL_ID=$(az staticwebapp show -n "$SWA_NAME" -g "$RG" --query "identity.principalId" -o tsv 2>/dev/null || echo "")
if [ -z "$PRINCIPAL_ID" ] || [ "$PRINCIPAL_ID" = "null" ]; then
    echo "SWA '$SWA_NAME' has no managed identity — nothing to clean up."
    exit 0
fi
echo "SWA Principal: $PRINCIPAL_ID"
echo ""

# Role GUIDs to clean up
SEARCH_ROLE="8ebe5a00-799e-43f5-93ac-243d3dce84a7"   # Search Index Data Contributor
STORAGE_ROLE="ba92f5b4-2d11-453d-a403-e96b0029c9fe"  # Storage Blob Data Contributor
COG_ROLE="a97b65f3-24c7-4388-baec-2e87135dc908"      # Cognitive Services User

# Delete all role assignments for this principal in the resource group
echo "Removing role assignments for principal $PRINCIPAL_ID..."

ASSIGNMENTS=$(az role assignment list \
    --assignee "$PRINCIPAL_ID" \
    --resource-group "$RG" \
    --query "[?roleDefinitionId.contains(@, '$SEARCH_ROLE') || roleDefinitionId.contains(@, '$STORAGE_ROLE') || roleDefinitionId.contains(@, '$COG_ROLE')].id" \
    -o tsv 2>/dev/null || echo "")

if [ -z "$ASSIGNMENTS" ]; then
    # Fallback: list all assignments for this principal and filter
    ASSIGNMENTS=$(az role assignment list \
        --assignee "$PRINCIPAL_ID" \
        --resource-group "$RG" \
        --query "[].id" \
        -o tsv 2>/dev/null || echo "")
fi

if [ -z "$ASSIGNMENTS" ]; then
    echo "  No role assignments found — nothing to clean up."
    exit 0
fi

COUNT=0
while IFS= read -r ASSIGNMENT_ID; do
    if [ -n "$ASSIGNMENT_ID" ]; then
        echo "  Deleting: $ASSIGNMENT_ID"
        az role assignment delete --ids "$ASSIGNMENT_ID" --output none 2>/dev/null || echo "    ⚠ Failed (may already be gone)"
        COUNT=$((COUNT + 1))
    fi
done <<< "$ASSIGNMENTS"

echo ""
echo "✓ Removed $COUNT role assignment(s)."
echo ""
echo "Next: Run 'azd provision' — Bicep will recreate them with deterministic GUIDs."
echo ""
