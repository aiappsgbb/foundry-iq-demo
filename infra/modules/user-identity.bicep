// User-Assigned Managed Identity (UAMI) for Foundry IQ Demo
// A single identity shared across Container App, AI Services, and Search service.
// Simplifies RBAC: one identity, one set of role assignments.

@description('Name of the managed identity')
param identityName string

@description('Location for the identity')
param location string = resourceGroup().location

@description('Tags for the identity')
param tags object = {}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

output identityId string = identity.id
output identityPrincipalId string = identity.properties.principalId
output identityClientId string = identity.properties.clientId
output identityName string = identity.name
