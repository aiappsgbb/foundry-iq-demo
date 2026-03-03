import { NextRequest, NextResponse } from 'next/server'
import { getSearchAuthHeaders } from '@/lib/search-auth'

// Force dynamic rendering - this route always needs fresh data
export const dynamic = 'force-dynamic'
export const revalidate = 0

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION

export async function GET() {
  try {
    if (!ENDPOINT || !API_VERSION) {
      return NextResponse.json(
        { error: 'Azure Search configuration missing' },
        { status: 500 }
      )
    }

    const authHeaders = await getSearchAuthHeaders()
    const response = await fetch(
      `${ENDPOINT}/knowledgesources?api-version=${API_VERSION}`,
      {
        headers: {
          ...authHeaders,
          'Cache-Control': 'no-cache'
        },
        cache: 'no-store'
      }
    )

    if (!response.ok) {
      return NextResponse.json(
        { error: 'Failed to fetch knowledge sources' },
        { status: response.status }
      )
    }

    const data = await response.json()

    return NextResponse.json(data, {
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      }
    })
  } catch (error) {
    console.error('Knowledge sources API error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

export async function PUT(req: NextRequest) {
  try {
    if (!ENDPOINT || !API_VERSION) {
      return NextResponse.json(
        { error: 'Azure Search configuration missing' },
        { status: 500 }
      )
    }

    const body = await req.json()
    const sourceName = body.name

    const authHeaders = await getSearchAuthHeaders()
    const response = await fetch(
      `${ENDPOINT}/knowledgesources/${sourceName}?api-version=${API_VERSION}`,
      {
        method: 'PUT',
        headers: authHeaders,
        body: JSON.stringify(body)
      }
    )

    if (!response.ok) {
      const errorData = await response.json()
      return NextResponse.json(
        { error: errorData.error?.message || 'Failed to create knowledge source' },
        { status: response.status }
      )
    }

    const data = await response.json()
    return NextResponse.json(data)
  } catch (error) {
    console.error('Knowledge source creation error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}