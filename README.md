# Microsoft Foundry IQ Demo

<img width="1289" height="495" alt="image" src="https://github.com/user-attachments/assets/7ec01135-f72f-4113-aaaf-8b637fcf27b4" />

Agentic RAG demo with Foundry IQ Knowledge Bases and Microsoft Foundry Agent Service. Deploys to **Azure Container Apps** via `azd up` with fully identity-based authentication (zero API keys).

## Deploy with Azure Developer CLI (azd)

`azd up` provisions all Azure resources, configures Azure AI Search knowledge bases, uploads sample data, builds the Docker image remotely in ACR, and deploys to Azure Container Apps — all in a single command.

**Prerequisites:**

- [Azure Developer CLI (azd)](https://aka.ms/install-azd)
- [Azure CLI](https://aka.ms/installazurecli)
- Python 3.8+ (for post-provision hooks)

> **Note:** Node.js and Docker are **not** required locally — the Docker image is built remotely in Azure Container Registry.

**Steps:**

```bash
# 1. Clone the repository
git clone https://github.com/aiappsgbb/foundry-iq-demo.git
cd foundry-iq-demo

# 2. Set up a Python virtual environment for post-provision dependencies
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS/Linux
# source .venv/bin/activate

# 3. Install Python dependencies used by post-provision hooks
pip install -r infra/hooks/requirements.txt

# 4. Login and deploy everything
azd auth login
az login          # Required for sample data upload
azd up
```

That's it. `azd up` handles provisioning, search object configuration, sample data upload, remote Docker build, and deployment.

> **Why a Python venv?** The `postprovision` hook runs `infra/hooks/configure_search_objects.py` which uses Azure SDKs to create Knowledge Sources and Knowledge Bases in Azure AI Search (these aren't supported in ARM/Bicep). Without a venv, `pip install` writes packages into your global Python environment.

See [AZD Deployment Guide](./docs/AZD_DEPLOYMENT.md) for detailed instructions.

### Reuse an Existing Foundry Instance (Optional)

If you already have an Azure AI Services (Foundry) account with model deployments and want to centralize quota, you can skip provisioning a new one:

```bash
# Point to your existing AI Services account
azd env set AZURE_EXISTING_FOUNDRY_RESOURCE_GROUP rg-my-foundry
azd env set AZURE_EXISTING_FOUNDRY_NAME my-ai-services-account

# Specify your existing model deployment names
azd env set AZURE_EXISTING_CHAT_DEPLOYMENT gpt-4o
azd env set AZURE_EXISTING_EMBEDDING_DEPLOYMENT text-embedding-3-large

azd up
```

When these are set, Bicep skips AI Services and model deployment creation, creates only a Foundry Project + Search connection on the existing account, and applies RBAC so the UAMI can access it. The existing account can be in any resource group within the same subscription. Leave them empty (default) to provision a new Foundry instance.

## Quick Start (Local Development)

```bash
git clone https://github.com/aiappsgbb/foundry-iq-demo.git
cd foundry-iq-demo
npm install
cp .env.example .env.local
# Edit .env.local with your Azure resource endpoints
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

## Authentication

This application uses **Entra ID (managed identity)** for all Azure service authentication — **no API keys are stored or required**.

- **Azure AI Search**: Bearer tokens via `DefaultAzureCredential` with scope `https://search.azure.com/.default`
- **Azure OpenAI / AI Services**: Search service's system-assigned managed identity (no keys)
- **Azure Blob Storage**: ResourceId-based connection string (identity auth)

For local development, `DefaultAzureCredential` picks up your `az login` or `azd auth login` session automatically.

## Environment Variables

See `.env.example` for all options. Required for local development:

```
AZURE_SEARCH_ENDPOINT=https://<your-search>.search.windows.net
AZURE_SEARCH_API_VERSION=2025-11-01-preview
```

When deployed via `azd`, all environment variables are configured automatically on the container app.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│              Azure Container Apps (Next.js)                   │
│            Identity: System-assigned managed identity         │
└──────────────┬──────────────────────┬────────────────────────┘
               │                      │
               ▼                      ▼
 ┌─────────────────────┐   ┌─────────────────────┐
 │   Azure AI Search   │   │    Azure OpenAI     │
 │  (Knowledge Bases)  │   │ (Embeddings & Chat) │
 │  Identity: system MI│   └─────────────────────┘
 └─────────┬───────────┘              │
           │                          │
           ▼                          ▼
 ┌─────────────────────┐   ┌─────────────────────────────┐
 │  Azure Blob Storage │   │   Azure AI Foundry Project  │
 │   (Documents)       │   │   (Agent Orchestration)     │
 └─────────────────────┘   └─────────────────────────────┘
```

**RBAC assignments (configured automatically by Bicep):**
- Container App → Search Index Data Contributor + Search Service Contributor
- Container App → Storage Blob Data Contributor
- Container App → Cognitive Services User
- Search Service → Storage Blob Data Reader (indexer access)
- Search Service → Cognitive Services User (embedding/OCR)

## Routes

| Route | Description |
|-------|-------------|
| `/test` | Primary playground — query knowledge bases with runtime controls |
| `/knowledge` | Manage knowledge bases and data sources |
| `/playground` | Alternative playground view |
| `/agents` | Microsoft Foundry Agent Service integration |
| `/knowledge-sources` | Knowledge source management and quick-create |

## Azure Resources Provisioned

| Resource | Purpose |
|----------|---------|
| Azure Container Apps | Hosts the Next.js application |
| Azure Container Registry | Stores Docker images (remote build) |
| Azure AI Search (Basic) | Knowledge base indexing and retrieval |
| Azure AI Services | OpenAI models (embeddings + chat) — or reuse existing |
| Azure AI Foundry Hub & Project | Agent orchestration (project created on existing or new account) |
| Azure Blob Storage | Document storage for knowledge sources |
| Log Analytics + App Insights | Monitoring and observability |

## Resources

- [Foundry IQ Blog](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-iq-unlocking-ubiquitous-knowledge-for-agents/4470812)
- [Azure AI Search Docs](https://learn.microsoft.com/azure/search/)
- [Microsoft Foundry Docs](https://learn.microsoft.com/azure/ai-foundry/)
- [AGENTS.md](./AGENTS.md) – AI agent coding guidelines

## License

MIT
