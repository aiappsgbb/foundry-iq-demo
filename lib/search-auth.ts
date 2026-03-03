import { DefaultAzureCredential } from '@azure/identity'

const SEARCH_SCOPE = 'https://search.azure.com/.default'

let credential: DefaultAzureCredential | null = null
let cachedToken: { token: string; expiresOn: number } | null = null

function getCredential(): DefaultAzureCredential {
  if (!credential) {
    credential = new DefaultAzureCredential()
  }
  return credential
}

/**
 * Get a Bearer token for Azure AI Search data-plane API.
 * Uses DefaultAzureCredential which works with:
 *   - Azure CLI credentials (local dev)
 *   - Managed Identity (SWA deployment)
 *   - Environment credentials (CI/CD)
 */
export async function getSearchBearerToken(): Promise<string> {
  // Check cache (refresh 5 min before expiry)
  if (cachedToken && cachedToken.expiresOn > Date.now() + 5 * 60 * 1000) {
    return cachedToken.token
  }

  const tokenResponse = await getCredential().getToken(SEARCH_SCOPE)
  if (!tokenResponse) {
    throw new Error('Failed to get Azure Search bearer token')
  }

  cachedToken = {
    token: tokenResponse.token,
    expiresOn: tokenResponse.expiresOnTimestamp || Date.now() + 60 * 60 * 1000
  }

  return cachedToken.token
}

/**
 * Get authorization headers for Azure AI Search REST API calls.
 * Returns Bearer token auth headers (no API key needed).
 */
export async function getSearchAuthHeaders(): Promise<Record<string, string>> {
  const token = await getSearchBearerToken()
  return {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json'
  }
}
