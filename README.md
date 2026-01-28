# Foundry IQ Demo - Azure AI Search Knowledge Retrieval

Production-ready Next.js application showcasing Azure AI Search Knowledge Bases and Azure AI Foundry Agent Service integration.

🚀 [Live Demo](https://azure-ai-search-knowledge-retrieval.vercel.app/)

## 📂 Project Structure

This repository uses a specific structure required for Azure Developer CLI (azd) deployment compatibility with Azure Static Web Apps:

```
/
├── web/                # Next.js application (all source code)
│   ├── app/           # Next.js 14 App Router pages and API routes
│   ├── components/    # React components
│   ├── lib/          # Utility libraries
│   ├── public/       # Static assets
│   └── package.json  # Application dependencies
│
├── infra/            # Infrastructure as Code (Bicep templates)
│   ├── main.bicep    # Main deployment template
│   └── modules/      # Bicep modules for Azure resources
│
├── scripts/          # Deployment and utility scripts
├── docs/             # Documentation
├── azure.yaml        # Azure Developer CLI configuration
└── README.md         # This file
```

**Why this structure?**
Azure Developer CLI (azd) requires the application source to be in a subfolder (not at the root) when deploying to Azure Static Web Apps. The `web/` folder contains all application code, while infrastructure and deployment configuration remain at the root level.

## 🚀 Quick Start

### Prerequisites

- **Node.js 18+**
- **Azure subscription** with the following resources:
  - Azure AI Search
  - Azure OpenAI Service
  - Azure AI Foundry Hub & Project
  - Azure Storage Account

### Local Development

1. **Clone the repository:**
   ```bash
   git clone https://github.com/farzad528/azure-ai-search-knowledge-retrieval-demo.git
   cd azure-ai-search-knowledge-retrieval-demo
   ```

2. **Navigate to the web directory:**
   ```bash
   cd web
   ```

3. **Install dependencies:**
   ```bash
   npm install
   ```

4. **Configure environment variables:**
   ```bash
   cp .env.example .env.local
   ```
   
   Edit `.env.local` with your Azure credentials:
   ```env
   AZURE_SEARCH_ENDPOINT=https://your-search-service.search.windows.net
   AZURE_SEARCH_API_KEY=your-search-api-key
   AZURE_SEARCH_API_VERSION=2025-11-01-preview
   
   NEXT_PUBLIC_AZURE_OPENAI_ENDPOINT=https://your-openai-service.openai.azure.com
   AZURE_OPENAI_API_KEY=your-openai-api-key
   
   FOUNDRY_PROJECT_ENDPOINT=https://your-foundry-project.api.azureml.ms
   FOUNDRY_API_VERSION=2025-05-01
   ```

5. **Start the development server:**
   ```bash
   npm run dev
   ```

6. **Open your browser:**
   Navigate to [http://localhost:3000](http://localhost:3000)

## 🌐 Deployment

### Deploy with Azure Developer CLI (azd)

**Recommended:** Deploy the complete solution (infrastructure + application) with one command:

```bash
# Install azd if not already installed
# https://aka.ms/install-azd

# Login to Azure
azd auth login

# Provision infrastructure and deploy application
azd up
```

**Step-by-step deployment:**

```bash
# Initialize azd (first time only)
azd init

# Provision Azure resources
azd provision

# Deploy application to Azure Static Web Apps
azd deploy
```

See [DEPLOYMENT_NOTES.md](./DEPLOYMENT_NOTES.md) for detailed deployment instructions and troubleshooting.

### Deploy to Azure Static Web Apps (Manual)

1. Create an Azure Static Web App resource in Azure Portal
2. Configure build settings:
   - **App location:** `web`
   - **API location:** (leave empty)
   - **Output location:** (leave empty for hybrid Next.js)
   - **App build command:** `npm run build`
3. Configure environment variables in the Static Web Apps settings
4. Deploy via GitHub Actions or Azure CLI

### Deploy to Vercel

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Ffarzad528%2Fazure-ai-search-knowledge-retrieval-demo)

Or manually:

```bash
cd web
vercel --prod
```

## 🎯 Key Features

### 1. Test Playground (`/test`)
Direct Knowledge Base queries against Azure AI Search without Foundry integration.
- Industry-specific knowledge base selection
- Real-time query testing
- Citation and source document viewing

### 2. Knowledge Management (`/knowledge`)
Manage knowledge bases and data sources:
- Azure Blob Storage
- Azure AI Search Index
- Web URLs
- SharePoint (indexed and remote)
- OneLake

### 3. Knowledge Bases Playground (`/playground`)
Interactive RAG experimentation:
- Configurable retrieval parameters
- Source-specific tuning
- Reranker adjustments

### 4. Foundry Agents (`/agents`)
Azure AI Foundry Agent Service integration:
- Multi-turn conversations
- Production-ready orchestration
- Enterprise-grade scalability

## 🛠️ Tech Stack

- **Framework:** Next.js 14 (App Router)
- **Language:** TypeScript 5.9
- **Styling:** TailwindCSS 3.3
- **Deployment:** Azure Static Web Apps, Vercel
- **Azure Services:**
  - Azure AI Search
  - Azure OpenAI
  - Azure AI Foundry
  - Azure Storage

## 📚 Documentation

- [AGENTS.md](./AGENTS.md) - AI agent development guidelines
- [DEPLOYMENT_NOTES.md](./DEPLOYMENT_NOTES.md) - Deployment troubleshooting and notes
- [web/README.md](./web/README.md) - Application-specific documentation

## 🔧 Development

**Important:** All npm commands must be run from the `web/` directory.

```bash
# Development server
cd web && npm run dev

# Build for production
cd web && npm run build

# Start production server
cd web && npm start
```

### Project Commands (from root)

```bash
# Provision Azure resources
azd provision

# Deploy to Azure
azd deploy

# Provision + Deploy
azd up

# View deployment logs
azd monitor
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make changes in the appropriate directory:
   - Application code: `web/`
   - Infrastructure: `infra/`
4. Follow the guidelines in [AGENTS.md](./AGENTS.md)
5. Submit a pull request

## 📝 License

This project is licensed under the MIT License.

## 🆘 Support

- [GitHub Issues](https://github.com/farzad528/azure-ai-search-knowledge-retrieval-demo/issues)
- [GitHub Discussions](https://github.com/farzad528/azure-ai-search-knowledge-retrieval-demo/discussions)
- [Azure AI Search Documentation](https://learn.microsoft.com/azure/search/)
- [Azure AI Foundry Documentation](https://learn.microsoft.com/azure/ai-services/agents/)

## ⚠️ Important Notes

### Project Structure Change (2026-01-28)

The project structure was reorganized to support Azure Developer CLI (azd) deployment with Azure Static Web Apps:

- **Before:** Application files at repository root
- **After:** Application files in `web/` subdirectory

**If updating from an older version:**
1. Re-clone the repository or pull latest changes
2. Navigate to `web/` directory for all npm commands
3. Update any custom scripts that reference old paths
4. Reconfigure environment variables in `web/.env.local`

### Development Environment

- All application development happens in the `web/` directory
- Infrastructure changes happen in the `infra/` directory
- Do not move files between `web/` and root without updating `azure.yaml`

---

**Made with ❤️ by the Azure App Innovation team**
