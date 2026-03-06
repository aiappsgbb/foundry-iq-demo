// RBAC assignments for an existing AI Services (Foundry) account
// Deployed scoped to the Foundry's resource group when it differs from the main deployment RG.

@description('Name of the existing AI Services account')
param aiServicesName string

@description('Principal ID of the UAMI to grant Cognitive Services User')
param uamiPrincipalId string

@description('Principal ID of the Search service system MI (for embedding/OCR during indexing)')
param searchServicePrincipalId string = ''

var cognitiveServicesUser = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aiServicesName
}

// UAMI → Cognitive Services User
resource uamiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, uamiPrincipalId, cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUser)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Search MI → Cognitive Services User (for vectorization during indexing)
resource searchMiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(searchServicePrincipalId)) {
  name: guid(aiServices.id, searchServicePrincipalId, cognitiveServicesUser)
  scope: aiServices
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUser)
    principalId: searchServicePrincipalId
    principalType: 'ServicePrincipal'
  }
}
