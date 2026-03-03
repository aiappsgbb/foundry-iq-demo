/** @type {import('next').NextConfig} */
const nextConfig = {
  // Standalone output for Docker / Azure Container Apps deployment
  output: 'standalone',
  // Enable instrumentation hook for Application Insights telemetry
  experimental: {
    instrumentationHook: true,
  },
}
module.exports = nextConfig