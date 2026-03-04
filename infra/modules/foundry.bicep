// Azure AI Foundry (Microsoft Foundry) with Project, Connections, and Model Deployments
// Uses modern CognitiveServices resource types — NO legacy MachineLearningServices Hub/Project
// Reference: https://learn.microsoft.com/azure/foundry-classic/how-to/migrate-project

@description('Name of the AI Services (Foundry) account')
param aiServicesName string

@description('Name of the Foundry project')
param projectName string

@description('Location for Foundry resources')
param location string = resourceGroup().location

@description('Tags for Foundry resources')
param tags object = {}

@description('Search service resource ID to connect')
param searchResourceId string

@description('Search service endpoint URL')
param searchEndpoint string = ''

@description('Resource ID of the User-Assigned Managed Identity')
param userAssignedIdentityId string = ''

@description('Chat model to deploy')
@allowed([
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-4.1-nano'
  'gpt-4.1-mini'
  'gpt-4.1'
  'gpt-5-nano'
  'gpt-5-mini'
  'gpt-5'
])
param chatModelName string = 'gpt-4.1-mini'

@description('Embedding model to deploy')
@allowed([
  'text-embedding-ada-002'
  'text-embedding-3-small'
  'text-embedding-3-large'
])
param embeddingModelName string = 'text-embedding-3-large'

@description('Chat model capacity (TPM in thousands)')
param chatCapacity int = 30

@description('Embedding model capacity (TPM in thousands)')
param embeddingCapacity int = 20

// Model version mappings
var chatModelConfig = {
  'gpt-4o': {
    version: '2024-08-06'
  }
  'gpt-4o-mini': {
    version: '2024-07-18'
  }
  'gpt-4.1-nano': {
    version: '2024-11-01'
  }
  'gpt-4.1-mini': {
    version: '2024-11-01'
  }
  'gpt-4.1': {
    version: '2024-11-01'
  }
  'gpt-5-nano': {
    version: '2025-01-01'
  }
  'gpt-5-mini': {
    version: '2025-01-01'
  }
  'gpt-5': {
    version: '2025-01-01'
  }
}

var embeddingModelConfig = {
  'text-embedding-ada-002': {
    version: '2'
  }
  'text-embedding-3-small': {
    version: '1'
  }
  'text-embedding-3-large': {
    version: '1'
  }
}

// =====================================================
// Foundry Resource (Microsoft.CognitiveServices/accounts)
// This is the modern Foundry resource — hosts model deployments and enables project management
// =====================================================
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: !empty(userAssignedIdentityId) ? 'SystemAssigned,UserAssigned' : 'SystemAssigned'
    userAssignedIdentities: !empty(userAssignedIdentityId) ? {
      '${userAssignedIdentityId}': {}
    } : null
  }
  properties: {
    customSubDomainName: aiServicesName
    allowProjectManagement: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
  }
}

// =====================================================
// Model Deployments (on the Foundry resource)
// =====================================================
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: embeddingModelName
  sku: {
    name: 'Standard'
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelConfig[embeddingModelName].version
    }
  }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: chatModelName
  sku: {
    name: 'Standard'
    capacity: chatCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelConfig[chatModelName].version
    }
    // Disable content filtering — Knowledge Bases pass retrieved document chunks as
    // prompt context, which often triggers the default filter on healthcare/manufacturing content
    raiPolicyName: 'Microsoft.Nil'
  }
  dependsOn: [
    embeddingDeployment
  ]
}

// =====================================================
// Foundry Project (child resource of the Foundry account)
// Replaces legacy Microsoft.MachineLearningServices/workspaces kind=Project
// =====================================================
resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServices
  name: projectName
  location: location
  identity: {
    type: !empty(userAssignedIdentityId) ? 'SystemAssigned,UserAssigned' : 'SystemAssigned'
    userAssignedIdentities: !empty(userAssignedIdentityId) ? {
      '${userAssignedIdentityId}': {}
    } : null
  }
  properties: {
    description: 'Foundry Project for Knowledge Retrieval Demo'
    displayName: projectName
  }
}

// =====================================================
// Connections (on the Foundry account, shared across projects)
// Replaces legacy Microsoft.MachineLearningServices/workspaces/connections
// =====================================================

// Connection to AI Search
resource searchConnection 'Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview' = {
  parent: aiServices
  name: 'search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: !empty(searchEndpoint) ? searchEndpoint : 'https://${last(split(searchResourceId, '/'))}.search.windows.net'
    authType: 'AAD'
    useWorkspaceManagedIdentity: true
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchResourceId
      location: location
    }
  }
  dependsOn: [
    aiProject
  ]
}

// =====================================================
// Outputs
// =====================================================

// Project outputs
output projectId string = aiProject.id
output projectName string = aiProject.name
output projectEndpoint string = aiServices.properties.endpoint

// AI Services outputs (for model inference)
output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output aiServicesPrincipalId string = aiServices.identity.principalId
output projectPrincipalId string = aiProject.identity.principalId
output embeddingDeploymentName string = embeddingDeployment.name
output chatDeploymentName string = chatDeployment.name
