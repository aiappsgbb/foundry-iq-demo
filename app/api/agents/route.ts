import { NextResponse } from 'next/server';
import { getSearchAuthHeaders } from '@/lib/search-auth';

// Force dynamic rendering - this route always needs fresh data
export const dynamic = 'force-dynamic'
export const revalidate = 0

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT;
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION;

export async function GET() {
  try {
    const authHeaders = await getSearchAuthHeaders();
    const response = await fetch(`${ENDPOINT}/agents?api-version=${API_VERSION}`, {
      headers: {
        ...authHeaders,
        'Cache-Control': 'no-cache'
      },
      cache: 'no-store'
    });

    if (!response.ok) {
      return NextResponse.json({ error: 'Failed to fetch agents' }, { status: response.status });
    }

    const data = await response.json();

    return NextResponse.json(data, {
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      }
    });
  } catch (error) {
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}