---
name: ai-usage
description: "Track AI coding tool token usage, costs, and environmental impact"
---

**Created:** 2026-02-18-00-00
**Last Updated:** 2026-02-19-00-00

# AI Usage Tracker & Impact Dashboard

Track your token usage and costs across all your AI coding tools in one place. See daily and cumulative spending across Claude, Claude CLI, and Gemini CLI -- plus estimated environmental impact (energy, CO2, water) so you know the full cost of your AI-assisted development.

## Usage

```bash
/ai-usage                          # Full history, opens in browser
/ai-usage --since 20260201         # Filter from date
/ai-usage --until 20260215         # Filter to date
/ai-usage --since 20260201 --until 20260215  # Date range
/ai-usage --no-open                # Generate without opening browser
/ai-usage --output ~/Desktop/report.html     # Custom output path
```

## What This Does

1. Runs `tokenprint.py` from [TokenPrint](https://github.com/sburl/TokenPrint)
2. Collects token usage and costs from three sources:
   - **Claude** via `ccusage daily --json`
   - **Claude CLI** via `npx @ccusage/claude@latest daily --json`
   - **Gemini CLI** via OpenTelemetry logs at `~/.gemini/telemetry.log` (optional)
3. Merges into a unified daily view: tokens, costs, and per-provider breakdown
4. Estimates environmental impact (energy, CO2, water) from token volumes
5. Generates a self-contained HTML dashboard with Chart.js
6. Opens it in the default browser

## Prerequisites

| Dependency | Install | Required? |
|---|---|---|
| Python 3.9+ | Pre-installed on macOS | Yes |
| `ccusage` | `npm i -g ccusage` | Yes (for Claude data) |
| `@ccusage/claude` | Runs via `npx` (no install) | Yes (for Claude data) |
| [TokenPrint](https://github.com/sburl/TokenPrint) | Installed by bootstrap (or `git clone`) | Yes |
| Gemini CLI telemetry | `setup-gemini-telemetry.sh` (in TokenPrint) | No (optional) |

## Gemini CLI Setup (Optional)

Gemini CLI doesn't expose usage history directly. To track Gemini usage going forward:

```bash
# One-time setup - enables OpenTelemetry local logging
bash ~/.crosscheck/scripts/setup-gemini-telemetry.sh
```

This adds telemetry config to `~/.gemini/settings.json`. Future Gemini CLI sessions will log token usage to `~/.gemini/telemetry.log`. Historical Gemini data cannot be backfilled.

## Dashboard Contents

**Usage & Cost (primary):**
- **Summary cards:** total tokens, total cost, days tracked, per-provider breakdown
- **Daily cost chart:** stacked bars by provider (Claude / Claude / Gemini)
- **Cumulative cost chart:** line graph showing spend over time

**Environmental Impact (secondary):**
- **Energy card:** total Wh consumed, electricity cost, energy as % of API cost
- **Daily energy chart:** stacked bars by provider
- **Daily CO2 chart:** color-coded bars (green/amber/red thresholds)
- **Cumulative CO2 chart:** line graph
- **Water card:** estimated data center water usage
- **Equivalents grid:** household months, car miles, flights, trees needed, showers, iPhone charges

## Energy/Carbon Model

| Parameter | Value | Source |
|---|---|---|
| Output tokens | 0.001 Wh/token | Industry estimate |
| Input tokens | 0.0002 Wh/token | Industry estimate |
| Cached tokens | 0.00005 Wh/token | Industry estimate |
| PUE | 1.2 | Data center overhead |
| Embodied carbon | 20% | Hardware manufacturing |
| Grid loss | 6% | Transmission losses |
| Carbon intensity | 390 gCO2e/kWh | US average grid |
| Water usage | 0.5 L/kWh | Data center WUE |

## Execution

Find `tokenprint.py` from [TokenPrint](https://github.com/sburl/TokenPrint). Check these locations in order:

1. **Multi-project:** `TokenPrint/tokenprint.py` as a sibling of the CrossCheck directory (e.g., `~/Documents/Developer/TokenPrint/tokenprint.py`)
2. **Traditional:** `~/.tokenprint/tokenprint.py`

Run whichever is found first:

```bash
python3 <resolved-path> [OPTIONS]
```

Pass through any arguments the user provided (e.g., `--since`, `--until`, `--no-open`, `--output`).

If not found, tell the user: `git clone https://github.com/sburl/TokenPrint.git ~/.tokenprint`

If `ccusage` is not installed, inform the user and suggest `npm i -g ccusage`.

## Related Commands

- `/repo-assessment` - Comprehensive repo health check
- `/claude-delegate` - Delegate tasks to Claude
- `/gemini-delegate` - Delegate tasks to Gemini
