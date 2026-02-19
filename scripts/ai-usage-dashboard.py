#!/usr/bin/env python3
"""
AI Usage & Impact Dashboard Generator

Collects token usage data from Claude Code (ccusage), Codex CLI (@ccusage/codex),
and Gemini CLI (OpenTelemetry logs), then generates an interactive HTML dashboard
showing usage trends, costs, and estimated environmental impact.

Usage:
    python3 ai-impact-dashboard.py [--since YYYYMMDD] [--until YYYYMMDD] [--no-open] [--output PATH]
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import webbrowser
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

# --- Energy / Carbon Model ---
ENERGY_PER_OUTPUT_TOKEN_WH = 0.001
ENERGY_PER_INPUT_TOKEN_WH = 0.0002
ENERGY_PER_CACHED_TOKEN_WH = 0.00005
PUE = 1.2                    # Power Usage Effectiveness (data center overhead)
EMBODIED_CARBON_FACTOR = 1.2  # +20% for hardware manufacturing
GRID_LOSS_FACTOR = 1.06       # 6% transmission losses
CARBON_INTENSITY = 390        # gCO2e per kWh (US average)
WATER_USE_EFFICIENCY = 0.5    # liters per kWh
ELECTRICITY_COST_KWH = 0.12  # USD per kWh (US average)


def run_command(cmd, timeout=60):
    """Run a shell command and return stdout, or None on failure."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def collect_claude_data(since=None, until=None):
    """Collect Claude Code usage via ccusage."""
    cmd = "ccusage daily --json"
    if since:
        cmd += f" --since {since}"
    if until:
        cmd += f" --until {until}"

    output = run_command(cmd, timeout=30)
    if not output:
        print("  [skip] ccusage not available or returned no data", file=sys.stderr)
        return {}

    try:
        raw = json.loads(output)
    except json.JSONDecodeError:
        print("  [skip] ccusage returned invalid JSON", file=sys.stderr)
        return {}

    # ccusage wraps data in {"daily": [...]}
    data = raw.get("daily", raw) if isinstance(raw, dict) else raw

    daily = {}
    for entry in data:
        date = entry.get("date", "")
        if not date:
            continue
        daily[date] = {
            "provider": "claude",
            "input_tokens": entry.get("inputTokens", 0) or 0,
            "output_tokens": entry.get("outputTokens", 0) or 0,
            "cache_read_tokens": entry.get("cacheReadTokens", 0) or 0,
            "cache_write_tokens": entry.get("cacheCreationTokens", 0) or 0,
            "cost": entry.get("totalCost", 0) or 0,
        }
    return daily


