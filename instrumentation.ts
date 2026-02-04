// Next.js instrumentation file - runs once when server starts
// This sets up Application Insights for server-side telemetry

export async function register() {
  // Only run on Node.js (server-side), not edge runtime
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    const { setupApplicationInsights } = await import('./lib/telemetry')
    setupApplicationInsights()
  }
}
