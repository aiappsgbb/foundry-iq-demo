// Azure Static Web App for Next.js hosting
@description('Name of the static web app')
param staticWebAppName string

@description('Location for the static web app')
param location string = resourceGroup().location

@description('SKU for the static web app')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Standard'

@description('Tags for the static web app')
param tags object = {}

@description('Azure Developer CLI service name for deployment targeting')
param serviceName string = 'web'

@description('Repository URL')
param repositoryUrl string = ''

@description('Branch name')
param branch string = 'main'

@description('Repository token (optional)')
@secure()
param repositoryToken string = ''

@description('Build properties')
// For azd deploy with hybrid Next.js on Azure Static Web Apps:
// - appLocation: 'web/' - The subfolder containing the Next.js application source
// - apiLocation: Leave empty (no standalone API folder)
// - outputLocation: Leave empty for hybrid Next.js (SWA Oryx builder handles it)
// - appBuildCommand: Command to build the Next.js app
// When deploying via azd, these properties inform the SWA deployment process
// See: https://learn.microsoft.com/en-us/azure/static-web-apps/deploy-nextjs-hybrid
param buildProperties object = {
  appLocation: 'web'
  apiLocation: ''
  outputLocation: ''
  appBuildCommand: 'npm run build'
  apiBuildCommand: ''
}

resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticWebAppName
  location: location
  tags: union(tags, { 'azd-service-name': serviceName })
  sku: {
    name: sku
    tier: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    repositoryUrl: repositoryUrl
    branch: branch
    repositoryToken: repositoryToken
    buildProperties: buildProperties
    provider: 'GitHub'
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// Output Static Web App details
output staticWebAppId string = staticWebApp.id
output staticWebAppName string = staticWebApp.name
output staticWebAppUrl string = 'https://${staticWebApp.properties.defaultHostname}'
output staticWebAppPrincipalId string = staticWebApp.identity.principalId
