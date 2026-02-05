// Main deployment template for Azure AI Search Knowledge Retrieval Demo
targetScope = 'resourceGroup'

@description('Base name for all resources (will be used to generate unique names)')
@minLength(3)
@maxLength(10)
param baseName string = 'aikb'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('GitHub repository URL for Static Web App')
param repositoryUrl string = 'https://github.com/farzad528/azure-ai-search-knowledge-retrieval-demo'

@description('GitHub repository branch')
param branch string = 'main'

@description('GitHub repository token for Static Web App deployment')
@secure()
param repositoryToken string = ''

@description('Deploy sample data (hotels index and Responsible AI PDF)')
param deploySampleData bool = true

@description('Chat model to deploy')
@allowed([
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-4.1-nano'
  'gpt-4.1-mini'
  'gpt-4.1'
  'gpt-5'
  'gpt-5-mini'
  'gpt-5-nano'
])
param chatModelName string = 'gpt-4o-mini'

@description('Embedding model to deploy')
@allowed([
  'text-embedding-ada-002'
  'text-embedding-3-small'
  'text-embedding-3-large'
])
param embeddingModelName string = 'text-embedding-3-small'

// SKU selections based on environment
var skuMap = {
  dev: {
    search: 'basic'
    storage: 'Standard_LRS'
    staticWebApp: 'Standard'
  }
  staging: {
    search: 'standard'
    storage: 'Standard_LRS'
    staticWebApp: 'Standard'
  }
  prod: {
    search: 'standard'
    storage: 'Standard_GRS'
    staticWebApp: 'Standard'
  }
}

// Generate unique suffix (13 characters)
var uniqueSuffix = uniqueString(resourceGroup().id)

// Resource naming with Azure limits:
// - Storage Account: 3-24 chars, lowercase alphanumeric only
// - AI Search: 2-60 chars, lowercase alphanumeric and hyphens
// - Cognitive Services: 2-64 chars, alphanumeric and hyphens
// - ML Workspace: 3-33 chars, alphanumeric and hyphens
// - Static Web App: 2-40 chars, alphanumeric and hyphens
var resourceNames = {
  search: '${baseName}-search-${uniqueSuffix}'
  openai: '${baseName}-openai-${uniqueSuffix}'
  // Storage: max 24 chars, lowercase alphanumeric only. 'st' (2) + baseName (3-10) + suffix.
  // take() dynamically limits suffix to fit: 24 - 2 - len(baseName) = 12-19 chars of uniqueSuffix (which is 13 chars).
  // When baseName is 3-11 chars, take() returns all 13 chars of uniqueSuffix since requested amount is >= 13.
  storage: toLower('st${baseName}${take(uniqueSuffix, 24 - 2 - length(baseName))}')
  // Hub/Project: max 33 chars. Use shorter suffixes for safety margin.
  hub: '${baseName}-hub-${uniqueSuffix}'
  project: '${baseName}-prj-${uniqueSuffix}'
  staticWebApp: '${baseName}-web-${uniqueSuffix}'
  logAnalytics: '${baseName}-${uniqueSuffix}-law'
  appInsights: '${baseName}-${uniqueSuffix}-appi'
}

// Tags for all resources
var tags = {
  environment: environment
  solution: 'Azure AI Search Knowledge Retrieval'
  managedBy: 'Bicep'
}

// Model version and capacity mappings
var chatModelConfig = {
  'gpt-4o': {
    version: '2024-08-06'
    capacity: 30
  }
  'gpt-4o-mini': {
    version: '2024-07-18'
    capacity: 30
  }
  'gpt-4.1-nano': {
    version: '2024-11-01'
    capacity: 30
  }
  'gpt-4.1-mini': {
    version: '2024-11-01'
    capacity: 30
  }
  'gpt-4.1': {
    version: '2024-11-01'
    capacity: 30
  }
  'gpt-5': {
    version: 'latest'
    capacity: 30
  }
  'gpt-5-mini': {
    version: 'latest'
    capacity: 30
  }
  'gpt-5-nano': {
    version: 'latest'
    capacity: 30
  }
}

var embeddingModelConfig = {
  'text-embedding-ada-002': {
    version: '2'
    capacity: 120
  }
  'text-embedding-3-small': {
    version: '1'
    capacity: 20
  }
  'text-embedding-3-large': {
    version: '1'
    capacity: 20
  }
}

// Deploy Azure AI Search
module search 'modules/search.bicep' = {
  name: 'deploy-search'
  params: {
    searchServiceName: resourceNames.search
    location: location
    sku: skuMap[environment].search
    tags: tags
  }
}

// Deploy Storage Account
module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    storageAccountName: resourceNames.storage
    location: location
    sku: skuMap[environment].storage
    tags: tags
    sampleDataContainerName: 'sample-documents'
  }
}

// Deploy AI Foundry Hub, Project, and AI Services with model deployments
// This replaces the standalone OpenAI module - all models are now deployed via Foundry
module foundry 'modules/foundry.bicep' = {
  name: 'deploy-foundry'
  params: {
    hubName: resourceNames.hub
    projectName: resourceNames.project
    aiServicesName: resourceNames.openai // Reuse openai naming for AI Services
    location: location
    tags: tags
    searchResourceId: search.outputs.searchServiceId
    storageAccountId: storage.outputs.storageAccountId
    // Model deployments
    chatModelName: chatModelName
    embeddingModelName: embeddingModelName
    chatCapacity: chatModelConfig[chatModelName].capacity
    embeddingCapacity: embeddingModelConfig[embeddingModelName].capacity
  }
}

