// Foundry Project on an existing AI Services account
// Creates only the project and search connection — no AI Services or model deployments.
// Use this when reusing a centralized Foundry instance for shared model quota.

@description('Name of the existing AI Services account')
param aiServicesName string

@description('Name of the Foundry project to create')
param projectName string

@description('Location for the project')
param location string = resourceGroup().location

@description('Tags')
param tags object = {}

@description('Search service resource ID to connect')
param searchResourceId string

@description('Search service endpoint URL')
param searchEndpoint string = ''

@description('Resource ID of the User-Assigned Managed Identity')
param userAssignedIdentityId string = ''

// Reference the existing AI Services account
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesName
}

// Create project under the existing account
resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServices
  name: projectName
  location: location
  tags: tags
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

// Connection to AI Search (on the account, shared across projects)
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

// Outputs
output projectId string = aiProject.id
output projectName string = aiProject.name
output projectEndpoint string = aiServices.properties.endpoint
output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
