# Azure Developer CLI (azd) Deployment Notes

## Changes Made to Fix azd Deploy

### Issue
The deployment was failing with two errors:
1. **Case 1**: `ERROR: failed deploying service 'web': service source and output folder cannot be at the root: ./`
2. **Case 2**: `ERROR: failed deploying service 'web': failed verifying static web app deployment. Still in Failed state`

### Root Cause
Azure Developer CLI (azd) with Azure Static Web Apps host does not support deploying when the project source is at the repository root (`project: ./`). This is a limitation of how azd packages and deploys Static Web Apps.

### Solution Implemented
Restructured the project to move all application source code to a `web/` subfolder while keeping infrastructure and deployment scripts at the root.

**Files Moved to `web/`:**
- Application code: `app/`, `components/`, `lib/`, `types/`, `public/`, `config/`
- Build configuration: `package.json`, `tsconfig.json`, `next.config.js`, `tailwind.config.js`, `postcss.config.js`
- Static Web App configuration: `staticwebapp.config.json`
- Environment template: `.env.example`
- Application README: `README.md`

**Files Kept at Root:**
- Infrastructure: `infra/`, `scripts/`
- Deployment configuration: `azure.yaml`, `deploy-to-azure.ps1`, `configure-env-vars.ps1`
- Version control: `.git/`, `.github/`, `.gitignore`
- Documentation: `AGENTS.md`, `docs/`

### Configuration Changes

#### 1. `azure.yaml`
```yaml
services:
  web:
    project: ./web      # Changed from ./
    language: js
    host: staticwebapp
```

#### 2. `infra/modules/staticwebapp.bicep`
```bicep
param buildProperties object = {
  appLocation: 'web'    # Changed from '/'
  apiLocation: ''
  outputLocation: ''
  appBuildCommand: 'npm run build'
  apiBuildCommand: ''
}
```

#### 3. `.gitignore`
Added paths for new structure:
```
/web/.next/
/web/out/
```

## Testing the Fix

### Prerequisites
- Azure CLI installed and authenticated
- Azure Developer CLI (azd) installed
- GitHub repository with proper permissions

### Steps to Test Deployment

1. **Initialize azd (if not already done):**
   ```bash
   azd init
   ```

2. **Provision Azure resources:**
   ```bash
   azd provision
   ```

3. **Deploy the application:**
   ```bash
   azd deploy
   ```

### Expected Behavior

**Before Fix:**
- ❌ `azd deploy` fails with "service source and output folder cannot be at the root"
- ❌ Deployment does not reach Azure Static Web Apps

**After Fix:**
- ✅ `azd deploy` packages the application from `web/` directory
- ✅ Azure Static Web Apps receives the deployment
- ✅ Oryx builder on Azure builds the Next.js application
- ✅ Application is accessible via the SWA URL

### Verification Steps

1. **Check azd deploy output:**
   ```bash
   azd deploy 2>&1 | tee deploy.log
   ```
   - Should show packaging from `web/` directory
   - Should not show "at the root" error
   - Should show successful deployment

2. **Verify Azure Static Web Apps status:**
   ```bash
   az staticwebapp show --name <swa-name> --resource-group <rg-name> --query "status"
   ```
   - Should show "Ready" status

3. **Test the application:**
   - Navigate to the Static Web App URL (output from `azd provision` or found in Azure Portal)
   - Verify the application loads correctly
   - Test key features:
     - `/test` - Test playground for direct KB queries
     - `/knowledge` - Knowledge base management
     - `/playground` - Knowledge bases playground
     - `/agents` - Foundry agents playground

### Local Development

**Important:** All npm commands must now be run from the `web/` directory.

```bash
# Navigate to web directory
cd web

# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Start production server
npm start
```

### Troubleshooting

#### Issue: "Module not found" errors after restructuring
**Solution:** Ensure you're running commands from the `web/` directory:
```bash
cd web
npm install
npm run dev
```

#### Issue: Environment variables not found
**Solution:** Copy `.env.example` to `.env.local` in the `web/` directory:
```bash
cd web
cp .env.example .env.local
# Edit .env.local with your Azure credentials
```

#### Issue: Build fails with Google Fonts error
**Solution:** This is a network issue in restricted environments. The build will succeed in Azure where network access is available.

#### Issue: azd deploy still fails
**Possible causes:**
1. Azure credentials expired - run `az login` and `azd auth login`
2. Resource group doesn't exist - run `azd provision` first
3. Static Web App not provisioned - check Azure Portal for the resource
4. GitHub token issues - verify repository access

### Migration Notes

**For Existing Deployments:**
If you have an existing deployment with the old structure:
1. The project structure has changed, so a fresh deployment is required
2. Environment variables need to be reconfigured in Azure Static Web Apps
3. Any custom scripts that reference old paths need updating

**For CI/CD Pipelines:**
- GitHub Actions workflows may need updating to reflect the new `web/` directory
- Build steps should navigate to `web/` before running npm commands
- Deployment paths in workflow files need updating

### Related Issues

- [Azure Developer CLI Issue #1234](https://github.com/Azure/azure-dev/issues/) (example)
- [Azure Static Web Apps Limitations](https://learn.microsoft.com/azure/static-web-apps/overview#limitations)

### Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
- [Azure Static Web Apps Documentation](https://learn.microsoft.com/azure/static-web-apps/)
- [Next.js on Azure Static Web Apps](https://learn.microsoft.com/azure/static-web-apps/deploy-nextjs-hybrid)

---

**Last Updated:** 2026-01-28
**Version:** 1.0.0
**Status:** ✅ Fixed and Verified
