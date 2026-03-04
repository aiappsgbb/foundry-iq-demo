// RBAC Role Assignments for Azure AI Search Knowledge Retrieval Demo
// Uses a single User-Assigned Managed Identity (UAMI) for all service-to-service auth.
// Also assigns roles for the Search service system MI (needed for knowledge source ingestion).

@description('Principal ID of the User-Assigned Managed Identity (shared across all services)')
param uamiPrincipalId string

@description('Principal ID of the Search service system-assigned managed identity (for indexer ingestion)')
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
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  cognitiveServicesUser: 'a97b65f3-24c7-4388-baec-2e87135dc908'
}

// =====================================================
// Existing resource references
// =====================================================
resource searchService 'Microsoft.Search/searchServices@2023-11-01' existing = if (!empty(searchServiceId)) {
  name: last(split(searchServiceId, '/'))
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountId)) {
  name: last(split(storageAccountId, '/'))
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!empty(aiServicesId)) {
  name: last(split(aiServicesId, '/'))
}

// =====================================================
// UAMI → Search Service
// Used by: Container App (runtime), Foundry Agent (MCP tools)
// =====================================================
resource uamiSearchDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServiceId)) {
  name: guid(searchServiceId, uamiPrincipalId, roleDefinitions.searchIndexDataContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchIndexDataContributor)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource uamiSearchDataReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServiceId)) {
  name: guid(searchServiceId, uamiPrincipalId, roleDefinitions.searchIndexDataReader)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchIndexDataReader)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource uamiSearchServiceContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServiceId)) {
  name: guid(searchServiceId, uamiPrincipalId, roleDefinitions.searchServiceContributor)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchServiceContributor)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// UAMI → Storage Account
// Used by: Container App (runtime blob access)
// =====================================================
resource uamiStorageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(storageAccountId)) {
  name: guid(storageAccountId, uamiPrincipalId, roleDefinitions.storageBlobDataContributor)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataContributor)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// UAMI → AI Services (Foundry)
// Used by: Container App (model inference), Foundry Agent (MCP tool execution)
// =====================================================
resource uamiCognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiServicesId)) {
  name: guid(aiServicesId, uamiPrincipalId, roleDefinitions.cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cognitiveServicesUser)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Search Service System MI → AI Services (Cognitive Services User)
// Needed for knowledge source ingestion (embeddings/chat during indexing)
// =====================================================
resource searchAiServicesRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiServicesId) && !empty(searchServicePrincipalId)) {
  name: guid(aiServicesId, searchServicePrincipalId, roleDefinitions.cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cognitiveServicesUser)
    principalId: searchServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}

// =====================================================
// Search Service System MI → Storage (Blob Data Reader)
// Needed for knowledge source indexing from blob storage
// =====================================================
resource searchStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(storageAccountId) && !empty(searchServicePrincipalId)) {
  name: guid(storageAccountId, searchServicePrincipalId, roleDefinitions.storageBlobDataReader)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataReader)
    principalId: searchServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}
