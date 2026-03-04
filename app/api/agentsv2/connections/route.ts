import { NextResponse } from 'next/server'
import { DefaultAzureCredential } from '@azure/identity'

const MGMT_SCOPE = 'https://management.azure.com/.default'

/**
 * GET /api/agentsv2/connections
 * 
 * Lists Remote Tool connections for the AI Foundry project using Azure Management API.
 * Uses DefaultAzureCredential for authentication.
 */
export async function GET() {
  try {
    const subscriptionId = process.env.AZURE_SUBSCRIPTION_ID
    const resourceGroup = process.env.AZURE_RESOURCE_GROUP
    const projectName = process.env.FOUNDRY_PROJECT_NAME

    if (!subscriptionId || !resourceGroup || !projectName) {
      return NextResponse.json(
        { error: 'Missing required environment variables: AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP, FOUNDRY_PROJECT_NAME' },
        { status: 500 }
      )
    }

    const credential = new DefaultAzureCredential()
    const tokenResponse = await credential.getToken(MGMT_SCOPE)

    const url = `https://management.azure.com/subscriptions/${subscriptionId}/resourceGroups/${resourceGroup}/providers/Microsoft.MachineLearningServices/workspaces/${projectName}/connections?api-version=2024-04-01`

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${tokenResponse.token}`,
        'Content-Type': 'application/json',
      },
      cache: 'no-store',
    })

    if (!response.ok) {
      const errorText = await response.text()
      return NextResponse.json(
        { 
          error: 'Failed to fetch connections from Azure Management API',
          details: errorText,
          status: response.status 
        },
        { status: response.status }
      )
    }

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json(
      { error: 'Internal server error', details: message },
      { status: 500 }
    )
  }
}
