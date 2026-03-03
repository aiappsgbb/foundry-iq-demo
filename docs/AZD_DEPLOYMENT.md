# Azure Developer CLI (azd) Deployment Guide

This guide explains how to deploy the Foundry IQ Demo application using Azure Developer CLI (azd). The application deploys to **Azure Container Apps** with a remote Docker build in Azure Container Registry — no local Docker or Node.js required.

## Prerequisites

1. **Azure Developer CLI (azd)**: Install from [aka.ms/install-azd](https://aka.ms/install-azd)
2. **Azure CLI**: Install from [aka.ms/installazurecli](https://aka.ms/installazurecli)
3. **Python 3.8+**: Required for post-provision hooks
4. **Azure Subscription**: With permissions to create resources

> **Note:** Node.js and Docker are **not** required locally. The Docker image is built remotely in Azure Container Registry (ACR).

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/aiappsgbb/foundry-iq-demo.git
cd foundry-iq-demo

# 2. Set up Python virtual environment
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
# source .venv/bin/activate

# 3. Install Python dependencies
pip install -r infra/hooks/requirements.txt

# 4. Authenticate with Azure
azd auth login
az login

# 5. Deploy everything
azd up
```

The `azd up` command will:

1. Prompt you to create a new environment (e.g., `dev`, `staging`, `prod`)
2. Prompt you to select an Azure subscription and location
3. **Provision** all Azure resources via Bicep
4. **Run postprovision hook** — creates Knowledge Sources & Knowledge Bases in Azure AI Search, uploads sample data to blob storage, and configures RBAC
5. **Build** the Docker image remotely in Azure Container Registry
6. **Deploy** the container to Azure Container Apps

## What Gets Deployed

| Resource | SKU | Purpose |
|----------|-----|---------|
| Azure Container Apps | Consumption | Hosts the Next.js application |
| Azure Container Registry | Basic | Stores Docker images |
| Azure AI Search | Basic | Knowledge base indexing and agentic retrieval |
| Azure AI Services (OpenAI) | S0 | Chat (gpt-4o-mini) and embedding (text-embedding-3-large) models |
| Azure AI Foundry Hub & Project | — | Agent orchestration and connections |
| Azure Blob Storage | Standard LRS | Document storage for knowledge sources |
| Log Analytics + App Insights | — | Monitoring and observability |

## Authentication Model

All authentication uses **Entra ID / managed identity** — zero API keys anywhere.

| Connection | Auth Method |
|------------|-------------|
| App → Azure AI Search | Bearer token via `DefaultAzureCredential` |
| App → Azure OpenAI | Managed identity (via Search service) |
| Search → Blob Storage | System-assigned managed identity + RBAC |
| Search → AI Services | System-assigned managed identity + RBAC |
| Postprovision script → Azure | `AzureDeveloperCliCredential` (matches azd tenant) |

**RBAC roles (configured automatically):**
- Container App identity → Search Index Data Contributor, Search Service Contributor, Storage Blob Data Contributor, Cognitive Services User
- Search service identity → Storage Blob Data Reader, Cognitive Services User
- Current user → Storage Blob Data Contributor (for sample data upload)

## Configuration

### Environment Variables

Customize your deployment by setting azd environment variables before running `azd up`:

```bash
# Set the chat model deployment name (default: gpt-4o-mini)
azd env set AZURE_CHAT_DEPLOYMENT_NAME gpt-4o-mini

# Set the embedding model deployment name (default: text-embedding-3-large)
azd env set AZURE_EMBEDDING_DEPLOYMENT_NAME text-embedding-3-large
```

> **Model availability:** Not all models are available in all regions/subscriptions. `gpt-4o-mini` and `text-embedding-3-large` are widely available. The postprovision hook dynamically substitutes deployment names in all search configs.

### Sample Data

The postprovision hook automatically uploads sample documents from `data/blob/foundry-iq-data/` to Azure Blob Storage. These documents are organized into industry folders:

```
foundry-iq-data/
├── manufacturing/manuals/     # Technical manuals (PDFs)
├── manufacturing/ads/         # Airworthiness directives
├── manufacturing/investigations/ # Investigation reports
├── healthcare/labels/         # FDA drug labels
├── healthcare/guidelines/     # Clinical guidelines
├── financial-services/filings/    # SEC filings
└── financial-services/bulletins/  # Financial bulletins
```

Seven knowledge sources and three knowledge bases (manufacturing, healthcare, financial) are created automatically.

## Step-by-Step Deployment

### 1. Initialize the Environment

```bash
azd init
# Select a name for your environment (e.g., "dev")
```

### 2. Provision Infrastructure

```bash
azd provision
```

This creates all Azure resources via Bicep and runs the postprovision hook.

### 3. Deploy the Application

```bash
azd deploy
```

This builds the Docker image remotely in ACR and deploys to Azure Container Apps.

### 4. Verify

After deployment, `azd` prints the app URL. Open it in a browser and navigate to `/test` to query knowledge bases.

> **Note:** After first deployment, indexers need 5-15 minutes to process all documents (OCR + embeddings). Queries will return results after indexing completes.

## Managing Environments

```bash
# List all environments
azd env list

# Create a new environment
azd env new staging

# Switch to a different environment
azd env select staging

# Show environment values
azd env get-values

# Delete an environment and all its resources
azd down
```

## Updating the Deployment

After making code changes:

```bash
# Deploy only (no infrastructure changes)
azd deploy

# Or provision and deploy together
azd up
```

The remote build in ACR means you don't need Docker locally — just push your code changes and run `azd deploy`.

## Cleaning Up

```bash
azd down
```

⚠️ **Warning**: This permanently deletes all resources and data in the environment.

## Troubleshooting

### Authentication Issues

```bash
# Re-authenticate with both azd and az
azd auth login
az login

# For multi-tenant scenarios, ensure both CLIs target the same tenant
az account set --subscription <your-subscription-id>
```

### Indexers Show 0 Documents

If knowledge base queries return no results:

1. **Check indexer status** — Indexers run automatically after knowledge source creation but need time (5-15 min for OCR + embeddings)
2. **RBAC propagation** — After provisioning, RBAC roles take 1-2 minutes to propagate. The postprovision hook includes retry logic for this.
3. **Re-run postprovision** — If sources were created with stale connection strings:
   ```bash
   # Re-run the postprovision hook manually
   azd hooks run postprovision
   ```
   The script always creates-or-updates (PUT is idempotent) so re-running is safe.

### Content Filter Errors

If queries return content filter errors, the chat model's RAI policy may need adjustment. The Bicep template sets `raiPolicyName: 'Microsoft.Nil'` on the chat deployment to avoid false positives with document content.

### RBAC Permission Issues

The postprovision hook configures all RBAC automatically. If issues persist:

```bash
# View all environment variables
azd env get-values

# Re-provision to re-apply RBAC
azd provision
```

### Container App Not Responding

```bash
# Check container app logs
az containerapp logs show --name <app-name> --resource-group <rg-name> --follow

# Check if the app is running
az containerapp show --name <app-name> --resource-group <rg-name> --query "properties.runningStatus"
```

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│               Azure Container Apps (Next.js)                      │
│             Identity: System-assigned managed identity            │
└───────────────────┬──────────────────────┬───────────────────────┘
                    │                      │
                    ▼                      ▼
      ┌─────────────────────┐   ┌─────────────────────┐
      │   Azure AI Search   │   │   Azure AI Services  │
      │  (Knowledge Bases)  │   │  (OpenAI + Cognitive) │
      │  Identity: system MI│   └─────────────────────┘
      └─────────┬───────────┘              │
                │                          │
                ▼                          ▼
      ┌─────────────────────┐   ┌─────────────────────────────┐
      │  Azure Blob Storage │   │   Azure AI Foundry Project  │
      │   (Documents)       │   │   (Agent Orchestration)     │
      └─────────────────────┘   └─────────────────────────────┘
```

## Deployment Flow

```
azd up
  ├── azd provision
  │     ├── Bicep deployment (main.bicep)
  │     │     ├── Container Registry (ACR)
  │     │     ├── Container App Environment + App
  │     │     ├── AI Search (Basic, system-assigned identity)
  │     │     ├── AI Services (OpenAI models + Foundry)
  │     │     ├── Storage Account
  │     │     ├── Log Analytics + App Insights
  │     │     └── RBAC role assignments
  │     └── postprovision hook (PowerShell → Python)
  │           ├── Create/update 7 Knowledge Sources
  │           ├── Create/update 3 Knowledge Bases
  │           ├── Upload sample data to blob storage
  │           └── Self-assign Storage Blob Data Contributor
  ├── azd package (remote Docker build in ACR)
  └── azd deploy (update Container App revision)
```

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Azure OpenAI Documentation](https://learn.microsoft.com/azure/ai-services/openai/)
