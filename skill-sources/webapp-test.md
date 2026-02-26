---
name: webapp-test
description: |
  Automated Playwright-based web app testing. Screenshot, inspect DOM, discover selectors,
  interact with elements, and run visual regression checks against a running localhost app.
  Use when: "test webapp", "browser test", "screenshot app", "check UI", "visual regression",
  "end-to-end test", or verifying a web app works after changes.
---

**Created:** 2026-02-26-00-00
**Last Updated:** 2026-02-26-00-00

*Inspired by [anthropics/skills](https://github.com/anthropics/skills) — webapp-testing skill.*

# Webapp Test

Automated Playwright-based testing for web applications running on localhost. Takes screenshots,
discovers interactive elements, runs interaction tests, and performs visual regression checks.

## Usage

```bash
/webapp-test                    # Full test (all 4 phases)
/webapp-test --recon            # Phase 1 only: screenshot + DOM dump
/webapp-test --selectors        # Phase 2 only: discover interactive elements
/webapp-test --quick            # Phases 1-3: recon + selectors + interaction
```

---

## Prerequisites

Bootstrap Playwright (one-time, auto-detected):

**Python:**
```bash
pip install playwright && playwright install chromium
```

**Node:**
```bash
npx playwright install chromium
```

If neither is installed, prompt the user to choose and install.

---

## Phase 1: Reconnaissance

Gather baseline information about the running app.

1. **Detect running app** — Check common ports (3000, 3001, 4000, 5000, 5173, 8000, 8080, 8888).
   If nothing found, check for a start script (`package.json`, `Makefile`, `Procfile`) and offer
   to start the server. Track whether we started it (for cleanup).
2. **Navigate** — Open the app URL, wait for `networkidle`
3. **Screenshot** — Save to `__webtest_recon.png`
4. **DOM dump** — Save rendered HTML to `__webtest_dom.html` (truncate at 50KB)
5. **Report** — Display screenshot, note page title, visible text count, form count

---

## Phase 2: Selector Discovery

Find interactive elements from the rendered DOM.

1. **Query all interactive elements:**
   - Buttons: `button`, `[role="button"]`, `input[type="submit"]`
   - Links: `a[href]`
   - Inputs: `input`, `textarea`, `select`
   - Custom: `[onclick]`, `[data-testid]`, `[aria-label]`
2. **For each element, record:**
   - Best selector (prefer `data-testid` > `aria-label` > `id` > CSS path)
   - Element type and visible text
   - Whether it's visible and enabled
3. **Output** — Print a numbered table of discoverable elements
4. **Save** — Write selector map to `__webtest_selectors.json`

---

## Phase 3: Interaction Testing

Click, type, and navigate — verify outcomes.

1. **For each key interactive element** (buttons, forms, navigation links):
   - Screenshot before interaction
   - Perform the interaction (click, type test data, submit)
   - Wait for response (networkidle or DOM change)
   - Screenshot after interaction
   - Verify: Did the page change? Any errors in console? HTTP failures?
2. **Form testing:**
   - Fill with valid test data, submit, verify success state
   - Fill with empty/invalid data, submit, verify error state
3. **Navigation testing:**
   - Click main nav links, verify each page loads
   - Check back button works
4. **Report** — List each interaction, result (pass/fail), and screenshots

---

## Phase 4: Visual Regression

Compare screenshots before and after code changes.

1. **Check for baseline screenshots** in `__webtest_baseline/`
2. **If no baseline exists:**
   - Save current screenshots as baseline
   - Report: "Baseline created. Run again after changes to compare."
3. **If baseline exists:**
   - Take new screenshots of same pages/states
   - Compare pixel-by-pixel (or perceptual hash if available)
   - Flag differences above threshold (>5% pixel diff)
   - Generate diff images highlighting changes
4. **Report** — List pages with visual changes, show diff screenshots

---

## Execution Flow

```
1. Detect running app (or start it)
2. Bootstrap Playwright if needed
3. Run selected phases (--recon, --selectors, --quick, or all)
4. Generate report with screenshots
5. Cleanup: delete __webtest_* artifacts
6. Stop server if we started it
```

---

## Test Script Naming

All artifacts use the `__webtest_` prefix:
- `__webtest_recon.png` — Reconnaissance screenshot
- `__webtest_dom.html` — DOM dump
- `__webtest_selectors.json` — Selector map
- `__webtest_interact_*.png` — Interaction screenshots
- `__webtest_baseline/` — Visual regression baselines
- `__webtest_diff_*.png` — Visual diff images
- `__webtest_script.py` (or `.js`) — Generated test script

---

## Rules

- **Localhost only** — Never navigate to external URLs
- **Headless only** — Always run Playwright in headless mode
- **Never commit artifacts** — All `__webtest_*` files are temporary
- **Cleanup on completion** — Delete all `__webtest_*` files and directories when done
- **Stop what you started** — If this skill started a dev server, stop it on completion
- **No production** — This is for local development testing only
- **Timeout** — Each phase has a 60-second timeout; abort and report on timeout
