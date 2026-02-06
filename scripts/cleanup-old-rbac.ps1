<#
.SYNOPSIS
    Remove old RBAC role assignments so Bicep can recreate them with deterministic GUIDs.

.DESCRIPTION
    Cleans up RBAC role assignments previously created by postprovision.sh for the
    Static Web App managed identity. This is needed because the old shell script used
    auto-generated Azure GUIDs, while Bicep uses deterministic guid() names.

    This script is idempotent — safe to run multiple times.
    Run ONCE before the next 'azd provision', then delete this script.

.PARAMETER ResourceGroup
    The Azure resource group name. If not provided, falls back to:
    1. $env:AZURE_RESOURCE_GROUP
    2. azd env get-value AZURE_RESOURCE_GROUP

.EXAMPLE
    .\scripts\cleanup-old-rbac.ps1
    # Uses AZURE_RESOURCE_GROUP env var or azd environment

.EXAMPLE
    .\scripts\cleanup-old-rbac.ps1 -ResourceGroup "rg-foundry-iq-demo"
    # Explicitly specify the resource group
#>

param(
    [Parameter(HelpMessage = "Azure resource group name. Defaults to `$env:AZURE_RESOURCE_GROUP or azd environment.")]
    [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

Write-Host "======================================"
Write-Host "Cleanup: Old RBAC Role Assignments"
Write-Host "======================================"
Write-Host ""

# Determine resource group
$RG = if (-not [string]::IsNullOrEmpty($ResourceGroup)) { $ResourceGroup }
      elseif (-not [string]::IsNullOrEmpty($env:AZURE_RESOURCE_GROUP)) { $env:AZURE_RESOURCE_GROUP }
      else { (azd env get-value AZURE_RESOURCE_GROUP 2>$null) }

if ([string]::IsNullOrEmpty($RG)) {
    Write-Error "Set AZURE_RESOURCE_GROUP or run inside an azd environment."
    exit 1
}
Write-Host "Resource Group: $RG"

# Get SWA principal ID
$SwaName = (az staticwebapp list -g $RG --query "[0].name" -o tsv 2>$null)
if ([string]::IsNullOrEmpty($SwaName)) {
    Write-Host "No Static Web App found in $RG — nothing to clean up."
    exit 0
}

$PrincipalId = (az staticwebapp show -n $SwaName -g $RG --query "identity.principalId" -o tsv 2>$null)
if ([string]::IsNullOrEmpty($PrincipalId) -or $PrincipalId -eq 'null') {
    Write-Host "SWA '$SwaName' has no managed identity — nothing to clean up."
    exit 0
}
Write-Host "SWA Principal: $PrincipalId"
Write-Host ""

# Get all role assignments for this principal in the resource group
Write-Host "Removing role assignments for principal $PrincipalId..."

$AssignmentsJson = az role assignment list `
    --assignee $PrincipalId `
    --resource-group $RG `
    --query "[].id" `
    -o json 2>$null

$Assignments = ($AssignmentsJson | ConvertFrom-Json)

if (-not $Assignments -or $Assignments.Count -eq 0) {
    Write-Host "  No role assignments found — nothing to clean up."
    exit 0
}

$Count = 0
foreach ($AssignmentId in $Assignments) {
    if (-not [string]::IsNullOrEmpty($AssignmentId)) {
        Write-Host "  Removing: $AssignmentId"
        az role assignment delete --ids $AssignmentId --output none 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ⚠ Failed (may already be gone)"
        }
        $Count++
    }
}

Write-Host ""
Write-Host "✓ Removed $Count role assignment(s)."
Write-Host ""
Write-Host "Next: Run 'azd provision' — Bicep will recreate them with deterministic GUIDs."
Write-Host ""
