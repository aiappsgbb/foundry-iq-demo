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
param embeddingModelName string = 'text-embedding-3-large'

@description('Container image name (azd sets SERVICE_WEB_IMAGE_NAME after each deploy)')
param webImageName string = ''

@description('Resource group of an existing Foundry (AI Services) account to reuse. Leave empty to provision new.')
param existingFoundryResourceGroup string = ''

@description('Name of an existing Foundry (AI Services) account to reuse. Leave empty to provision new.')
param existingFoundryName string = ''

@description('Name of the existing Foundry chat model deployment (required when using existing Foundry)')
param existingChatDeploymentName string = ''

@description('Name of the existing Foundry embedding model deployment (required when using existing Foundry)')
param existingEmbeddingDeploymentName string = ''

// SKU selections based on environment
var skuMap = {
  dev: {
    search: 'basic'
    storage: 'Standard_LRS'
  }
  staging: {
    search: 'standard'
    storage: 'Standard_LRS'
  }
  prod: {
    search: 'standard'
    storage: 'Standard_GRS'
  }
}

// Generate unique suffix (13 characters)
var uniqueSuffix = uniqueString(resourceGroup().id)

// Resource naming with Azure limits:
// - Storage Account: 3-24 chars, lowercase alphanumeric only
// - AI Search: 2-60 chars, lowercase alphanumeric and hyphens
// - Cognitive Services / Foundry: 2-64 chars, alphanumeric and hyphens
// - Static Web App: 2-40 chars, alphanumeric and hyphens
var resourceNames = {
  search: '${baseName}-search-${uniqueSuffix}'
  openai: '${baseName}-openai-${uniqueSuffix}'
  // Storage: max 24 chars, lowercase alphanumeric only. 'st' (2) + baseName (3-10) + suffix.
  // take() dynamically limits suffix to fit: 24 - 2 - len(baseName) = 12-19 chars of uniqueSuffix (which is 13 chars).
  // When baseName is 3-11 chars, take() returns all 13 chars of uniqueSuffix since requested amount is >= 13.
  storage: toLower('st${baseName}${take(uniqueSuffix, 24 - 2 - length(baseName))}')
  // Foundry project name
  project: '${baseName}-prj-${uniqueSuffix}'
  containerApp: '${baseName}-${uniqueSuffix}'
  logAnalytics: '${baseName}-${uniqueSuffix}-law'
  appInsights: '${baseName}-${uniqueSuffix}-appi'
}

// Tags for all resources
var tags = {
  environment: environment
  solution: 'Azure AI Search Knowledge Retrieval'
  managedBy: 'Bicep'
}

// Foundry mode: provision new or reuse existing
var useExistingFoundry = !empty(existingFoundryName)
// Fallback to current RG so scope expression is always valid (even when condition is false)
var targetFoundryRg = !empty(existingFoundryResourceGroup) ? existingFoundryResourceGroup : resourceGroup().name

