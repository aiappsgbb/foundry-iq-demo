// Azure Container Apps hosting for Next.js application
// Uses SERVICE_WEB_IMAGE_NAME (set by azd after deploy) to preserve image across provisions
@description('Name prefix for container app resources')
param baseName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Tags for resources')
param tags object = {}

@description('Log Analytics workspace ID for Container App Environment')
param logAnalyticsWorkspaceId string

@description('Container image name from last azd deploy (empty on first deploy)')
param imageName string = ''

// =====================================================
// Environment Variables
// =====================================================
@description('Azure AI Search endpoint URL')
param azureSearchEndpoint string = ''

@description('Azure AI Search API version')
param azureSearchApiVersion string = '2025-11-01-preview'

@description('Azure OpenAI endpoint URL')
param azureOpenAIEndpoint string = ''

@description('Foundry Project endpoint URL')
param foundryProjectEndpoint string = ''

@description('Foundry Project name')
param foundryProjectName string = ''

@description('Azure Subscription ID')
param azureSubscriptionId string = ''

@description('Azure Resource Group name')
param azureResourceGroup string = ''

@description('Application Insights connection string')
param applicationInsightsConnectionString string = ''

@description('Resource ID of the User-Assigned Managed Identity')
param userAssignedIdentityId string = ''

@description('Client ID of the User-Assigned Managed Identity (for DefaultAzureCredential)')
param userAssignedIdentityClientId string = ''

// =====================================================
// Container Registry
// =====================================================
var acrName = replace('cr${baseName}', '-', '')

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// =====================================================
// Container App Environment
// =====================================================
resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${baseName}-cae'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2022-10-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2022-10-01').primarySharedKey
      }
    }
  }
}

// =====================================================
// Container App
// =====================================================
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${baseName}-app'
  location: location
  tags: union(tags, { 'azd-service-name': 'web' })
  identity: {
    type: !empty(userAssignedIdentityId) ? 'SystemAssigned,UserAssigned' : 'SystemAssigned'
    userAssignedIdentities: !empty(userAssignedIdentityId) ? {
      '${userAssignedIdentityId}': {}
    } : null
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 80
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: acr.listCredentials().passwords[0].value
        }
      ]
    }
    template: {
      containers: [
        {
          // Use last deployed image if available, otherwise placeholder (azd deploy replaces it)
          image: !empty(imageName) ? imageName : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          name: 'web'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'AZURE_SEARCH_ENDPOINT', value: azureSearchEndpoint }
            { name: 'AZURE_SEARCH_API_VERSION', value: azureSearchApiVersion }
            { name: 'NEXT_PUBLIC_SEARCH_ENDPOINT', value: azureSearchEndpoint }
            { name: 'NEXT_PUBLIC_AZURE_SEARCH_API_VERSION', value: azureSearchApiVersion }
            { name: 'AZURE_OPENAI_ENDPOINT', value: azureOpenAIEndpoint }
            { name: 'NEXT_PUBLIC_AZURE_OPENAI_ENDPOINT', value: azureOpenAIEndpoint }
            { name: 'FOUNDRY_PROJECT_ENDPOINT', value: foundryProjectEndpoint }
            { name: 'FOUNDRY_PROJECT_NAME', value: foundryProjectName }
            { name: 'NEXT_PUBLIC_FOUNDRY_ENDPOINT', value: foundryProjectEndpoint }
            { name: 'AZURE_SUBSCRIPTION_ID', value: azureSubscriptionId }
            { name: 'AZURE_RESOURCE_GROUP', value: azureResourceGroup }
            { name: 'AZURE_CLIENT_ID', value: userAssignedIdentityClientId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsightsConnectionString }
            { name: 'PORT', value: '80' }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// =====================================================
// Outputs
// =====================================================
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppName string = containerApp.name
output containerAppPrincipalId string = containerApp.identity.principalId
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output containerAppEnvName string = containerAppEnv.name
