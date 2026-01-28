# Azure Developer CLI (azd) Deployment Guide

This guide explains how to deploy the Foundry IQ Demo application using Azure Developer CLI (azd).

## Prerequisites

1. **Azure Developer CLI (azd)**: Install from [aka.ms/install-azd](https://aka.ms/install-azd)
2. **Azure CLI**: Install from [aka.ms/installazurecli](https://aka.ms/installazurecli)
3. **Node.js 18+**: Required for building the Next.js application
4. **Azure Subscription**: With permissions to create resources

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/aiappsgbb/foundry-iq-demo.git
cd foundry-iq-demo

# 2. Authenticate with Azure
azd auth login

# 3. Initialize and deploy (interactive)
azd up
```

The `azd up` command will:
1. Prompt you to create a new environment (e.g., `dev`, `staging`, `prod`)
2. Prompt you to select an Azure subscription
3. Prompt you to select an Azure location
4. Provision all required Azure resources
5. Deploy the application

## Step-by-Step Deployment

### 1. Initialize the Environment

```bash
# Run the initialization helper script
./scripts/azd-init.sh

# Or initialize manually
azd init
```

### 2. Configure Environment Variables (Optional)

Customize your deployment by setting environment variables:

```bash
# Set the chat model (default: gpt-4o-mini)
azd env set AZURE_CHAT_MODEL gpt-4o-mini

# Set the embedding model (default: text-embedding-3-small)
azd env set AZURE_EMBEDDING_MODEL text-embedding-3-small

# Set the environment type (default: dev)
azd env set AZURE_ENVIRONMENT dev

# Set whether to deploy sample data (default: true)
azd env set AZURE_DEPLOY_SAMPLE_DATA true
```

Available chat models:
- `gpt-4o`, `gpt-4o-mini`
- `gpt-4.1`, `gpt-4.1-mini`, `gpt-4.1-nano`
- `gpt-5`, `gpt-5-mini`, `gpt-5-nano`

Available embedding models:
- `text-embedding-ada-002`
- `text-embedding-3-small`
- `text-embedding-3-large`

### 3. Provision Infrastructure

```bash
azd provision
```

This creates the following Azure resources:
- **Azure AI Search**: For knowledge base indexing and retrieval
- **Azure OpenAI**: For embeddings and chat completions
- **Azure Storage Account**: For document storage
- **Azure AI Foundry Hub & Project**: For agent orchestration
- **Azure Static Web App**: For hosting the Next.js application

### 4. Deploy the Application

```bash
azd deploy
```

This will:
1. Build the Next.js application
2. Deploy to Azure Static Web Apps
3. Configure environment variables automatically

## Managing Multiple Environments

```bash
# List all environments
azd env list

# Create a new environment
azd env new staging

# Switch to a different environment
azd env select staging

# Delete an environment
azd env delete staging
```

## Viewing Deployment Information

```bash
# Show environment values
azd env get-values

# Show deployed resources
azd show
```

## Updating the Deployment

After making code changes:

```bash
# Deploy only (no infrastructure changes)
azd deploy

# Or provision and deploy together
azd up
```

## Cleaning Up

To delete all deployed resources:

```bash
azd down
```

⚠️ **Warning**: This will permanently delete all resources and data in the environment.

## Troubleshooting

### Authentication Issues

```bash
# Re-authenticate with Azure
azd auth login

# Clear cached credentials
azd auth logout
azd auth login
```

### Deployment Failures

Check the deployment logs:

```bash
# View recent deployments
az staticwebapp list-deployments --name <app-name> --resource-group <rg-name>
```

### RBAC Permission Issues

The post-provision hook automatically configures RBAC permissions. If issues persist:

```bash
# Run the RBAC configuration manually
export AZURE_RESOURCE_GROUP=<your-resource-group>
./infra/hooks/postprovision.sh
```

### Environment Variable Issues

```bash
# View all environment variables
azd env get-values

# Refresh environment from Azure
azd env refresh
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Static Web App                      │
│                      (Next.js Application)                       │
└─────────────────────┬───────────────────────┬───────────────────┘
                      │                       │
                      ▼                       ▼
        ┌─────────────────────┐   ┌─────────────────────┐
        │   Azure AI Search   │   │    Azure OpenAI     │
        │  (Knowledge Bases)  │   │ (Embeddings & Chat) │
        └─────────────────────┘   └─────────────────────┘
                      │                       │
                      ▼                       │
        ┌─────────────────────┐               │
        │  Azure Blob Storage │               │
        │   (Documents)       │               │
        └─────────────────────┘               │
                      │                       │
                      ▼                       ▼
        ┌─────────────────────────────────────────────┐
        │         Azure AI Foundry Project            │
        │        (Agent Orchestration)                │
        └─────────────────────────────────────────────┘
```

## Cost Estimation

| Environment | Estimated Monthly Cost |
|-------------|----------------------|
| dev         | $100-150            |
| staging     | $250-350            |
| prod        | $500+               |

Costs vary based on usage, region, and selected SKUs.

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure OpenAI Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
- [Azure Static Web Apps Documentation](https://learn.microsoft.com/azure/static-web-apps/)