// =====================================================
// User-Assigned Managed Identity (shared across all services)
// =====================================================
module userIdentity 'modules/user-identity.bicep' = {
  name: 'deploy-uami'
  params: {
    identityName: '${baseName}-${uniqueSuffix}-id'
    location: location
    tags: tags
  }
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

// Deploy AI Foundry (Microsoft Foundry) with Project, Connections, and Model Deployments
// Uses modern CognitiveServices resource types — no legacy MachineLearningServices Hub/Project
module foundry 'modules/foundry.bicep' = if (!useExistingFoundry) {
  name: 'deploy-foundry'
  params: {
    aiServicesName: resourceNames.openai // Reuse openai naming for AI Services
    projectName: resourceNames.project
    location: location
    tags: tags
    searchResourceId: search.outputs.searchServiceId
    searchEndpoint: search.outputs.searchEndpoint
    // Model deployments
    chatModelName: chatModelName
    embeddingModelName: embeddingModelName
    chatCapacity: chatModelConfig[chatModelName].capacity
    embeddingCapacity: embeddingModelConfig[embeddingModelName].capacity
    userAssignedIdentityId: userIdentity.outputs.identityId
  }
}

// Create a project + search connection on the existing AI Services account
// Scoped to the existing Foundry's resource group (may differ from current RG)
module existingFoundryProject 'modules/foundry-project.bicep' = if (useExistingFoundry) {
  name: 'deploy-foundry-project'
  scope: resourceGroup(targetFoundryRg)
  params: {
    aiServicesName: existingFoundryName
    projectName: resourceNames.project
    location: location
    tags: tags
    searchResourceId: search.outputs.searchServiceId
    searchEndpoint: search.outputs.searchEndpoint
    userAssignedIdentityId: userIdentity.outputs.identityId
  }
}

// RBAC for UAMI + Search MI on the existing Foundry (cross-RG)
module existingFoundryRbac 'modules/foundry-rbac.bicep' = if (useExistingFoundry) {
  name: 'deploy-foundry-rbac'
  scope: resourceGroup(targetFoundryRg)
  params: {
    aiServicesName: existingFoundryName
    uamiPrincipalId: userIdentity.outputs.identityPrincipalId
    searchServicePrincipalId: search.outputs.searchServicePrincipalId
  }
}

// Resolved Foundry outputs — works for both new and existing
var resolvedFoundry = {
  aiServicesEndpoint: useExistingFoundry ? existingFoundryProject.outputs.aiServicesEndpoint : foundry.outputs.aiServicesEndpoint
  aiServicesId: useExistingFoundry ? existingFoundryProject.outputs.aiServicesId : foundry.outputs.aiServicesId
  aiServicesName: useExistingFoundry ? existingFoundryName : foundry.outputs.aiServicesName
  projectEndpoint: useExistingFoundry ? existingFoundryProject.outputs.projectEndpoint : foundry.outputs.projectEndpoint
  projectName: useExistingFoundry ? existingFoundryProject.outputs.projectName : foundry.outputs.projectName
  chatDeploymentName: useExistingFoundry ? existingChatDeploymentName : foundry.outputs.chatDeploymentName
  embeddingDeploymentName: useExistingFoundry ? existingEmbeddingDeploymentName : foundry.outputs.embeddingDeploymentName
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

// Deploy Container App (replaces Static Web App)
module containerApp 'modules/containerapp.bicep' = {
  name: 'deploy-containerapp'
  params: {
    baseName: resourceNames.containerApp
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    imageName: webImageName
    // Environment variables
    azureSearchEndpoint: search.outputs.searchEndpoint
    azureSearchApiVersion: '2025-11-01-preview'
    azureOpenAIEndpoint: resolvedFoundry.aiServicesEndpoint
    foundryProjectEndpoint: resolvedFoundry.projectEndpoint
    foundryProjectName: resolvedFoundry.projectName
    azureSubscriptionId: subscription().subscriptionId
    azureResourceGroup: resourceGroup().name
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    userAssignedIdentityId: userIdentity.outputs.identityId
    userAssignedIdentityClientId: userIdentity.outputs.identityClientId
  }
}

// Deploy RBAC Role Assignments
// Assigns roles to: UAMI (shared identity) + Search system MI (knowledge source ingestion)
// Note: When using existing Foundry, AI Services RBAC is handled by foundry-rbac.bicep (cross-RG)
module rbac 'modules/rbac.bicep' = {
  name: 'deploy-rbac'
  params: {
    uamiPrincipalId: userIdentity.outputs.identityPrincipalId
    searchServicePrincipalId: search.outputs.searchServicePrincipalId
    searchServiceId: search.outputs.searchServiceId
    storageAccountId: storage.outputs.storageAccountId
    aiServicesId: useExistingFoundry ? '' : resolvedFoundry.aiServicesId
  }
}

// Outputs for application configuration
output resourceGroupName string = resourceGroup().name
output location string = location

// Search outputs
output searchEndpoint string = search.outputs.searchEndpoint
output searchServiceName string = search.outputs.searchServiceName

// AI Services outputs (unified model hosting via Foundry)
output openAIEndpoint string = resolvedFoundry.aiServicesEndpoint
output embeddingDeploymentName string = resolvedFoundry.embeddingDeploymentName
output chatDeploymentName string = resolvedFoundry.chatDeploymentName
output aiServicesName string = resolvedFoundry.aiServicesName

// Storage outputs
output storageAccountName string = storage.outputs.storageAccountName
output sampleDataContainerName string = storage.outputs.sampleDataContainerName
output knowledgeDataContainerName string = storage.outputs.knowledgeDataContainerName

// Foundry outputs
output foundryProjectEndpoint string = resolvedFoundry.projectEndpoint
output foundryProjectName string = resolvedFoundry.projectName
output foundryAccountName string = resolvedFoundry.aiServicesName

// Container App outputs
output containerAppUrl string = containerApp.outputs.containerAppUrl
output containerAppName string = containerApp.outputs.containerAppName
output acrName string = containerApp.outputs.acrName
output acrLoginServer string = containerApp.outputs.acrLoginServer

// Monitoring outputs
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId
output applicationInsightsName string = monitoring.outputs.applicationInsightsName
output applicationInsightsConnectionString string = monitoring.outputs.applicationInsightsConnectionString

// Deployment summary
output deploymentSummary object = {
  message: 'Deployment completed successfully!'
  nextSteps: [
    '1. Visit your Container App at: ${containerApp.outputs.containerAppUrl}'
    '2. Run azd deploy to push your app image'
    '3. Upload sample data using the provided script'
    '4. Create your first knowledge base in the app'
  ]
  estimatedMonthlyCost: environment == 'dev' ? '$100-150' : environment == 'staging' ? '$250-350' : '$500+'
  resources: {
    search: resourceNames.search
    aiServices: resolvedFoundry.aiServicesName
    storage: resourceNames.storage
    foundry: '${resolvedFoundry.aiServicesName} / ${resolvedFoundry.projectName}'
    containerApp: resourceNames.containerApp
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
output AZURE_CONTAINER_REGISTRY_NAME string = containerApp.outputs.acrName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApp.outputs.acrLoginServer
// SERVICE_WEB_ENDPOINT_URL: Displayed to users after deployment completion
output SERVICE_WEB_ENDPOINT_URL string = containerApp.outputs.containerAppUrl

// Resource names for post-provision hooks (RBAC configuration)
// Used by infra/hooks/postprovision.sh to configure role assignments
output AZURE_SEARCH_SERVICE_NAME string = search.outputs.searchServiceName
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.storageAccountName
output AZURE_AI_SERVICES_NAME string = resolvedFoundry.aiServicesName
// Backward compatibility: Scripts expect AZURE_OPENAI_NAME (now AI Services via Foundry)
output AZURE_OPENAI_NAME string = resolvedFoundry.aiServicesName

// Environment configuration for the web service
// These values are used by scripts/upload-sample-data-azd.sh
output AZURE_SEARCH_ENDPOINT string = search.outputs.searchEndpoint
output AZURE_OPENAI_ENDPOINT string = resolvedFoundry.aiServicesEndpoint
output AZURE_FOUNDRY_PROJECT_ENDPOINT string = resolvedFoundry.projectEndpoint

// Tenant ID — used by postprovision hooks to authenticate with AzureDeveloperCliCredential
output AZURE_TENANT_ID string = tenant().tenantId

// UAMI Client ID — used by Container App (DefaultAzureCredential) and postprovision scripts
output AZURE_CLIENT_ID string = userIdentity.outputs.identityClientId

// Deployed model names — used by postprovision to configure knowledge base/source JSON configs
output AZURE_CHAT_DEPLOYMENT_NAME string = resolvedFoundry.chatDeploymentName
output AZURE_EMBEDDING_DEPLOYMENT_NAME string = resolvedFoundry.embeddingDeploymentName
