import { DefaultAzureCredential } from '@azure/identity'

const FOUNDRY_SCOPE = 'https://ai.azure.com/.default'

let credential: DefaultAzureCredential | null = null
let cachedToken: { token: string; expiresOn: number } | null = null

function getCredential(): DefaultAzureCredential {
  if (!credential) {
    credential = new DefaultAzureCredential()
  }
  return credential
}

/**
 * Get a Bearer token for Azure AI Foundry Agent Service.
 * Uses DefaultAzureCredential which works with:
 *   - Managed Identity (ACA deployment)
 *   - Azure CLI credentials (local dev)
 */
export async function getFoundryBearerToken(): Promise<string> {
  if (cachedToken && cachedToken.expiresOn > Date.now() + 5 * 60 * 1000) {
    return cachedToken.token
  }

  const tokenResponse = await getCredential().getToken(FOUNDRY_SCOPE)
  if (!tokenResponse) {
    throw new Error('Failed to get Azure Foundry bearer token')
  }

  cachedToken = {
    token: tokenResponse.token,
    expiresOn: tokenResponse.expiresOnTimestamp || Date.now() + 60 * 60 * 1000
  }

  return cachedToken.token
}

/**
 * Build the Foundry Agent Service project endpoint from env vars.
 * 
 * FOUNDRY_PROJECT_ENDPOINT is the cognitiveservices URL:
 *   https://xxx.cognitiveservices.azure.com
 * 
 * The Agent Service endpoint uses a different domain:
 *   https://xxx.services.ai.azure.com/api/projects/{projectName}
 */
export function getFoundryProjectEndpoint(): string {
  const endpoint = process.env.FOUNDRY_PROJECT_ENDPOINT
  const projectName = process.env.FOUNDRY_PROJECT_NAME

  if (!endpoint || !projectName) {
    throw new Error('FOUNDRY_PROJECT_ENDPOINT and FOUNDRY_PROJECT_NAME must be set')
  }

  // Extract hostname prefix from cognitiveservices URL
  const url = new URL(endpoint)
  const hostPrefix = url.hostname.split('.')[0]

  return `https://${hostPrefix}.services.ai.azure.com/api/projects/${projectName}`
}

/**
 * Get authorization headers for Foundry Agent Service REST API calls.
 */
export async function getFoundryAuthHeaders(): Promise<Record<string, string>> {
  const token = await getFoundryBearerToken()
  return {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  }
}
