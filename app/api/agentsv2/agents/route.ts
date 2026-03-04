import { NextResponse } from 'next/server'
import { getFoundryAuthHeaders, getFoundryProjectEndpoint } from '@/lib/foundry-auth'

/**
 * GET /api/agentsv2/agents
 * 
 * Lists Foundry agents in the project.
 * Uses DefaultAzureCredential for authentication.
 */
export async function GET() {
  try {
    let projectEndpoint: string
    try {
      projectEndpoint = getFoundryProjectEndpoint()
    } catch {
      return NextResponse.json(
        { error: 'Foundry endpoint not configured' },
        { status: 500 }
      )
    }

    const headers = await getFoundryAuthHeaders()

    // List agents via the Agent Service API
    const url = `${projectEndpoint}/agents?api-version=v1`

    const response = await fetch(url, {
      method: 'GET',
      headers,
      cache: 'no-store',
    })

    if (!response.ok) {
      const errorText = await response.text()
      return NextResponse.json(
        { 
          error: 'Failed to list agents',
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