// Deploy Monitoring (Log Analytics + Application Insights)
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    baseName: '${baseName}-${uniqueSuffix}'
    location: location
    tags: tags
    retentionInDays: environment == 'prod' ? 90 : 30
  }
}

// Deploy Static Web App
module staticWebApp 'modules/staticwebapp.bicep' = {
  name: 'deploy-staticwebapp'
  params: {
    staticWebAppName: resourceNames.staticWebApp
    location: location
    sku: skuMap[environment].staticWebApp
    tags: tags
    repositoryUrl: repositoryUrl
    branch: branch
    repositoryToken: repositoryToken
    serviceName: 'web' // Matches service name in azure.yaml
    // Environment variables (detected from app/ folder)
    azureSearchEndpoint: search.outputs.searchEndpoint
    azureSearchApiKey: search.outputs.searchAdminKey
    azureSearchApiVersion: '2025-11-01-preview'
    // Azure AI Services via Foundry (for Knowledge Base model calls)
    azureOpenAIEndpoint: foundry.outputs.aiServicesEndpoint
    azureOpenAIApiKey: foundry.outputs.aiServicesKey
    // Foundry Project (for Agents and unified AI)
    foundryProjectEndpoint: foundry.outputs.projectEndpoint
    foundryApiKey: foundry.outputs.aiServicesKey
    foundryProjectName: foundry.outputs.projectName
    azureSubscriptionId: subscription().subscriptionId
    azureResourceGroup: resourceGroup().name
    // Monitoring
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
  }
}

// Role assignments for Managed Identity
// Note: Role assignments commented out as they require outputs that aren't available at compile time
// They can be added post-deployment via a script or manually in the portal
// See scripts/configure-rbac.sh for automated role assignment setup

// Outputs for application configuration
output resourceGroupName string = resourceGroup().name
output location string = location

// Search outputs
output searchEndpoint string = search.outputs.searchEndpoint
output searchServiceName string = search.outputs.searchServiceName
output searchAdminKey string = search.outputs.searchAdminKey

// AI Services outputs (unified model hosting via Foundry)
output openAIEndpoint string = foundry.outputs.aiServicesEndpoint
output openAIKey string = foundry.outputs.aiServicesKey
output embeddingDeploymentName string = foundry.outputs.embeddingDeploymentName
output chatDeploymentName string = foundry.outputs.chatDeploymentName
output aiServicesName string = foundry.outputs.aiServicesName

// Storage outputs
output storageAccountName string = storage.outputs.storageAccountName
output storageConnectionString string = storage.outputs.storageConnectionString
output sampleDataContainerName string = storage.outputs.sampleDataContainerName

// Foundry outputs
output foundryProjectEndpoint string = foundry.outputs.projectEndpoint
output foundryProjectName string = foundry.outputs.projectName
output foundryHubName string = foundry.outputs.hubName

// Static Web App outputs
output staticWebAppUrl string = staticWebApp.outputs.staticWebAppUrl
output staticWebAppName string = staticWebApp.outputs.staticWebAppName

// Monitoring outputs
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output applicationInsightsName string = monitoring.outputs.applicationInsightsName
output applicationInsightsConnectionString string = monitoring.outputs.applicationInsightsConnectionString

// Deployment summary
output deploymentSummary object = {
  message: 'Deployment completed successfully!'
  nextSteps: [
    '1. Visit your Static Web App at: ${staticWebApp.outputs.staticWebAppUrl}'
    '2. Configure GitHub Actions for automated deployments'
    '3. Upload sample data using the provided script'
    '4. Create your first knowledge base in the app'
  ]
  estimatedMonthlyCost: environment == 'dev' ? '$100-150' : environment == 'staging' ? '$250-350' : '$500+'
  resources: {
    search: resourceNames.search
    aiServices: resourceNames.openai  // AI Services (models deployed via Foundry)
    storage: resourceNames.storage
    foundry: '${resourceNames.hub} / ${resourceNames.project}'
    staticWebApp: resourceNames.staticWebApp
    monitoring: '${resourceNames.logAnalytics} / ${resourceNames.appInsights}'
  }
}

// =====================================================
// Azure Developer CLI (azd) outputs
// These outputs follow azd naming conventions for environment variable mapping
// azd automatically sets AZURE_<OUTPUT_NAME> environment variables
// Reference: https://learn.microsoft.com/azure/developer/azure-developer-cli/
// =====================================================

// Service endpoint for azd service discovery
// AZURE_STATIC_WEB_APP_NAME: Used by postprovision.sh hook for RBAC configuration
output AZURE_STATIC_WEB_APP_NAME string = staticWebApp.outputs.staticWebAppName
// SERVICE_WEB_ENDPOINT_URL: Displayed to users after deployment completion
output SERVICE_WEB_ENDPOINT_URL string = staticWebApp.outputs.staticWebAppUrl

// Resource names for post-provision hooks (RBAC configuration)
// Used by infra/hooks/postprovision.sh to configure role assignments
output AZURE_SEARCH_SERVICE_NAME string = search.outputs.searchServiceName
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.storageAccountName
output AZURE_AI_SERVICES_NAME string = foundry.outputs.aiServicesName
// Backward compatibility: Scripts expect AZURE_OPENAI_NAME (now AI Services via Foundry)
output AZURE_OPENAI_NAME string = foundry.outputs.aiServicesName

// Environment configuration for the web service
// These values are used by scripts/upload-sample-data-azd.sh
output AZURE_SEARCH_ENDPOINT string = search.outputs.searchEndpoint
output AZURE_OPENAI_ENDPOINT string = foundry.outputs.aiServicesEndpoint
output AZURE_FOUNDRY_PROJECT_ENDPOINT string = foundry.outputs.projectEndpoint