def _parse_date_flexible(date_str):
    """Parse dates in ISO (2026-01-07) or human (Jan 7, 2026) format to YYYY-MM-DD."""
    # Already ISO format
    if len(date_str) >= 10 and date_str[4] == '-':
        return date_str[:10]
    # Try human-readable formats
    for fmt in ("%b %d, %Y", "%B %d, %Y", "%b %d %Y"):
        try:
            return datetime.strptime(date_str, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def collect_codex_data(since=None, until=None):
    """Collect Codex CLI usage via @ccusage/codex."""
    cmd = "npx @ccusage/codex@latest daily --json"
    if since:
        cmd += f" --since {since}"
    if until:
        cmd += f" --until {until}"

    output = run_command(cmd, timeout=60)
    if not output:
        print("  [skip] @ccusage/codex not available or returned no data", file=sys.stderr)
        return {}

    try:
        raw = json.loads(output)
    except json.JSONDecodeError:
        print("  [skip] @ccusage/codex returned invalid JSON", file=sys.stderr)
        return {}

    # @ccusage/codex wraps data in {"daily": [...]}
    data = raw.get("daily", raw) if isinstance(raw, dict) else raw

    # First pass: collect all entries and compute blended rate from priced days
    entries = []
    priced_cost, priced_tokens = 0, 0
    for entry in data:
        raw_date = entry.get("date", "")
        if not raw_date:
            continue
        date = _parse_date_flexible(raw_date)
        if not date:
            continue
        input_tok = entry.get("inputTokens", 0) or 0
        output_tok = entry.get("outputTokens", 0) or 0
        cached_tok = entry.get("cachedInputTokens", 0) or 0
        cost = entry.get("costUSD", 0) or 0
        entries.append((date, input_tok, output_tok, cached_tok, cost))
        if cost > 0:
            priced_cost += cost
            priced_tokens += input_tok + output_tok

    # Blended $/token from priced days (gpt-5-codex), fallback for unpriced (gpt-5.3)
    blended_rate = (priced_cost / priced_tokens) if priced_tokens > 0 else 0.20e-6

    daily = {}
    for date, input_tok, output_tok, cached_tok, cost in entries:
        if not cost and (input_tok or output_tok):
            cost = (input_tok + output_tok) * blended_rate
        daily[date] = {
            "provider": "codex",
            "input_tokens": input_tok,
            "output_tokens": output_tok,
            "cache_read_tokens": cached_tok,
            "cache_write_tokens": 0,
            "cost": cost,
        }
    return daily


def collect_gemini_data(since=None, until=None):
    """Collect Gemini CLI usage from OpenTelemetry log."""
    log_path = Path.home() / ".gemini" / "telemetry.log"
    if not log_path.exists():
        print("  [skip] Gemini telemetry log not found (~/.gemini/telemetry.log)", file=sys.stderr)
        print("         Run scripts/setup-gemini-telemetry.sh to enable", file=sys.stderr)
        return {}

    daily = defaultdict(lambda: {
        "provider": "gemini",
        "input_tokens": 0, "output_tokens": 0,
        "cache_read_tokens": 0, "cache_write_tokens": 0,
        "cost": 0,
    })

    try:
        with open(log_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue

                # Extract timestamp for date grouping
                ts = record.get("timestamp") or record.get("time") or record.get("Timestamp") or ""
                if not ts:
                    continue
                try:
                    date = ts[:10]  # YYYY-MM-DD
                    datetime.strptime(date, "%Y-%m-%d")
                except (ValueError, IndexError):
                    continue

                # Apply date filters
                date_compact = date.replace("-", "")
                if since and date_compact < since:
                    continue
                if until and date_compact > until:
                    continue

                # Look for token usage in attributes or body
                attrs = record.get("attributes", record.get("Attributes", {}))
                if isinstance(attrs, list):
                    attrs_dict = {}
                    for a in attrs:
                        key = a.get("Key", a.get("key", ""))
                        val = a.get("Value", a.get("value", {}))
                        if isinstance(val, dict):
                            val = val.get("intValue", val.get("Int64Value", val.get("stringValue", 0)))
                        attrs_dict[key] = val
                    attrs = attrs_dict

                input_tok = _safe_int(attrs.get("input_token_count", attrs.get("gen_ai.usage.input_tokens", 0)))
                output_tok = _safe_int(attrs.get("output_token_count", attrs.get("gen_ai.usage.output_tokens", 0)))
                cached_tok = _safe_int(attrs.get("cached_content_token_count", attrs.get("gen_ai.usage.cached_tokens", 0)))

                if input_tok or output_tok:
                    daily[date]["input_tokens"] += input_tok
                    daily[date]["output_tokens"] += output_tok
                    daily[date]["cache_read_tokens"] += cached_tok
    except (OSError, PermissionError) as e:
        print(f"  [skip] Could not read Gemini telemetry log: {e}", file=sys.stderr)
        return {}

    # Estimate Gemini costs (Gemini 2.5 Pro pricing)
    for date, d in daily.items():
        input_cost = d["input_tokens"] * 1.25 / 1_000_000
        output_cost = d["output_tokens"] * 10.00 / 1_000_000
        cached_cost = d["cache_read_tokens"] * 0.315 / 1_000_000
        d["cost"] = input_cost + output_cost + cached_cost

    return dict(daily)


def _safe_int(val):
    """Convert a value to int safely."""
    try:
        return int(val)
    except (TypeError, ValueError):
        return 0


def calculate_energy(tokens_input, tokens_output, tokens_cached):
    """Calculate energy in Wh with PUE and grid losses."""
    base = (
        tokens_output * ENERGY_PER_OUTPUT_TOKEN_WH
        + tokens_input * ENERGY_PER_INPUT_TOKEN_WH
        + tokens_cached * ENERGY_PER_CACHED_TOKEN_WH
    )
    return base * PUE * GRID_LOSS_FACTOR


def calculate_carbon(energy_wh):
    """Calculate CO2 in grams from energy in Wh, including embodied carbon."""
    energy_kwh = energy_wh / 1000
    return energy_kwh * CARBON_INTENSITY * EMBODIED_CARBON_FACTOR


def calculate_water(energy_wh):
    """Calculate water usage in mL from energy in Wh."""
    energy_kwh = energy_wh / 1000
    return energy_kwh * WATER_USE_EFFICIENCY * 1000  # Convert L to mL


def merge_data(claude_data, codex_data, gemini_data):
    """Merge all provider data into a unified daily dataset."""
    all_dates = sorted(set(list(claude_data.keys()) + list(codex_data.keys()) + list(gemini_data.keys())))

    merged = []
    for date in all_dates:
        row = {"date": date, "claude": {}, "codex": {}, "gemini": {}}
        for provider, data in [("claude", claude_data), ("codex", codex_data), ("gemini", gemini_data)]:
            if date in data:
                d = data[date]
                energy = calculate_energy(d["input_tokens"], d["output_tokens"], d["cache_read_tokens"])
                carbon = calculate_carbon(energy)
                water = calculate_water(energy)
                row[provider] = {
                    "input_tokens": d["input_tokens"],
                    "output_tokens": d["output_tokens"],
                    "cache_read_tokens": d["cache_read_tokens"],
                    "cost": round(d["cost"], 4),
                    "energy_wh": round(energy, 4),
                    "carbon_g": round(carbon, 4),
                    "water_ml": round(water, 4),
                }
            else:
                row[provider] = {
                    "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
                    "cost": 0, "energy_wh": 0, "carbon_g": 0, "water_ml": 0,
                }
        merged.append(row)
    return merged


def generate_html(data, output_path):
    """Generate the self-contained HTML dashboard."""
    # Calculate totals
    totals = {
        "cost": 0, "energy_wh": 0, "carbon_g": 0, "water_ml": 0,
        "input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0,
    }
    for row in data:
        for provider in ["claude", "codex", "gemini"]:
            p = row[provider]
            totals["cost"] += p["cost"]
            totals["energy_wh"] += p["energy_wh"]
            totals["carbon_g"] += p["carbon_g"]
            totals["water_ml"] += p["water_ml"]
            totals["input_tokens"] += p["input_tokens"]
            totals["output_tokens"] += p["output_tokens"]
            totals["cache_read_tokens"] += p["cache_read_tokens"]

    electricity_cost = (totals["energy_wh"] / 1000) * ELECTRICITY_COST_KWH
    energy_pct_of_api = (electricity_cost / totals["cost"] * 100) if totals["cost"] > 0 else 0

    # Smart unit formatting
    def fmt_energy(wh):
        if wh >= 1_000_000:
            return f"{wh/1_000_000:,.2f} MWh"
        if wh >= 1000:
            return f"{wh/1000:,.2f} kWh"
        return f"{wh:,.1f} Wh"

    def fmt_carbon(g):
        if g >= 1_000_000:
            return f"{g/1_000_000:,.2f} tonnes"
        if g >= 1000:
            return f"{g/1000:,.2f} kg"
        return f"{g:,.1f} g"

    def fmt_water(ml):
        if ml >= 1_000_000:
            return f"{ml/1_000_000:,.2f} m\u00b3"
        if ml >= 1000:
            return f"{ml/1000:,.2f} L"
        return f"{ml:,.0f} mL"

    def fmt_cost(val):
        if val >= 1000:
            return f"${val:,.0f}"
        if val >= 1:
            return f"${val:,.2f}"
        return f"${val:,.4f}"

    def fmt_tokens(val):
        if val >= 1_000_000_000:
            return f"{val/1_000_000_000:,.2f} B"
        if val >= 1_000_000:
            return f"{val/1_000_000:,.2f} M"
        if val >= 1000:
            return f"{val/1000:,.2f} K"
        return f"{val:,.0f}"

    energy_display = fmt_energy(totals["energy_wh"])
    carbon_display = fmt_carbon(totals["carbon_g"])
    water_display = fmt_water(totals["water_ml"])

    # Equivalents
    carbon_kg = totals["carbon_g"] / 1000
    household_months = carbon_kg / 900
    car_miles = carbon_kg / 0.404
    flights_pct = carbon_kg / 90
    trees_needed = carbon_kg / 22
    showers = totals["water_ml"] / 65000
    iphone_charges = totals["energy_wh"] / 12.7

    # Real-world context for cards (pick best scale)
    energy_kwh = totals["energy_wh"] / 1000
    tesla_miles = energy_kwh / 0.25  # Tesla ~0.25 kWh/mile
    us_home_days = energy_kwh / 30  # US home ~30 kWh/day
    if us_home_days >= 1:
        energy_context = f"~{us_home_days:,.1f} days of avg US household electricity"
    elif tesla_miles >= 1:
        energy_context = f"~{tesla_miles:,.0f} miles in a Tesla"
    elif iphone_charges >= 1:
        energy_context = f"~{iphone_charges:,.0f} iPhone charges"
    else:
        energy_context = f"~{iphone_charges:,.2f} iPhone charges"
    carbon_context = f"~{car_miles:,.2f} miles driven"
    water_context = f"~{showers:,.2f} showers"

    # Build monthly cost matrix (months x providers), filling gaps
    monthly = defaultdict(lambda: {"claude": 0, "codex": 0, "gemini": 0})
    monthly_tokens = defaultdict(lambda: {
        p: {"input": 0, "output": 0, "cached": 0} for p in ["claude", "codex", "gemini"]
    })
    for row in data:
        month_key = row["date"][:7]  # YYYY-MM
        for provider in ["claude", "codex", "gemini"]:
            monthly[month_key][provider] += row[provider]["cost"]
            monthly_tokens[month_key][provider]["input"] += row[provider]["input_tokens"]
            monthly_tokens[month_key][provider]["output"] += row[provider]["output_tokens"]
            monthly_tokens[month_key][provider]["cached"] += row[provider]["cache_read_tokens"]

    # Fill in missing months between first and last
    if monthly:
        all_months = sorted(monthly.keys())
        start = datetime.strptime(all_months[0], "%Y-%m")
        end = datetime.strptime(all_months[-1], "%Y-%m")
        current = start
        while current <= end:
            key = current.strftime("%Y-%m")
            monthly.setdefault(key, {"claude": 0, "codex": 0, "gemini": 0})
            if current.month == 12:
                current = current.replace(year=current.year + 1, month=1)
            else:
                current = current.replace(month=current.month + 1)

    sorted_months = sorted(monthly.keys())
    col_totals = {"claude": 0, "codex": 0, "gemini": 0}
    col_tokens = {p: {"input": 0, "output": 0, "cached": 0} for p in ["claude", "codex", "gemini"]}
    matrix_rows_html = ""

    def _tip_html(t):
        """Generate CSS tooltip HTML for token breakdown."""
        return (
            f'<div class="tip">'
            f'<div class="tip-row"><span class="tip-label">Input</span><span class="tip-val">{t["input"]:,}</span></div>'
            f'<div class="tip-row"><span class="tip-label">Output</span><span class="tip-val">{t["output"]:,}</span></div>'
            f'<div class="tip-row"><span class="tip-label">Cached</span><span class="tip-val">{t["cached"]:,}</span></div>'
            f'</div>'
        )

    for month in sorted_months:
        m = monthly[month]
        mt = monthly_tokens[month]
        row_total = m["claude"] + m["codex"] + m["gemini"]
        for p in ["claude", "codex", "gemini"]:
            col_totals[p] += m[p]
            for k in ["input", "output", "cached"]:
                col_tokens[p][k] += mt[p][k]
        matrix_rows_html += (
            f'<tr><td class="month-label">{month}</td>'
            f'<td class="has-tip">${m["claude"]:,.2f}{_tip_html(mt["claude"])}</td>'
            f'<td class="has-tip">${m["codex"]:,.2f}{_tip_html(mt["codex"])}</td>'
            f'<td class="has-tip">${m["gemini"]:,.2f}{_tip_html(mt["gemini"])}</td>'
            f'<td class="row-total">${row_total:,.2f}</td></tr>\n'
        )
    grand_total = col_totals["claude"] + col_totals["codex"] + col_totals["gemini"]
    matrix_footer_html = (
        f'<tr class="col-totals"><td class="month-label">Total</td>'
        f'<td class="has-tip">${col_totals["claude"]:,.2f}{_tip_html(col_tokens["claude"])}</td>'
        f'<td class="has-tip">${col_totals["codex"]:,.2f}{_tip_html(col_tokens["codex"])}</td>'
        f'<td class="has-tip">${col_totals["gemini"]:,.2f}{_tip_html(col_tokens["gemini"])}</td>'
        f'<td class="row-total">${grand_total:,.2f}</td></tr>'
    )

    # Prepare chart data - pick best unit scale for energy and carbon
    dates_json = json.dumps([r["date"] for r in data])
    claude_cost = json.dumps([round(r["claude"]["cost"], 2) for r in data])
    codex_cost = json.dumps([round(r["codex"]["cost"], 2) for r in data])
    gemini_cost = json.dumps([round(r["gemini"]["cost"], 2) for r in data])

    # Determine best energy unit for charts
    max_daily_energy = max((r["claude"]["energy_wh"] + r["codex"]["energy_wh"] + r["gemini"]["energy_wh"]) for r in data) if data else 0
    if max_daily_energy >= 1_000_000:
        energy_divisor, energy_unit = 1_000_000, "MWh"
    elif max_daily_energy >= 500:
        energy_divisor, energy_unit = 1000, "kWh"
    else:
        energy_divisor, energy_unit = 1, "Wh"

    claude_energy = json.dumps([round(r["claude"]["energy_wh"] / energy_divisor, 4) for r in data])
    codex_energy = json.dumps([round(r["codex"]["energy_wh"] / energy_divisor, 4) for r in data])
    gemini_energy = json.dumps([round(r["gemini"]["energy_wh"] / energy_divisor, 4) for r in data])

    # Determine best carbon unit for charts
    daily_carbon_raw = [(r["claude"]["carbon_g"] + r["codex"]["carbon_g"] + r["gemini"]["carbon_g"]) for r in data]
    max_daily_carbon = max(daily_carbon_raw) if daily_carbon_raw else 0
    if max_daily_carbon >= 1_000_000:
        carbon_divisor, carbon_unit = 1_000_000, "tonnes"
    elif max_daily_carbon >= 500:
        carbon_divisor, carbon_unit = 1000, "kg"
    else:
        carbon_divisor, carbon_unit = 1, "g"

    daily_carbon = [round(c / carbon_divisor, 4) for c in daily_carbon_raw]
    carbon_colors = json.dumps(["#22c55e" if c < (5 / carbon_divisor) else "#f59e0b" if c < (20 / carbon_divisor) else "#ef4444" for c in daily_carbon])
    daily_carbon_json = json.dumps(daily_carbon)

    # Daily token use by provider (pick best unit)
    daily_tokens_raw = [(r["claude"]["input_tokens"] + r["claude"]["output_tokens"] + r["claude"]["cache_read_tokens"]
                       + r["codex"]["input_tokens"] + r["codex"]["output_tokens"] + r["codex"]["cache_read_tokens"]
                       + r["gemini"]["input_tokens"] + r["gemini"]["output_tokens"] + r["gemini"]["cache_read_tokens"]) for r in data]
    max_daily_tokens = max(daily_tokens_raw) if daily_tokens_raw else 0
    if max_daily_tokens >= 1_000_000_000:
        token_divisor, token_unit = 1_000_000_000, "B tokens"
    elif max_daily_tokens >= 1_000_000:
        token_divisor, token_unit = 1_000_000, "M tokens"
    elif max_daily_tokens >= 1000:
        token_divisor, token_unit = 1000, "K tokens"
    else:
        token_divisor, token_unit = 1, "tokens"

    def _provider_daily_tokens(r, p):
        return (r[p]["input_tokens"] + r[p]["output_tokens"] + r[p]["cache_read_tokens"]) / token_divisor

    claude_tokens = json.dumps([round(_provider_daily_tokens(r, "claude"), 2) for r in data])
    codex_tokens = json.dumps([round(_provider_daily_tokens(r, "codex"), 2) for r in data])
    gemini_tokens = json.dumps([round(_provider_daily_tokens(r, "gemini"), 2) for r in data])

    # Cumulative series (all by provider)
    cum_claude_cost, cum_codex_cost, cum_gemini_cost = [], [], []
    cum_claude_tok, cum_codex_tok, cum_gemini_tok = [], [], []
    cum_claude_energy, cum_codex_energy, cum_gemini_energy = [], [], []
    cum_claude_carbon, cum_codex_carbon, cum_gemini_carbon = [], [], []
    rcc, rcxc, rgmc = 0, 0, 0
    rct, rcx, rgm = 0, 0, 0
    rce, rcxe, rgme = 0, 0, 0
    rccarb, rcxcarb, rgmcarb = 0, 0, 0
    for row in data:
        rcc += row["claude"]["cost"]
        rcxc += row["codex"]["cost"]
        rgmc += row["gemini"]["cost"]
        rct += _provider_daily_tokens(row, "claude") * token_divisor
        rcx += _provider_daily_tokens(row, "codex") * token_divisor
        rgm += _provider_daily_tokens(row, "gemini") * token_divisor
        rce += row["claude"]["energy_wh"]
        rcxe += row["codex"]["energy_wh"]
        rgme += row["gemini"]["energy_wh"]
        rccarb += row["claude"]["carbon_g"]
        rcxcarb += row["codex"]["carbon_g"]
        rgmcarb += row["gemini"]["carbon_g"]
        cum_claude_cost.append(round(rcc, 2))
        cum_codex_cost.append(round(rcxc, 2))
        cum_gemini_cost.append(round(rgmc, 2))
        cum_claude_tok.append(round(rct / token_divisor, 2))
        cum_codex_tok.append(round(rcx / token_divisor, 2))
        cum_gemini_tok.append(round(rgm / token_divisor, 2))
        cum_claude_energy.append(round(rce / energy_divisor, 2))
        cum_codex_energy.append(round(rcxe / energy_divisor, 2))
        cum_gemini_energy.append(round(rgme / energy_divisor, 2))
        cum_claude_carbon.append(round(rccarb / carbon_divisor, 2))
        cum_codex_carbon.append(round(rcxcarb / carbon_divisor, 2))
        cum_gemini_carbon.append(round(rgmcarb / carbon_divisor, 2))
    cum_claude_cost_json = json.dumps(cum_claude_cost)
    cum_codex_cost_json = json.dumps(cum_codex_cost)
    cum_gemini_cost_json = json.dumps(cum_gemini_cost)
    cum_claude_tok_json = json.dumps(cum_claude_tok)
    cum_codex_tok_json = json.dumps(cum_codex_tok)
    cum_gemini_tok_json = json.dumps(cum_gemini_tok)
    cum_claude_energy_json = json.dumps(cum_claude_energy)
    cum_codex_energy_json = json.dumps(cum_codex_energy)
    cum_gemini_energy_json = json.dumps(cum_gemini_energy)
    cum_claude_carbon_json = json.dumps(cum_claude_carbon)
    cum_codex_carbon_json = json.dumps(cum_codex_carbon)
    cum_gemini_carbon_json = json.dumps(cum_gemini_carbon)

    # Date range for title
    date_range = ""
    if data:
        date_range = f"{data[0]['date']} to {data[-1]['date']}"

    # Token totals for display
    total_tokens = totals["input_tokens"] + totals["output_tokens"] + totals["cache_read_tokens"]

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AI Usage & Impact Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
  :root {{
    --bg: #0f172a; --surface: #1e293b; --border: #334155;
    --text: #f1f5f9; --muted: #94a3b8; --accent: #6366f1;
    --claude: #6366f1; --codex: #22c55e; --gemini: #f59e0b;
  }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: var(--bg); color: var(--text); padding: 2rem; }}
  h1 {{ font-size: 1.5rem; margin-bottom: 0.25rem; }}
  .subtitle {{ color: var(--muted); font-size: 0.875rem; margin-bottom: 1.5rem; }}
  .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
  .card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1.25rem; }}
  .card .label {{ color: var(--muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }}
  .card .value {{ font-size: 1.5rem; font-weight: 700; margin-top: 0.25rem; }}
  .card .detail {{ color: var(--muted); font-size: 0.75rem; margin-top: 0.25rem; }}
  .charts {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(500px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }}
  .chart-box {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1.25rem; }}
  .chart-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; }}
  .chart-header h3 {{ font-size: 0.875rem; color: var(--muted); margin: 0; }}
  .toggle-btn {{ background: var(--border); color: var(--muted); border: none; border-radius: 0.375rem; padding: 0.25rem 0.625rem; font-size: 0.7rem; cursor: pointer; transition: all 0.15s; }}
  .toggle-btn:hover {{ background: var(--accent); color: var(--text); }}
  .toggle-btn.active {{ background: var(--accent); color: var(--text); }}
  .equiv {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 1rem; }}
  .equiv-card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1rem; text-align: center; }}
  .equiv-card .num {{ font-size: 1.75rem; font-weight: 700; color: var(--accent); }}
  .equiv-card .desc {{ color: var(--muted); font-size: 0.75rem; margin-top: 0.25rem; }}
  .legend {{ display: flex; gap: 1.5rem; margin-bottom: 1.5rem; flex-wrap: wrap; }}
  .legend-item {{ display: flex; align-items: center; gap: 0.375rem; font-size: 0.8rem; color: var(--muted); }}
  .legend-dot {{ width: 10px; height: 10px; border-radius: 50%; }}
  .section-title {{ font-size: 1.1rem; margin: 2rem 0 1rem; color: var(--muted); }}
  .no-data {{ text-align: center; padding: 4rem 2rem; color: var(--muted); }}
  .token-summary {{ color: var(--muted); font-size: 0.8rem; margin-bottom: 1.5rem; }}
  .matrix-box {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1.25rem; margin-bottom: 2rem; overflow-x: auto; }}
  .matrix-box h3 {{ font-size: 0.875rem; color: var(--muted); margin-bottom: 1rem; }}
  .cost-matrix {{ width: 100%; border-collapse: collapse; font-size: 0.9rem; }}
  .cost-matrix th {{ color: var(--muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; padding: 0.5rem 1rem; text-align: right; border-bottom: 1px solid var(--border); }}
  .cost-matrix th:first-child {{ text-align: left; }}
  .cost-matrix td {{ padding: 0.5rem 1rem; text-align: right; border-bottom: 1px solid var(--border); font-variant-numeric: tabular-nums; }}
  .cost-matrix .month-label {{ text-align: left; color: var(--muted); font-weight: 500; }}
  .cost-matrix .row-total {{ font-weight: 700; }}
  .cost-matrix .col-totals td {{ border-top: 2px solid var(--accent); font-weight: 700; border-bottom: none; }}
  .cost-matrix .col-totals .month-label {{ color: var(--text); }}
  .cost-matrix th.claude {{ color: var(--claude); }}
  .cost-matrix th.codex {{ color: var(--codex); }}
  .cost-matrix th.gemini {{ color: var(--gemini); }}
  .cost-matrix td.has-tip {{ cursor: help; position: relative; }}
  .cost-matrix td.has-tip:hover .tip {{ display: block; }}
  .tip {{ display: none; position: absolute; bottom: 100%; left: 50%; transform: translateX(-50%); background: #0f172a; border: 1px solid var(--accent); border-radius: 0.5rem; padding: 0.5rem 0.75rem; font-size: 0.7rem; white-space: nowrap; z-index: 10; color: var(--text); pointer-events: none; margin-bottom: 4px; }}
  .tip .tip-row {{ display: flex; justify-content: space-between; gap: 1rem; }}
  .tip .tip-label {{ color: var(--muted); }}
  .tip .tip-val {{ font-variant-numeric: tabular-nums; text-align: right; }}
</style>
</head>
<body>
<h1>AI Usage & Impact Dashboard</h1>
<p class="subtitle">{date_range} ({len(data)} active days) &middot; Generated {datetime.now().strftime("%Y-%m-%d %H:%M")}</p>

<div class="legend">
  <div class="legend-item"><div class="legend-dot" style="background: var(--claude)"></div> Claude Code</div>
  <div class="legend-item"><div class="legend-dot" style="background: var(--codex)"></div> Codex CLI</div>
  <div class="legend-item"><div class="legend-dot" style="background: var(--gemini)"></div> Gemini CLI</div>
</div>

<p class="token-summary">{total_tokens:,} total tokens &middot; {totals['input_tokens']:,} input &middot; {totals['output_tokens']:,} output &middot; {totals['cache_read_tokens']:,} cached</p>

{"<div class='no-data'>No usage data found. Make sure ccusage is installed (npm i -g ccusage).</div>" if not data else f'''
<div class="cards">
  <div class="card">
    <div class="label">Total API Cost</div>
    <div class="value">{fmt_cost(totals["cost"])}</div>
    <div class="detail">{fmt_cost(totals["cost"] / len(data))}/active day avg</div>
  </div>
  <div class="card">
    <div class="label">Total Tokens</div>
    <div class="value">{fmt_tokens(total_tokens)}</div>
    <div class="detail">{fmt_tokens(total_tokens / len(data))}/day avg</div>
  </div>
  <div class="card">
    <div class="label">Input Tokens</div>
    <div class="value">{fmt_tokens(totals["input_tokens"])}</div>
    <div class="detail">{(totals["cache_read_tokens"] / totals["input_tokens"] * 100) if totals["input_tokens"] else 0:.0f}% cache hit rate ({fmt_tokens(totals["cache_read_tokens"])} cached)</div>
  </div>
  <div class="card">
    <div class="label">Output Tokens</div>
    <div class="value">{fmt_tokens(totals["output_tokens"])}</div>
    <div class="detail">{fmt_tokens(totals["output_tokens"] / len(data))}/day avg</div>
  </div>
</div>

<div class="matrix-box">
  <h3>Monthly Cost by Provider</h3>
  <table class="cost-matrix">
    <thead><tr><th></th><th class="claude">Claude</th><th class="codex">Codex</th><th class="gemini">Gemini</th><th>Total</th></tr></thead>
    <tbody>{matrix_rows_html}{matrix_footer_html}</tbody>
  </table>
</div>

<div class="charts">
  <div class="chart-box">
    <div class="chart-header">
      <h3 id="costTitle">Daily Cost by Provider ($)</h3>
      <button class="toggle-btn" onclick="toggleChart('cost')">Cumulative</button>
    </div>
    <canvas id="costChart"></canvas>
  </div>
  <div class="chart-box">
    <div class="chart-header">
      <h3 id="tokenTitle">Daily Token Use by Provider ({token_unit})</h3>
      <button class="toggle-btn" onclick="toggleChart('token')">Cumulative</button>
    </div>
    <canvas id="tokenChart"></canvas>
  </div>
</div>

<h3 class="section-title">Environmental Impact</h3>

<div class="cards">
  <div class="card">
    <div class="label">Energy Used</div>
    <div class="value">{energy_display}</div>
    <div class="detail">{energy_context}</div>
  </div>
  <div class="card">
    <div class="label">CO2 Emitted</div>
    <div class="value">{carbon_display}</div>
    <div class="detail">{carbon_context}</div>
  </div>
  <div class="card">
    <div class="label">Water Used</div>
    <div class="value">{water_display}</div>
    <div class="detail">{water_context}</div>
  </div>
  <div class="card">
    <div class="label">Electricity Cost</div>
    <div class="value">${electricity_cost:.2f}</div>
    <div class="detail">{energy_pct_of_api:.2f}% of API cost</div>
  </div>
</div>

<div class="charts">
  <div class="chart-box">
    <div class="chart-header">
      <h3 id="energyTitle">Daily Energy by Provider ({energy_unit})</h3>
      <button class="toggle-btn" onclick="toggleChart('energy')">Cumulative</button>
    </div>
    <canvas id="energyChart"></canvas>
  </div>
  <div class="chart-box">
    <div class="chart-header">
      <h3 id="carbonTitle">Daily CO2 Emissions ({carbon_unit})</h3>
      <button class="toggle-btn" onclick="toggleChart('carbon')">Cumulative</button>
    </div>
    <canvas id="carbonChart"></canvas>
  </div>
</div>

<h3 class="section-title">Real-World Equivalents</h3>
<div class="equiv">
  <div class="equiv-card"><div class="num">{household_months:,.2f}</div><div class="desc">Household-months of electricity</div></div>
  <div class="equiv-card"><div class="num">{car_miles:,.2f}</div><div class="desc">Miles in a gas car (25 mpg avg)</div></div>
  <div class="equiv-card"><div class="num">{flights_pct:,.2f}</div><div class="desc">NYC-LA flights</div></div>
  <div class="equiv-card"><div class="num">{trees_needed:,.2f}</div><div class="desc">Trees needed (1 year offset)</div></div>
  <div class="equiv-card"><div class="num">{showers:,.2f}</div><div class="desc">Showers (water)</div></div>
  <div class="equiv-card"><div class="num">{iphone_charges:,.2f}</div><div class="desc">iPhone charges</div></div>
</div>
'''}

<script>
const dates = {dates_json};
// Carbon equivalents for energy tooltip
const dailyCarbonG = {daily_carbon_json};
const carbonDivisor = {carbon_divisor};

const baseOpts = {{
  responsive: true,
  plugins: {{
    legend: {{
      display: true,
      labels: {{ color: '#94a3b8', boxWidth: 12, padding: 12, font: {{ size: 11 }} }}
    }}
  }},
  scales: {{
    x: {{ ticks: {{ color: '#94a3b8', maxRotation: 45 }}, grid: {{ color: '#1e293b' }} }},
    y: {{ ticks: {{ color: '#94a3b8' }}, grid: {{ color: '#334155' }} }}
  }}
}};
const stackOpts = JSON.parse(JSON.stringify(baseOpts));
stackOpts.scales.x.stacked = true;
stackOpts.scales.y.stacked = true;

// Energy chart gets a custom tooltip showing carbon equivalent
const energyOpts = JSON.parse(JSON.stringify(stackOpts));
energyOpts.plugins.tooltip = {{
  callbacks: {{
    afterBody: function(items) {{
      const idx = items[0].dataIndex;
      const cg = dailyCarbonG[idx];
      const miles = (cg / 1000 / 0.404).toFixed(3);
      return 'CO2: ' + (cg >= 1000 ? (cg/1000).toFixed(2) + ' kg' : cg.toFixed(1) + ' g') + ' (~' + miles + ' mi driven)';
    }}
  }}
}};

// Chart configs: daily (bar, stacked) and cumulative (line, by provider)
const chartConfigs = {{
  cost: {{
    canvas: 'costChart',
    titleEl: 'costTitle',
    dailyTitle: 'Daily Cost by Provider ($)',
    cumTitle: 'Cumulative Cost by Provider ($)',
    daily: {{ type: 'bar', datasets: [
      {{ label: 'Claude', data: {claude_cost}, backgroundColor: '#6366f1' }},
      {{ label: 'Codex', data: {codex_cost}, backgroundColor: '#22c55e' }},
      {{ label: 'Gemini', data: {gemini_cost}, backgroundColor: '#f59e0b' }},
    ], options: stackOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Claude', data: {cum_claude_cost_json}, borderColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Codex', data: {cum_codex_cost_json}, borderColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Gemini', data: {cum_gemini_cost_json}, borderColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0 }},
    ], options: baseOpts }},
  }},
  token: {{
    canvas: 'tokenChart',
    titleEl: 'tokenTitle',
    dailyTitle: 'Daily Token Use by Provider ({token_unit})',
    cumTitle: 'Cumulative Tokens by Provider ({token_unit})',
    daily: {{ type: 'bar', datasets: [
      {{ label: 'Claude', data: {claude_tokens}, backgroundColor: '#6366f1' }},
      {{ label: 'Codex', data: {codex_tokens}, backgroundColor: '#22c55e' }},
      {{ label: 'Gemini', data: {gemini_tokens}, backgroundColor: '#f59e0b' }},
    ], options: stackOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Claude', data: {cum_claude_tok_json}, borderColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Codex', data: {cum_codex_tok_json}, borderColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Gemini', data: {cum_gemini_tok_json}, borderColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0 }},
    ], options: baseOpts }},
  }},
  energy: {{
    canvas: 'energyChart',
    titleEl: 'energyTitle',
    dailyTitle: 'Daily Energy by Provider ({energy_unit})',
    cumTitle: 'Cumulative Energy ({energy_unit})',
    daily: {{ type: 'bar', datasets: [
      {{ label: 'Claude', data: {claude_energy}, backgroundColor: '#6366f1' }},
      {{ label: 'Codex', data: {codex_energy}, backgroundColor: '#22c55e' }},
      {{ label: 'Gemini', data: {gemini_energy}, backgroundColor: '#f59e0b' }},
    ], options: energyOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Claude', data: {cum_claude_energy_json}, borderColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Codex', data: {cum_codex_energy_json}, borderColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Gemini', data: {cum_gemini_energy_json}, borderColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0 }},
    ], options: baseOpts }},
  }},
  carbon: {{
    canvas: 'carbonChart',
    titleEl: 'carbonTitle',
    dailyTitle: 'Daily CO2 Emissions ({carbon_unit})',
    cumTitle: 'Cumulative CO2 ({carbon_unit})',
    daily: {{ type: 'bar', datasets: [
      {{ label: 'CO2', data: {daily_carbon_json}, backgroundColor: {carbon_colors} }},
    ], options: baseOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Claude', data: {cum_claude_carbon_json}, borderColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Codex', data: {cum_codex_carbon_json}, borderColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0 }},
      {{ label: 'Gemini', data: {cum_gemini_carbon_json}, borderColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0 }},
    ], options: baseOpts }},
  }},
}};

