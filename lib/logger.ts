// Structured logger for API routes
// Sends logs to both console and Application Insights
import { trackTrace, trackException, trackEvent, SeverityLevel } from './telemetry'

type LogLevel = 'debug' | 'info' | 'warn' | 'error'

interface LogContext {
  [key: string]: unknown
}

const severityMap: Record<LogLevel, number> = {
  debug: SeverityLevel.Verbose,
  info: SeverityLevel.Information,
  warn: SeverityLevel.Warning,
  error: SeverityLevel.Error,
}

function formatMessage(message: string, context?: LogContext): string {
  if (!context || Object.keys(context).length === 0) {
    return message
  }
  return `${message} | ${JSON.stringify(context)}`
}

function stringifyContext(context?: LogContext): Record<string, string> | undefined {
  if (!context) return undefined
  const result: Record<string, string> = {}
  for (const [key, value] of Object.entries(context)) {
    result[key] = typeof value === 'object' ? JSON.stringify(value) : String(value)
  }
  return result
}

/**
 * Logger that sends to console and Application Insights
 */
export const logger = {
  /**
   * Debug level log - only in development
   */
  debug(message: string, context?: LogContext) {
    if (process.env.NODE_ENV === 'development') {
      console.debug(`[DEBUG] ${formatMessage(message, context)}`)
    }
    trackTrace(message, severityMap.debug, stringifyContext(context))
  },

  /**
   * Info level log
   */
  info(message: string, context?: LogContext) {
    console.log(`[INFO] ${formatMessage(message, context)}`)
    trackTrace(message, severityMap.info, stringifyContext(context))
  },

  /**
   * Warning level log
   */
  warn(message: string, context?: LogContext) {
    console.warn(`[WARN] ${formatMessage(message, context)}`)
    trackTrace(message, severityMap.warn, stringifyContext(context))
  },

  /**
   * Error level log
   */
  error(message: string, error?: Error | unknown, context?: LogContext) {
    const errorContext = { ...context }
    
    if (error instanceof Error) {
      errorContext.errorMessage = error.message
      errorContext.errorStack = error.stack
      console.error(`[ERROR] ${formatMessage(message, errorContext)}`)
      trackException(error, stringifyContext(errorContext))
    } else if (error) {
      errorContext.error = typeof error === 'object' ? JSON.stringify(error) : String(error)
      console.error(`[ERROR] ${formatMessage(message, errorContext)}`)
      trackTrace(message, severityMap.error, stringifyContext(errorContext))
    } else {
      console.error(`[ERROR] ${formatMessage(message, context)}`)
      trackTrace(message, severityMap.error, stringifyContext(context))
    }
  },

  /**
   * Track a custom event (for metrics/analytics)
   */
  event(name: string, properties?: LogContext) {
    trackEvent(name, stringifyContext(properties))
  },

  /**
   * Create a child logger with preset context
   */
  child(baseContext: LogContext) {
    return {
      debug: (message: string, context?: LogContext) => 
        logger.debug(message, { ...baseContext, ...context }),
      info: (message: string, context?: LogContext) => 
        logger.info(message, { ...baseContext, ...context }),
      warn: (message: string, context?: LogContext) => 
        logger.warn(message, { ...baseContext, ...context }),
      error: (message: string, error?: Error | unknown, context?: LogContext) => 
        logger.error(message, error, { ...baseContext, ...context }),
      event: (name: string, properties?: LogContext) => 
        logger.event(name, { ...baseContext, ...properties }),
    }
  },
}

/**
 * Create a request-scoped logger with correlation ID
 */
export function createRequestLogger(requestId?: string) {
  const correlationId = requestId || crypto.randomUUID()
  return logger.child({ correlationId })
}
