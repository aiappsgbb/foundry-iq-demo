// Azure Static Web App for Next.js hosting
@description('Name of the static web app')
param staticWebAppName string

@description('Location for the static web app')
param location string = resourceGroup().location

@description('SKU for the static web app')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Standard'

@description('Tags for the static web app')
param tags object = {}

@description('Azure Developer CLI service name for deployment targeting')
param serviceName string = 'web'

@description('Repository URL')
param repositoryUrl string = ''

@description('Branch name')
param branch string = 'main'

@description('Repository token (optional)')
@secure()
param repositoryToken string = ''

@description('Build properties')
// For hybrid Next.js apps on Azure Static Web Apps, the outputLocation should be empty
// to let SWA's Oryx builder handle the Next.js hybrid deployment automatically.
// See: https://learn.microsoft.com/en-us/azure/static-web-apps/deploy-nextjs-hybrid
param buildProperties object = {
  appLocation: '/'
  apiLocation: ''
  outputLocation: ''
  appBuildCommand: 'npm run build'
  apiBuildCommand: ''
}

// =====================================================
// Environment Variables (detected from app/ folder)
// =====================================================

// Azure AI Search
@description('Azure AI Search endpoint URL')
param azureSearchEndpoint string = ''

@description('Azure AI Search API key')
@secure()
param azureSearchApiKey string = ''

@description('Azure AI Search API version')
param azureSearchApiVersion string = '2025-11-01-preview'

// Azure OpenAI (for Knowledge Base model calls)
@description('Azure OpenAI endpoint URL (e.g., https://{name}.openai.azure.com)')
param azureOpenAIEndpoint string = ''

@description('Azure OpenAI API key')
@secure()
param azureOpenAIApiKey string = ''

// Azure AI Foundry
@description('Foundry Project endpoint URL')
param foundryProjectEndpoint string = ''

@description('Foundry API key (for Azure OpenAI access) - DEPRECATED: use azureOpenAIApiKey')
@secure()
param foundryApiKey string = ''

@description('Foundry Project name')
param foundryProjectName string = ''

// Azure Subscription Info (for management operations)
@description('Azure Subscription ID')
param azureSubscriptionId string = ''

@description('Azure Resource Group name')
param azureResourceGroup string = ''

// Monitoring
@description('Application Insights connection string')
param applicationInsightsConnectionString string = ''

resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticWebAppName
  location: location
  tags: union(tags, { 'azd-service-name': serviceName })
  sku: {
    name: sku
    tier: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    repositoryUrl: repositoryUrl
    branch: branch
    repositoryToken: repositoryToken
    buildProperties: buildProperties
    provider: 'GitHub'
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// Configure environment variables for the Static Web App
// These are detected from process.env usage in app/ folder
resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2023-01-01' = {
  parent: staticWebApp
  name: 'appsettings'
  properties: {
    // Azure AI Search (server-side)
    AZURE_SEARCH_ENDPOINT: azureSearchEndpoint
    AZURE_SEARCH_API_KEY: azureSearchApiKey
    AZURE_SEARCH_API_VERSION: azureSearchApiVersion
    
    // Azure AI Search (client-side)
    NEXT_PUBLIC_SEARCH_ENDPOINT: azureSearchEndpoint
    NEXT_PUBLIC_AZURE_SEARCH_API_VERSION: azureSearchApiVersion
    
    // Azure OpenAI (for Knowledge Base model authentication)
    AZURE_OPENAI_ENDPOINT: azureOpenAIEndpoint
    AZURE_OPENAI_API_KEY: !empty(azureOpenAIApiKey) ? azureOpenAIApiKey : foundryApiKey
    NEXT_PUBLIC_AZURE_OPENAI_ENDPOINT: azureOpenAIEndpoint
    
    // Azure AI Foundry (server-side)
    FOUNDRY_PROJECT_ENDPOINT: foundryProjectEndpoint
    FOUNDRY_API_KEY: !empty(azureOpenAIApiKey) ? azureOpenAIApiKey : foundryApiKey
    FOUNDRY_PROJECT_NAME: foundryProjectName
    
    // Azure AI Foundry (client-side)
    NEXT_PUBLIC_FOUNDRY_ENDPOINT: foundryProjectEndpoint
    
    // Azure Subscription Info (for management operations)
    AZURE_SUBSCRIPTION_ID: azureSubscriptionId
    AZURE_RESOURCE_GROUP: azureResourceGroup
    
    // Monitoring
    APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
  }
}

// Output Static Web App details
output staticWebAppId string = staticWebApp.id
output staticWebAppName string = staticWebApp.name
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output staticWebAppPrincipalId string = staticWebApp.identity.principalId
