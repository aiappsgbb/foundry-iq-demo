// RBAC Role Assignments for Azure AI Search Knowledge Retrieval Demo
// Assigns permissions to:
//   1. Container App managed identity (app runtime)
//   2. Search service managed identity (knowledge source ingestion)

@description('Principal ID of the Container App managed identity')
param appPrincipalId string

@description('Principal ID of the Search service managed identity')
param searchServicePrincipalId string = ''

@description('Search Service resource ID')
param searchServiceId string = ''

@description('Storage Account resource ID')
param storageAccountId string = ''

@description('AI Services (Foundry) resource ID')
param aiServicesId string = ''

// =====================================================
// Azure Built-in Role IDs
// Reference: https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
// =====================================================
var roleDefinitions = {
  // Search Index Data Contributor - read/write access to search indexes
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  // Search Service Contributor - management plane access (knowledge bases, sources, etc.)
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  // Storage Blob Data Contributor - read/write/delete blobs
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  // Storage Blob Data Reader - read blobs
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  // Cognitive Services User - read access to cognitive services
  cognitiveServicesUser: 'a97b65f3-24c7-4388-baec-2e87135dc908'
}

// =====================================================
// Search Service RBAC (for Container App)
// =====================================================
resource searchService 'Microsoft.Search/searchServices@2023-11-01' existing = if (!empty(searchServiceId)) {
  name: last(split(searchServiceId, '/'))
}

resource searchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServiceId)) {
  name: guid(searchServiceId, appPrincipalId, roleDefinitions.searchIndexDataContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchIndexDataContributor)
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Search Service Contributor - for management plane operations (knowledge bases, sources, etc.)
resource searchServiceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServiceId)) {
  name: guid(searchServiceId, appPrincipalId, roleDefinitions.searchServiceContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchServiceContributor)
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Storage Account RBAC (for Container App)
// =====================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountId)) {
  name: last(split(storageAccountId, '/'))
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(storageAccountId)) {
  name: guid(storageAccountId, appPrincipalId, roleDefinitions.storageBlobDataContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataContributor)
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// AI Services (Foundry) RBAC (for Container App)
// =====================================================
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!empty(aiServicesId)) {
  name: last(split(aiServicesId, '/'))
}

resource aiServicesRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiServicesId)) {
  name: guid(aiServicesId, appPrincipalId, roleDefinitions.cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cognitiveServicesUser)
    principalId: appPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Search Service Identity RBAC
// The Search service's managed identity needs access to AI Services (for embeddings/chat)
// and Storage (for blob indexing) in knowledge source ingestion.
// =====================================================

// Search → AI Services (Cognitive Services User)
resource searchAiServicesRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiServicesId) && !empty(searchServicePrincipalId)) {
  name: guid(aiServicesId, searchServicePrincipalId, roleDefinitions.cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cognitiveServicesUser)
    principalId: searchServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Search → Storage (Blob Data Reader)
resource searchStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(storageAccountId) && !empty(searchServicePrincipalId)) {
  name: guid(storageAccountId, searchServicePrincipalId, roleDefinitions.storageBlobDataReader)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataReader)
    principalId: searchServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Outputs
// =====================================================
output searchRoleAssignmentId string = !empty(searchServiceId) ? searchRoleAssignment.id : ''
output storageRoleAssignmentId string = !empty(storageAccountId) ? storageRoleAssignment.id : ''
output aiServicesRoleAssignmentId string = !empty(aiServicesId) ? aiServicesRoleAssignment.id : ''
