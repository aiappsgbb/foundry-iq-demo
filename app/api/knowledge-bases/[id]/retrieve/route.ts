import { NextRequest, NextResponse } from 'next/server'
import { createRequestLogger } from '@/lib/logger'

// Force dynamic rendering
export const dynamic = 'force-dynamic'
export const revalidate = 0

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT
const API_KEY = process.env.AZURE_SEARCH_API_KEY
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION

interface RouteContext {
  params: Promise<{ id: string }> | { id: string }
}

export async function POST(request: NextRequest, context: RouteContext) {
  const log = createRequestLogger()
  const startTime = Date.now()
  
  try {
    const params = context.params instanceof Promise ? await context.params : context.params
    const knowledgeBaseId = params.id
    const body = await request.json()

    const aclHeader = request.headers.get('x-ms-query-source-authorization') ??
      request.headers.get('x-ms-user-authorization') ??
      undefined

    const url = `${ENDPOINT}/knowledgebases/${knowledgeBaseId}/retrieve?api-version=${API_VERSION}`

    log.info('Knowledge Base retrieve request', {
      knowledgeBaseId,
      hasAclHeader: !!aclHeader,
      requestBody: JSON.stringify(body)
    })

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': API_KEY!,
        ...(aclHeader ? { 'x-ms-query-source-authorization': aclHeader } : {})
      },
      body: JSON.stringify(body)
    })

    const responseText = await response.text()
    const duration = Date.now() - startTime
    
    if (!response.ok) {
      let parsedError: unknown = responseText
      try {
        parsedError = JSON.parse(responseText)
      } catch {
        // keep as text
      }

      log.error('Azure Search retrieve failed', undefined, {
        knowledgeBaseId,
        status: response.status,
        statusText: response.statusText,
        error: JSON.stringify(parsedError),
        duration: `${duration}ms`
      })

      return NextResponse.json({
        error: `Failed to retrieve from knowledge base (${response.status})`,
        azureError: parsedError,
        details: responseText,
        status: response.status,
        statusText: response.statusText
      }, { status: response.status })
    }

    let data: Record<string, unknown> = {}
    try {
      data = responseText ? JSON.parse(responseText) : {}
    } catch {
      data = { message: responseText }
    }

    log.info('Knowledge Base retrieve successful', {
      knowledgeBaseId,
      hasResponse: !!data.response,
      referencesCount: (data.references as unknown[])?.length || 0,
      activityCount: (data.activity as unknown[])?.length || 0,
      responseLength: responseText.length,
      duration: `${duration}ms`
    })

    // Track as custom event for analytics
    log.event('KnowledgeBaseRetrieve', {
      knowledgeBaseId,
      success: 'true',
      duration: String(duration),
      referencesCount: String((data.references as unknown[])?.length || 0)
    })

    return NextResponse.json(data)
  } catch (error: unknown) {
    const duration = Date.now() - startTime
    const err = error instanceof Error ? error : new Error(String(error))
    
    log.error('Knowledge Base retrieve exception', err, {
      duration: `${duration}ms`
    })
    
    return NextResponse.json({
      error: 'Internal server error',
      details: err.message,
      type: 'exception'
    }, { status: 500 })
  }
}
