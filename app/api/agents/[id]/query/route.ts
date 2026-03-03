import { NextRequest, NextResponse } from 'next/server';
import { getSearchAuthHeaders } from '@/lib/search-auth';

// Force dynamic rendering
export const dynamic = 'force-dynamic'
export const revalidate = 0

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT;
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION;

interface RouteContext {
  params: Promise<{ id: string }> | { id: string };
}

export async function POST(request: NextRequest, context: RouteContext) {
  try {
    const params = context.params instanceof Promise ? await context.params : context.params;
    const { id } = params;
    const body = await request.json();

    // Transform messages content from string to array format for 2025-11-01-preview API
    if (body.messages && Array.isArray(body.messages)) {
      body.messages = body.messages.map((msg: { role: string; content: unknown }) => ({
        ...msg,
        content: typeof msg.content === 'string'
          ? [{ type: 'text', text: msg.content }]
          : msg.content
      }))
    }

    const authHeaders = await getSearchAuthHeaders();
    const response = await fetch(`${ENDPOINT}/agents/${id}/retrieve?api-version=${API_VERSION}`, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorText = await response.text();
      return NextResponse.json({ error: 'Failed to query agent', details: errorText }, { status: response.status });
    }

    const data = await response.json();
    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({ error: 'Internal server error', details: error.message }, { status: 500 });
  }
}