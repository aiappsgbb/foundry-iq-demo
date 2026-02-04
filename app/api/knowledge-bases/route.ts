import { NextResponse } from 'next/server'
import { createRequestLogger } from '@/lib/logger'

// Force dynamic rendering - this route always needs fresh data
export const dynamic = 'force-dynamic'
export const revalidate = 0

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT
const API_KEY = process.env.AZURE_SEARCH_API_KEY
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION

export async function GET() {
  const log = createRequestLogger()
  
  try {
    if (!ENDPOINT || !API_KEY || !API_VERSION) {
      log.error('Missing environment variables', undefined, {
        hasEndpoint: !!ENDPOINT,
        hasApiKey: !!API_KEY,
        hasApiVersion: !!API_VERSION
      })
      return NextResponse.json(
        { error: 'Azure Search configuration missing', details: {
          hasEndpoint: !!ENDPOINT,
          hasApiKey: !!API_KEY,
          hasApiVersion: !!API_VERSION
        }},
        { status: 500 }
      )
    }

    const url = `${ENDPOINT}/knowledgebases?api-version=${API_VERSION}`
    log.info('Fetching knowledge bases', { endpoint: ENDPOINT })

    const response = await fetch(url, {
      headers: {
        'api-key': API_KEY,
        'Cache-Control': 'no-cache'
      },
      cache: 'no-store'
    })

    if (!response.ok) {
      const errorText = await response.text()
      log.error('Knowledge bases API error', undefined, {
        status: response.status,
        statusText: response.statusText,
        error: errorText
      })
      return NextResponse.json(
        { error: 'Failed to fetch knowledge bases', status: response.status, details: errorText },
        { status: response.status }
      )
    }

    const data = await response.json()
    log.info('Knowledge bases fetched successfully', { count: data.value?.length || 0 })

    return NextResponse.json(data, {
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      }
    })
  } catch (error) {
    log.error('Knowledge bases API exception', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
