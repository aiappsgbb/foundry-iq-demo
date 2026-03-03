#!/usr/bin/env python3
"""Deploy Next.js app to Azure Static Web Apps from a local machine.

This script mirrors what the CI workflow (gbb-demo.yml) does:
  1. Reads the SWA name & resource group from azd environment values
  2. Retrieves the SWA deployment token via Azure CLI
  3. Builds with npm and deploys using the SWA CLI

Prerequisites:
  - Azure CLI logged in         (az login)
  - azd environment provisioned (azd provision)
  - Node.js 18+

Usage:
  python scripts/deploy-swa.py
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def run(cmd: str, *, capture: bool = False) -> str:
    """Run a shell command from the project root."""
    result = subprocess.run(
        cmd,
        shell=True,
        cwd=ROOT,
        capture_output=capture,
        text=True,
    )
    if result.returncode != 0:
        if capture:
            return ""
        sys.exit(result.returncode)
    return result.stdout.strip() if capture else ""


def azd_value(key: str) -> str:
    """Read a value from the azd environment, falling back to env vars."""
    val = os.environ.get(key, "")
    if val:
        return val
    return run(f"azd env get-value {key}", capture=True)


def fatal(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# 1. Resolve resource names from azd environment
# ---------------------------------------------------------------------------
swa_name = azd_value("AZURE_STATIC_WEB_APP_NAME")
if not swa_name:
    fatal(
        "Could not determine AZURE_STATIC_WEB_APP_NAME.\n"
        "       Run 'azd provision' first, or set the env var manually."
    )

resource_group = azd_value("AZURE_RESOURCE_GROUP")
if not resource_group:
    env_name = azd_value("AZURE_ENV_NAME")
    if env_name:
        resource_group = f"rg-{env_name}"
    else:
        fatal(
            "Could not determine AZURE_RESOURCE_GROUP.\n"
            "       Run 'azd provision' first, or set the env var manually."
        )

print(f"Static Web App : {swa_name}")
print(f"Resource Group  : {resource_group}")
print()

# ---------------------------------------------------------------------------
# 2. Retrieve the SWA deployment token
# ---------------------------------------------------------------------------
print("Retrieving deployment token...")
token_json = run(
    f'az staticwebapp secrets list --name "{swa_name}" '
    f'--resource-group "{resource_group}" '
    f'--query "properties.apiKey" -o tsv',
    capture=True,
)
if not token_json:
    fatal(
        "Could not retrieve deployment token.\n"
        "       Make sure the SWA resource exists and you have access."
    )
deployment_token = token_json.strip()
print("Deployment token retrieved.")
print()

# ---------------------------------------------------------------------------
# 3. Build the Next.js application
# ---------------------------------------------------------------------------
print("Building the Next.js application...")
run("npm run build")
print("Build complete.")
print()

# ---------------------------------------------------------------------------
# 4. Install SWA CLI if needed, then deploy
# ---------------------------------------------------------------------------
if not shutil.which("swa"):
    print("SWA CLI not found. Installing globally...")
    run("npm install -g @azure/static-web-apps-cli")
    print()

print("Deploying to Azure Static Web Apps...")
# For hybrid Next.js, point --output-location at the .next build output
# and --app-location at the project root so SWA can resolve the full app.
run(
    f'swa deploy --app-location . --output-location .next'
    f' --deployment-token "{deployment_token}" --env production'
)

print()
print("Deployment complete!")
