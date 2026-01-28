/** @type {import('next').NextConfig} */
// For Azure Static Web Apps hybrid Next.js deployment, DO NOT use 'standalone' output.
// SWA's managed hosting handles SSR directly through its Oryx builder.
// See: https://learn.microsoft.com/en-us/azure/static-web-apps/deploy-nextjs-hybrid
const nextConfig = {}
module.exports = nextConfig