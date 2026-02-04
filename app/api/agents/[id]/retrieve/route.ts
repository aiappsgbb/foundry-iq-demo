import { NextRequest, NextResponse } from 'next/server';
import { logger } from '@/lib/logger';

// Force dynamic rendering
export const dynamic = 'force-dynamic'
export const revalidate = 0

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT;
const API_KEY = process.env.AZURE_SEARCH_API_KEY;
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION;

interface RouteContext {
  params: Promise<{ id: string }> | { id: string };
}

export async function POST(request: NextRequest, context: RouteContext) {
  const start = Date.now();
  try {
    const params = context.params instanceof Promise ? await context.params : context.params;
    const agentId = params.id;
    const body = await request.json();

    logger.info('Agent retrieve request', { agentId, hasQuery: !!body?.messages });

    // Forward end-user authorization token for ACL enforcement if provided
    // Support either canonical header or a legacy alias (if client provided)
    const aclHeader = request.headers.get('x-ms-query-source-authorization') ||
                     request.headers.get('x-ms-user-authorization');

    const url = `${ENDPOINT}/agents/${agentId}/retrieve?api-version=${API_VERSION}`;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'api-key': API_KEY!,
        // Pass through ACL header when present for document-level security
        ...(aclHeader ? { 'x-ms-query-source-authorization': aclHeader } : {})
      },
      body: JSON.stringify(body)
    });

    const responseText = await response.text();

    if (!response.ok) {
      let parsedError = responseText;
      try {
        parsedError = JSON.parse(responseText);
      } catch (e) {
        // Response is not JSON
      }

      logger.error('Agent retrieve failed', new Error(`Azure API error: ${response.status}`), {
        agentId,
        status: String(response.status),
        duration: `${Date.now() - start}ms`,
        errorBody: responseText.slice(0, 500)
      });

      return NextResponse.json({
        error: `Failed to retrieve from agent (${response.status})`,
        azureError: parsedError,
        details: responseText,
        status: response.status,
        statusText: response.statusText
      }, { status: response.status });
    }

    let data = {};
    if (responseText) {
      try {
        data = JSON.parse(responseText);
      } catch (e) {
        data = { message: responseText };
      }
    }

    logger.info('Agent retrieve success', { agentId, duration: `${Date.now() - start}ms` });

    return NextResponse.json(data);
  } catch (error: any) {
    logger.error('Agent retrieve exception', error, {
      duration: `${Date.now() - start}ms`
    });
    return NextResponse.json({
      error: 'Internal server error',
      details: error.message,
      stack: error.stack,
      type: 'exception'
    }, { status: 500 });
  }
}