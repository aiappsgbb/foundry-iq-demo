// Azure AI Foundry Hub, Project, and AI Services with model deployments
// This module creates the complete AI infrastructure without requiring a separate OpenAI resource

@description('Name of the AI Foundry hub')
param hubName string

@description('Name of the AI Foundry project')
param projectName string

@description('Name of the AI Services account (hosts model deployments)')
param aiServicesName string = '${hubName}-ais'

@description('Location for AI Foundry resources')
param location string = resourceGroup().location

@description('Tags for AI Foundry resources')
param tags object = {}

@description('Search resource ID to connect')
param searchResourceId string

@description('Storage account resource ID to connect')
param storageAccountId string

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

// Create Azure AI Services account (unified Cognitive Services account)
// This hosts model deployments and serves as the OpenAI endpoint
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiServicesName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    disableLocalAuth: false
  }
}

// Deploy embedding model on AI Services
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
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

// Deploy chat model on AI Services
resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
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
  }
  dependsOn: [
    embeddingDeployment
  ]
}

// Create AI Hub (AI Studio workspace)
resource aiHub 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: hubName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'Hub'
  properties: {
    description: 'Azure AI Foundry Hub for Knowledge Retrieval Demo'
    friendlyName: hubName
    storageAccount: storageAccountId
    publicNetworkAccess: 'Enabled'
  }
}

// Create AI Project under the hub
resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'Project'
  properties: {
    description: 'Azure AI Foundry Project for Agentic RAG'
    friendlyName: projectName
    hubResourceId: aiHub.id
    publicNetworkAccess: 'Enabled'
  }
}

// Create connection to AI Services (provides OpenAI models)
resource aiServicesConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: aiProject
  name: 'aiservices-connection'
  properties: {
    category: 'AzureOpenAI'
    target: aiServices.id
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: aiServices.id
    }
  }
}

// Create connection to AI Search
resource searchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-04-01' = {
  parent: aiProject
  name: 'search-connection'
  properties: {
    category: 'CognitiveSearch'
    target: searchResourceId
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ResourceId: searchResourceId
    }
  }
}

// Output Foundry details
output hubId string = aiHub.id
output hubName string = aiHub.name
output projectId string = aiProject.id
output projectName string = aiProject.name
output projectEndpoint string = 'https://${aiProject.properties.workspaceId}.${location}.api.azureml.ms'
output hubPrincipalId string = aiHub.identity.principalId
output projectPrincipalId string = aiProject.identity.principalId

// AI Services outputs (for model inference - replaces standalone OpenAI)
output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output aiServicesKey string = aiServices.listKeys().key1
output embeddingDeploymentName string = embeddingDeployment.name
output chatDeploymentName string = chatDeployment.name
