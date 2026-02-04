// Application Insights telemetry for Next.js server-side
import * as appInsights from 'applicationinsights'

let isInitialized = false
let client: appInsights.TelemetryClient | null = null

// Define SeverityLevel manually (matches Application Insights spec)
export enum SeverityLevel {
  Verbose = 0,
  Information = 1,
  Warning = 2,
  Error = 3,
  Critical = 4,
}

/**
 * Initialize Application Insights SDK
 * Call this once at server startup via instrumentation.ts
 */
export function setupApplicationInsights() {
  const connectionString = process.env.APPLICATIONINSIGHTS_CONNECTION_STRING

  if (!connectionString) {
    console.warn('[Telemetry] APPLICATIONINSIGHTS_CONNECTION_STRING not set - telemetry disabled')
    return
  }

  if (isInitialized) {
    return
  }

  try {
    appInsights
      .setup(connectionString)
      .setAutoCollectRequests(true)
      .setAutoCollectPerformance(true, true)
      .setAutoCollectExceptions(true)
      .setAutoCollectDependencies(true)
      .setAutoCollectConsole(true, true) // Captures console.log/error
      .setUseDiskRetryCaching(true)
      .setSendLiveMetrics(false) // Disable Live Metrics to reduce overhead
      .setDistributedTracingMode(appInsights.DistributedTracingModes.AI_AND_W3C)

    appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRole] = 'foundry-iq-demo'
    appInsights.defaultClient.context.tags[appInsights.defaultClient.context.keys.cloudRoleInstance] = 
      process.env.HOSTNAME || process.env.COMPUTERNAME || 'local'

    appInsights.start()
    client = appInsights.defaultClient
    isInitialized = true

    console.log('[Telemetry] Application Insights initialized successfully')
  } catch (error) {
    console.error('[Telemetry] Failed to initialize Application Insights:', error)
  }
}

/**
 * Get the Application Insights client
 */
export function getClient(): appInsights.TelemetryClient | null {
  return client
}

/**
 * Track a custom event
 */
export function trackEvent(name: string, properties?: Record<string, string>, measurements?: Record<string, number>) {
  if (!client) return
  client.trackEvent({ name, properties, measurements })
}

/**
 * Track an exception with full stack trace
 */
export function trackException(error: Error, properties?: Record<string, string>) {
  if (!client) {
    console.error('[Telemetry] Exception (no client):', error)
    return
  }
  client.trackException({
    exception: error,
    properties: {
      ...properties,
      stack: error.stack || '',
    },
  })
}

/**
 * Track a trace message (log)
 */
export function trackTrace(
  message: string, 
  severity: SeverityLevel = SeverityLevel.Information,
  properties?: Record<string, string>
) {
  if (!client) return
  // SDK expects severity as number (0-4), cast to any to satisfy type checker
  client.trackTrace({ message, severity: severity as unknown as string, properties })
}

/**
 * Track a dependency call (external API, database, etc.)
 */
export function trackDependency(
  name: string,
  data: string,
  duration: number,
  success: boolean,
  dependencyTypeName: string = 'HTTP',
  properties?: Record<string, string>
) {
  if (!client) return
  client.trackDependency({
    name,
    data,
    duration,
    success,
    dependencyTypeName,
    properties,
  })
}

/**
 * Track a metric
 */
export function trackMetric(name: string, value: number, properties?: Record<string, string>) {
  if (!client) return
  client.trackMetric({ name, value, properties })
}

/**
 * Flush pending telemetry - call before app shutdown
 */
export async function flush(): Promise<void> {
  if (!client) return
  // Modern SDK uses promise-based flush
  await client.flush()
}
