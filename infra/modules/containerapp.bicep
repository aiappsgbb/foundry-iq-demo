// Azure Container Apps hosting for Next.js application
// Follows azd conventions: fetchLatestImage, SERVICE_WEB_IMAGE_NAME, identity-based ACR pull
@description('Name prefix for container app resources')
param baseName string

@description('Location for resources')
param location string = resourceGroup().location

@description('Tags for resources')
param tags object = {}

@description('Log Analytics workspace ID for Container App Environment')
param logAnalyticsWorkspaceId string

@description('Whether the container app already exists (azd sets SERVICE_WEB_RESOURCE_EXISTS)')
param exists bool

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
// Fetch latest image (azd convention for idempotent deploys)
// On first deploy: no image exists yet, falls back to placeholder
// On subsequent deploys: uses the existing image to avoid downtime
// =====================================================
module fetchLatestImage './fetch-container-image.bicep' = {
  name: '${baseName}-fetch-image'
  params: {
    exists: exists
    name: '${baseName}-app'
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
    type: 'SystemAssigned'
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
          // Use existing image if app already exists, otherwise placeholder
          image: fetchLatestImage.outputs.?containers[?0].?image ?? 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
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
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsightsConnectionString }
            { name: 'PORT', value: '80' }
          ]
        }
      ]
      scale: {
        minReplicas: 0
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
