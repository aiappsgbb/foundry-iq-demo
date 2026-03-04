import { NextResponse } from 'next/server'
import { getFoundryAuthHeaders, getFoundryProjectEndpoint } from '@/lib/foundry-auth'

/**
 * POST /api/agentsv2/responses
 * 
 * Foundry Agents v2 Responses API (single-call pattern).
 * Proxies requests to the Azure AI Foundry Agent Service using
 * DefaultAzureCredential (Managed Identity in ACA, CLI creds locally).
 * 
 * Request body should include:
 *   - input: string (user message)
 *   - agent_name: string (name of the agent to use)
 *   - previous_response_id?: string (for multi-turn conversation)
 */
export async function POST(request: Request) {
  try {
    const body = await request.json()

    let projectEndpoint: string
    try {
      projectEndpoint = getFoundryProjectEndpoint()
    } catch {
      return NextResponse.json(
        { error: 'Foundry endpoint not configured. Set FOUNDRY_PROJECT_ENDPOINT and FOUNDRY_PROJECT_NAME.' },
        { status: 500 }
      )
    }

    const headers = await getFoundryAuthHeaders()

    // Build the Responses API request
    const { input, agent_name, previous_response_id } = body

    const requestBody: Record<string, unknown> = {
      input,
      // Use agent_reference to route to the named agent
      agent_reference: {
        name: agent_name || 'foundry-iq-agent',
        type: 'agent_reference'
      }
    }

    if (previous_response_id) {
      requestBody.previous_response_id = previous_response_id
    }

    const url = `${projectEndpoint}/openai/v1/responses`

    const response = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(requestBody),
    })

    if (!response.ok) {
      const errorText = await response.text()
      return NextResponse.json(
        { 
          error: 'Failed to get response from Foundry Agent',
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
