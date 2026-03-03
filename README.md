# Microsoft Foundry IQ Demo
<img width="1289" height="495" alt="image" src="https://github.com/user-attachments/assets/7ec01135-f72f-4113-aaaf-8b637fcf27b4" />

Agentic RAG demo with Foundry IQ Knowledge Bases and Microsoft Foundry Agent Service.

🚀 [Live Demo](https://azure-ai-search-knowledge-retrieval.vercel.app/)

## Deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Ffarzad528%2Fazure-ai-search-knowledge-retrieval-demo%2Fmain%2Finfra%2Fmain.json)
[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Ffarzad528%2Fazure-ai-search-knowledge-retrieval-demo)

### Deploy with Azure Developer CLI (azd)

The recommended way to deploy this application is using Azure Developer CLI (azd).

**Prerequisites:**
- [Azure Developer CLI (azd)](https://aka.ms/install-azd)
- [Azure CLI](https://aka.ms/installazurecli)
- Node.js 18+
- Python 3.8+ (required for post-provision hooks that configure Azure AI Search objects)

**Steps:**

```bash
# 1. Install azd: https://aka.ms/install-azd

# 2. Set up a Python virtual environment for post-provision dependencies
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS/Linux
# source .venv/bin/activate

# 3. Install Python dependencies used by post-provision hooks
pip install -r infra/hooks/requirements.txt

# 4. Login and provision infrastructure
#    (this also runs the postprovision hook which deploys AI Search objects)
azd auth login
azd provision

# 5. Upload sample data (hotels index, sample PDF, knowledge source/base)
#    Requires Azure CLI login: az login
#    Windows: run via Git Bash, WSL, or any bash-compatible shell
./scripts/upload-sample-data-azd.sh
```

After provisioning and sample data are done, deploy the app to Azure Static Web Apps:

```bash
# 6. Deploy to SWA (works on Windows, macOS, and Linux)
python scripts/deploy-swa.py
# or: npm run deploy:swa
```

The deploy script reads your `azd` environment, retrieves the SWA deployment token via Azure CLI, runs `npm run build`, and deploys using the SWA CLI (installed automatically if missing) — the same flow used by the CI workflow.

Alternatively, push to GitHub and let the CI workflow ([gbb-demo.yml](.github/workflows/gbb-demo.yml)) handle steps 5–6 automatically.

> **Windows note:** `upload-sample-data-azd.sh` is a bash script. On Windows, run it via [Git Bash](https://gitforwindows.org/) (included with Git for Windows) or WSL.

> **Why not `azd up`?** `azd deploy` does not fully support Azure Static Web Apps with hybrid Next.js. The provision step works, but the deploy step may fail. Use the deploy script or CI workflow instead.

> **Why a Python venv?** The `postprovision` hook runs a Python script (`infra/hooks/configure_search_objects.py`) that uses Azure SDKs to create Knowledge Sources and Knowledge Bases in Azure AI Search (these aren't supported in ARM/Bicep). Without a venv, `pip install` writes packages into your global Python environment.

See [AZD Deployment Guide](./docs/AZD_DEPLOYMENT.md) for detailed instructions.

## Quick Start

```bash
git clone https://github.com/farzad528/azure-ai-search-knowledge-retrieval-demo.git
cd azure-ai-search-knowledge-retrieval-demo
npm install
cp .env.example .env.local
# Edit .env.local with your Azure credentials
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

## Environment Variables

See `.env.example` for all options. Required:

```
AZURE_SEARCH_ENDPOINT=https://<your-search>.search.windows.net
AZURE_SEARCH_API_KEY=<admin-or-query-key>
NEXT_PUBLIC_AZURE_OPENAI_ENDPOINT=https://<your-openai>.openai.azure.com
AZURE_OPENAI_API_KEY=<openai-key>
```

## Routes

| Route | Description |
|-------|-------------|
| `/knowledge` | Manage knowledge bases and data sources |
| `/playground` | Query knowledge bases with runtime controls |
| `/agents` | Microsoft Foundry Agent Service integration |

## Resources

- [Foundry IQ Blog](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-iq-unlocking-ubiquitous-knowledge-for-agents/4470812)
- [Azure AI Search Docs](https://learn.microsoft.com/azure/search/)
- [Microsoft Foundry Docs](https://learn.microsoft.com/azure/ai-foundry/)
- [AGENTS.md](./AGENTS.md) – Detailed agent guidance

## License

MIT
