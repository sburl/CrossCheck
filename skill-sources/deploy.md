---
name: deploy
description: Deploy the current project to its hosting platform (Railway, Vercel, or GitHub Pages). Auto-detects platform, pushes, monitors deploy, and reports status.
---

**Created:** 2026-03-07-00-00
**Last Updated:** 2026-03-07-00-00

# Deploy

Deploy the current project to its configured hosting platform.

## Step 1: Detect Platform

Check for platform indicators in order:

```bash
# Railway
if [ -f "railway.json" ] || [ -f "railway.toml" ] || railway status 2>/dev/null | grep -q "Project"; then
    PLATFORM="railway"
# Vercel
elif [ -f "vercel.json" ] || [ -f ".vercel/project.json" ] || vercel whoami 2>/dev/null; then
    PLATFORM="vercel"
# GitHub Pages
elif gh api repos/{owner}/{repo}/pages 2>/dev/null | grep -q "url"; then
    PLATFORM="github-pages"
else
    echo "No deployment platform detected."
    echo "Supported: Railway (railway.json), Vercel (vercel.json), GitHub Pages"
    echo "Ask the user which platform to use."
    exit 1
fi
echo "Detected platform: $PLATFORM"
```

If detection fails, ask the user which platform. Do not guess.

## Step 2: Pre-Deploy Checks

Before deploying:

1. Ensure all changes are committed (no dirty working tree)
2. Ensure current branch is pushed to remote
3. Run a quick test if test runner is available

```bash
# Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo "Uncommitted changes detected. Commit first."
    exit 1
fi

# Push if needed
git push origin "$(git branch --show-current)" 2>/dev/null
```

## Step 3: Deploy

### Railway

```bash
# Deploy current branch
railway up --detach

# Wait briefly then check status
sleep 5
railway status

# Tail logs to verify startup
railway logs --tail 50
```

If the deploy fails or the service isn't responding:

```bash
# Check recent deploy logs
railway logs --tail 100

# Force redeploy if needed
railway redeploy
```

### Vercel

```bash
# Deploy (production if on main, preview otherwise)
BRANCH=$(git branch --show-current)
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    vercel --prod
else
    vercel
fi
```

### GitHub Pages

```bash
# GitHub Pages deploys automatically on push to the configured branch
# Verify the deploy status
gh api repos/{owner}/{repo}/pages/builds --jq '.[0] | {status, created_at}'

# Get the site URL
gh api repos/{owner}/{repo}/pages --jq '.html_url'
```

## Step 4: Verify

After deploy completes:

1. Get the deployment URL from the platform output
2. Report the URL and status to the user
3. If `/webapp-test` is available and applicable, offer to screenshot the deployed site

```
Deploy complete.
Platform: {platform}
URL: {url}
Status: {success/failed}
```

## Step 5: If Deploy Fails

1. Read the deploy logs (platform-specific)
2. Identify the error (build failure, env var missing, port mismatch, etc.)
3. Fix the issue locally
4. Re-run from Step 2

Do NOT ask the user to check a dashboard. Read the logs yourself with CLI tools.