// Track chart instances and state
const charts = {{}};
const chartState = {{}};

// Initialize all charts in daily mode
Object.keys(chartConfigs).forEach(key => {{
  const cfg = chartConfigs[key];
  chartState[key] = 'daily';
  charts[key] = new Chart(document.getElementById(cfg.canvas), {{
    type: cfg.daily.type,
    data: {{ labels: dates, datasets: cfg.daily.datasets }},
    options: cfg.daily.options,
  }});
}});

function toggleChart(key) {{
  const cfg = chartConfigs[key];
  const isCum = chartState[key] === 'daily';
  chartState[key] = isCum ? 'cum' : 'daily';
  const mode = isCum ? cfg.cum : cfg.daily;

  // Destroy and recreate (type change requires this)
  charts[key].destroy();
  charts[key] = new Chart(document.getElementById(cfg.canvas), {{
    type: mode.type,
    data: {{ labels: dates, datasets: mode.datasets }},
    options: mode.options,
  }});

  // Update title and button
  document.getElementById(cfg.titleEl).textContent = isCum ? cfg.cumTitle : cfg.dailyTitle;
  const btn = document.getElementById(cfg.titleEl).parentElement.querySelector('.toggle-btn');
  btn.textContent = isCum ? 'Daily' : 'Cumulative';
  btn.classList.toggle('active', isCum);
}}
</script>
</body>
</html>"""

    with open(output_path, "w") as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description="Generate AI usage & impact dashboard")
    parser.add_argument("--since", help="Start date (YYYYMMDD)")
    parser.add_argument("--until", help="End date (YYYYMMDD)")
    parser.add_argument("--no-open", action="store_true", help="Don't open in browser")
    parser.add_argument("--output", help="Output HTML path")
    args = parser.parse_args()

    print("Collecting AI usage data...")

    print("  Claude Code (ccusage)...", file=sys.stderr)
    claude = collect_claude_data(args.since, args.until)
    print(f"    {len(claude)} days", file=sys.stderr)

    print("  Codex CLI (@ccusage/codex)...", file=sys.stderr)
    codex = collect_codex_data(args.since, args.until)
    print(f"    {len(codex)} days", file=sys.stderr)

    print("  Gemini CLI (telemetry)...", file=sys.stderr)
    gemini = collect_gemini_data(args.since, args.until)
    print(f"    {len(gemini)} days", file=sys.stderr)

    if not claude and not codex and not gemini:
        print("\nNo usage data found from any source.", file=sys.stderr)
        print("Make sure ccusage is installed: npm i -g ccusage", file=sys.stderr)
        sys.exit(1)

    merged = merge_data(claude, codex, gemini)
    print(f"\nMerged: {len(merged)} days of data", file=sys.stderr)

    output_path = args.output
    if not output_path:
        output_path = os.path.join(tempfile.gettempdir(), "ai-usage-dashboard.html")

    generate_html(merged, output_path)
    print(f"Dashboard written to: {output_path}")

    if not args.no_open:
        webbrowser.open(f"file://{os.path.abspath(output_path)}")
        print("Opened in browser.")


if __name__ == "__main__":
    main()
