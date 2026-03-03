import { NextRequest, NextResponse } from 'next/server';
import { getSearchAuthHeaders } from '@/lib/search-auth';

const ENDPOINT = process.env.AZURE_SEARCH_ENDPOINT;
const API_VERSION = process.env.AZURE_SEARCH_API_VERSION;

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();

    // Use Search service's managed identity for OpenAI calls (no API key)
    if (body.models && body.models.length > 0) {
      body.models.forEach((model: any) => {
        if (model.kind === 'azureOpenAI' && model.azureOpenAIParameters) {
          model.azureOpenAIParameters.apiKey = null;
          model.azureOpenAIParameters.authIdentity = null;
        }
      });
    }

    const authHeaders = await getSearchAuthHeaders();
    const response = await fetch(`${ENDPOINT}/agents/${body.name}?api-version=${API_VERSION}`, {
      method: 'PUT',
      headers: authHeaders,
      body: JSON.stringify(body),
    });

    const responseText = await response.text();

    if (!response.ok) {
      let parsedError = responseText;
      try {
        parsedError = JSON.parse(responseText);
      } catch (e) {
        // Response is not JSON
      }

      return NextResponse.json({
        error: `Failed to create agent (${response.status})`,
        azureError: parsedError,
        details: responseText,
        status: response.status,
        statusText: response.statusText,
        requestBody: body,
        url: `${ENDPOINT}/agents/${body.name}?api-version=${API_VERSION}`
      }, { status: response.status });
    }

    if (response.status === 204) {
      return NextResponse.json({
        success: true,
        message: 'Agent created successfully',
        name: body.name,
        status: 204
      });
    }

    let data = {};
    if (responseText) {
      try {
        data = JSON.parse(responseText);
      } catch (e) {
        data = { message: responseText, name: body.name };
      }
    }

    return NextResponse.json(data);
  } catch (error: any) {
    return NextResponse.json({
      error: 'Internal server error',
      details: error.message,
      stack: error.stack,
      type: 'exception'
    }, { status: 500 });
  }
}