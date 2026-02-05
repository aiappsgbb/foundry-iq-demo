// RBAC Role Assignments for Azure AI Search Knowledge Retrieval Demo
// This module assigns proper permissions to the Static Web App managed identity

@description('Principal ID of the Static Web App managed identity')
param staticWebAppPrincipalId string

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
  // Storage Blob Data Contributor - read/write/delete blobs
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  // Cognitive Services User - read access to cognitive services
  cognitiveServicesUser: 'a97b65f3-24c7-4388-baec-2e87135dc908'
}

// =====================================================
// Search Service RBAC
// =====================================================
resource searchService 'Microsoft.Search/searchServices@2023-11-01' existing = if (!empty(searchServiceId)) {
  name: last(split(searchServiceId, '/'))
}

resource searchRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServiceId)) {
  name: guid(searchServiceId, staticWebAppPrincipalId, roleDefinitions.searchIndexDataContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchIndexDataContributor)
    principalId: staticWebAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Storage Account RBAC
// =====================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountId)) {
  name: last(split(storageAccountId, '/'))
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(storageAccountId)) {
  name: guid(storageAccountId, staticWebAppPrincipalId, roleDefinitions.storageBlobDataContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataContributor)
    principalId: staticWebAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// AI Services (Foundry) RBAC
// =====================================================
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!empty(aiServicesId)) {
  name: last(split(aiServicesId, '/'))
}

resource aiServicesRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiServicesId)) {
  name: guid(aiServicesId, staticWebAppPrincipalId, roleDefinitions.cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cognitiveServicesUser)
    principalId: staticWebAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Outputs
// =====================================================
output searchRoleAssignmentId string = !empty(searchServiceId) ? searchRoleAssignment.id : ''
output storageRoleAssignmentId string = !empty(storageAccountId) ? storageRoleAssignment.id : ''
output aiServicesRoleAssignmentId string = !empty(aiServicesId) ? aiServicesRoleAssignment.id : ''
