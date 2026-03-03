#!/bin/bash

# Azure Developer CLI (azd) Initialization Helper
# This script helps set up the azd environment with proper configuration

set -e

echo "======================================"
echo "Azure Developer CLI (azd) Setup"
echo "======================================"
echo ""

# Check if azd is installed
if ! command -v azd &> /dev/null; then
    echo "Error: Azure Developer CLI (azd) is not installed."
    echo ""
    echo "Install azd using one of these methods:"
    echo "  Windows (winget): winget install microsoft.azd"
    echo "  macOS (Homebrew): brew tap azure/azd && brew install azd"
    echo "  Linux (script):   curl -fsSL https://aka.ms/install-azd.sh | bash"
    echo ""
    echo "More info: https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd"
    exit 1
fi

echo "✓ azd is installed: $(azd version)"
echo ""

# Check if user is logged in
echo "Checking Azure authentication..."
if ! azd auth login --check-status &> /dev/null; then
    echo "You need to log in to Azure."
    echo "Running: azd auth login"
    azd auth login
fi
echo "✓ Azure authentication configured"
echo ""

# Initialize environment if not already done
if [ ! -d ".azure" ]; then
    echo "Initializing azd environment..."
    echo ""
    echo "You'll be prompted to:"
    echo "  1. Enter an environment name (e.g., 'dev', 'staging', 'prod')"
    echo "  2. Select an Azure subscription"
    echo "  3. Select an Azure location"
    echo ""
    azd init
else
    echo "✓ azd environment already initialized"
    echo ""
    echo "Current environments:"
    azd env list
fi

echo ""
echo "======================================"
echo "Next Steps"
echo "======================================"
echo ""
echo "1. Configure optional environment variables:"
echo "   azd env set AZURE_CHAT_MODEL gpt-4o-mini"
echo "   azd env set AZURE_EMBEDDING_MODEL text-embedding-3-small"
echo "   azd env set AZURE_ENVIRONMENT dev"
echo ""
echo "2. Provision Azure infrastructure:"
echo "   azd provision"
echo ""
echo "3. Deploy the application:"
echo "   azd deploy"
echo ""
echo "Or do both in one command:"
echo "   azd up"
echo ""
echo "For more information, run: azd --help"
echo ""
