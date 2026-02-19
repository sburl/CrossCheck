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

    # First pass: collect all entries and derive per-token-type rates from priced days
    entries = []
    priced_input, priced_output, priced_cached, priced_cost = 0, 0, 0, 0
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
            non_cached = max(0, input_tok - cached_tok)
            priced_input += non_cached
            priced_output += output_tok
            priced_cached += cached_tok
            priced_cost += cost

    # Derive per-token-type rates from priced gpt-5-codex days.
    # Standard API pricing ratio: output ~4x input, cached ~0.25x input.
    # Solve: cost = non_cached_input * r + output * 4r + cached * 0.25r
    if priced_input + priced_output > 0:
        weighted = priced_input + priced_output * 4 + priced_cached * 0.25
        r = priced_cost / weighted if weighted > 0 else 0.05e-6
        rate_input = r
        rate_output = r * 4
        rate_cached = r * 0.25
    else:
        # Fallback if no priced days at all
        rate_input = 0.15e-6
        rate_output = 0.60e-6
        rate_cached = 0.0375e-6

    daily = {}
    for date, input_tok, output_tok, cached_tok, cost in entries:
        if not cost and (input_tok or output_tok):
            non_cached = max(0, input_tok - cached_tok)
            cost = non_cached * rate_input + output_tok * rate_output + cached_tok * rate_cached
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
            return f"{ml/1_000_000:,.2f} m³"
        if ml >= 1000:
            return f"{ml/1000:,.2f} L"
        return f"{ml:,.0f} mL"

    def fmt_cost(val):
        if val >= 1000:
            return f"${val:,.0f}"
        if val >= 0.01:
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

    def fmt_num(val):
        """Smart number format: drop decimals for large numbers."""
        if val >= 10:
            return f"{val:,.0f}"
        if val >= 1:
            return f"{val:,.1f}"
        return f"{val:,.2f}"

    energy_display = fmt_energy(totals["energy_wh"])
    carbon_display = fmt_carbon(totals["carbon_g"])
    water_display = fmt_water(totals["water_ml"])

    # Per-provider totals
    provider_carbon = {}
    provider_energy = {}
    provider_cost = {}
    for prov in ["claude", "codex", "gemini"]:
        provider_carbon[prov] = sum(r[prov]["carbon_g"] for r in data)
        provider_energy[prov] = sum(r[prov]["energy_wh"] for r in data)
        provider_cost[prov] = sum(r[prov]["cost"] for r in data)

    # Provider data presence (for default toggle state)
    provider_has_data = {p: any(r[p]["input_tokens"] + r[p]["output_tokens"] + r[p]["cache_read_tokens"] > 0 for r in data) for p in ["claude", "codex", "gemini"]}

    # Token composition & efficiency metrics
    total_input_all = totals["input_tokens"] + totals["cache_read_tokens"]
    cache_hit_rate = (totals["cache_read_tokens"] / total_input_all * 100) if total_input_all else 0
    _all_tokens = totals["input_tokens"] + totals["output_tokens"] + totals["cache_read_tokens"]
    output_pct = (totals["output_tokens"] / _all_tokens * 100) if _all_tokens else 0

    # Cost: per-M-token rate + provider percentages
    cost_per_m = (totals["cost"] / (_all_tokens / 1e6)) if _all_tokens else 0
    claude_pct = (provider_cost["claude"] / totals["cost"] * 100) if totals["cost"] else 0
    codex_pct = (provider_cost["codex"] / totals["cost"] * 100) if totals["cost"] else 0
    gemini_pct = (provider_cost["gemini"] / totals["cost"] * 100) if totals["cost"] else 0

    # Tokens: busiest day
    daily_totals = [(r["date"], r["claude"]["input_tokens"] + r["claude"]["output_tokens"] + r["claude"]["cache_read_tokens"]
                     + r["codex"]["input_tokens"] + r["codex"]["output_tokens"] + r["codex"]["cache_read_tokens"]
                     + r["gemini"]["input_tokens"] + r["gemini"]["output_tokens"] + r["gemini"]["cache_read_tokens"]) for r in data]
    busiest = max(daily_totals, key=lambda x: x[1])
    busiest_date = datetime.strptime(busiest[0], "%Y-%m-%d").strftime("%b %-d")
    busiest_tokens = busiest[1]

    # Input: estimated cache savings
    # If all cached tokens were charged at non-cached input rates instead
    # Use blended non-cached cost rate: total_cost / (non_cached_input + output) as proxy
    non_cache_tokens = totals["input_tokens"] + totals["output_tokens"]
    blended_rate = (totals["cost"] / non_cache_tokens) if non_cache_tokens else 0
    # Cached tokens are ~75% cheaper than non-cached; savings = cached * blended_rate * 0.75
    cache_savings = totals["cache_read_tokens"] * blended_rate * 0.75

    # Output: estimate actual output cost using known rates
    # Claude: $15/M output, $3/M input, $0.30/M cached
    # Codex: ~$2.76/M output, ~$0.69/M input, ~$0.17/M cached
    est_output_cost = 0
    est_total_cost = 0
    for prov in ["claude", "codex", "gemini"]:
        pt = {"claude": (3e-6, 15e-6, 0.30e-6), "codex": (0.69e-6, 2.76e-6, 0.17e-6), "gemini": (0.15e-6, 0.60e-6, 0.0375e-6)}
        ri, ro, rc = pt[prov]
        p_out = sum(r[prov]["output_tokens"] for r in data) * ro
        p_inp = sum(r[prov]["input_tokens"] for r in data) * ri
        p_cache = sum(r[prov]["cache_read_tokens"] for r in data) * rc
        est_output_cost += p_out
        est_total_cost += p_out + p_inp + p_cache
    output_cost_pct = (est_output_cost / est_total_cost * 100) if est_total_cost else 0
    cost_per_m_output = (est_output_cost / (totals["output_tokens"] / 1e6)) if totals["output_tokens"] else 0

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
        energy_context = f"~{fmt_num(us_home_days)} days of avg US household electricity"
    elif tesla_miles >= 1:
        energy_context = f"~{fmt_num(tesla_miles)} miles in a Tesla"
    else:
        energy_context = f"~{fmt_num(iphone_charges)} iPhone charges"
    carbon_context = f"~{fmt_num(car_miles)} miles driven"
    water_context = f"~{fmt_num(showers)} showers"

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
    daily_carbon_json = json.dumps(daily_carbon)
    claude_carbon = json.dumps([round(r["claude"]["carbon_g"] / carbon_divisor, 4) for r in data])
    codex_carbon = json.dumps([round(r["codex"]["carbon_g"] / carbon_divisor, 4) for r in data])
    gemini_carbon = json.dumps([round(r["gemini"]["carbon_g"] / carbon_divisor, 4) for r in data])

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
    # Total cumulative (sum of all providers per day)
    cum_total_cost_json = json.dumps([round(cum_claude_cost[i] + cum_codex_cost[i] + cum_gemini_cost[i], 2) for i in range(len(data))])
    cum_total_tok_json = json.dumps([round(cum_claude_tok[i] + cum_codex_tok[i] + cum_gemini_tok[i], 2) for i in range(len(data))])
    cum_total_energy_json = json.dumps([round(cum_claude_energy[i] + cum_codex_energy[i] + cum_gemini_energy[i], 2) for i in range(len(data))])
    cum_total_carbon_json = json.dumps([round(cum_claude_carbon[i] + cum_codex_carbon[i] + cum_gemini_carbon[i], 2) for i in range(len(data))])

    # Date range for title
    date_range = ""
    min_date = ""
    max_date = ""
    if data:
        date_range = f"{data[0]['date']} to {data[-1]['date']}"
        min_date = data[0]['date']
        max_date = data[-1]['date']

    # Token totals for display
    total_tokens = totals["input_tokens"] + totals["output_tokens"] + totals["cache_read_tokens"]

    # Raw data for client-side date filtering
    raw_data_json = json.dumps([{
        "d": r["date"],
        "c": [r["claude"]["input_tokens"], r["claude"]["output_tokens"],
              r["claude"]["cache_read_tokens"], round(r["claude"]["cost"], 4)],
        "x": [r["codex"]["input_tokens"], r["codex"]["output_tokens"],
              r["codex"]["cache_read_tokens"], round(r["codex"]["cost"], 4)],
        "g": [r["gemini"]["input_tokens"], r["gemini"]["output_tokens"],
              r["gemini"]["cache_read_tokens"], round(r["gemini"]["cost"], 4)],
    } for r in data])

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AI Usage & Impact</title>
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
  .subtitle {{ color: var(--muted); font-size: 0.875rem; margin-bottom: 0.25rem; }}
  .cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
  .card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1.25rem; }}
  .card .label {{ color: var(--muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; }}
  .card .value {{ font-size: 1.5rem; font-weight: 700; margin-top: 0.25rem; }}
  .card .detail {{ color: var(--muted); font-size: 0.75rem; margin-top: 0.25rem; }}
  .charts {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(500px, 1fr)); gap: 1.5rem; margin-bottom: 2rem; }}
  .chart-box {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1.25rem; }}
  .chart-header {{ display: flex; justify-content: space-between; align-items: center; margin-bottom: 1rem; }}
  .chart-header h3 {{ font-size: 0.875rem; color: var(--muted); margin: 0; }}
  .toggle-btn {{ background: var(--accent); color: var(--text); border: none; border-radius: 0.375rem; padding: 0.25rem 0.625rem; font-size: 0.7rem; cursor: pointer; transition: all 0.15s; opacity: 0.8; }}
  .toggle-btn:hover {{ opacity: 1; }}
  .equiv {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 1rem; }}
  .equiv-card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 0.75rem; padding: 1rem 1.25rem; display: flex; align-items: center; gap: 0.75rem; }}
  .equiv-card .emoji {{ font-size: 2rem; line-height: 1; flex-shrink: 0; }}
  .equiv-card .eq-content {{ flex: 1; }}
  .equiv-card .num {{ font-size: 1.5rem; font-weight: 700; color: var(--accent); }}
  .equiv-card .desc {{ color: var(--muted); font-size: 0.75rem; margin-top: 0.125rem; }}
  .legend {{ display: flex; gap: 1.5rem; margin-bottom: 1.5rem; flex-wrap: wrap; }}
  .legend-item {{ display: flex; align-items: center; gap: 0.375rem; font-size: 0.8rem; color: var(--text); cursor: pointer; user-select: none; transition: opacity 0.15s; }}
  .legend-item.off {{ opacity: 0.35; }}
  .legend-item.off .legend-dot {{ background: var(--muted) !important; }}
  .legend-dot {{ width: 10px; height: 10px; border-radius: 50%; }}
  .section-title {{ font-size: 1.1rem; margin: 2rem 0 1rem; color: var(--muted); }}
  .no-data {{ text-align: center; padding: 4rem 2rem; color: var(--muted); }}
  .token-summary {{ color: var(--muted); font-size: 0.8rem; margin-bottom: 0.75rem; }}
  .date-range {{ display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1.25rem; flex-wrap: wrap; }}
  .date-range label {{ color: var(--muted); font-size: 0.8rem; }}
  .date-range input[type="date"] {{ background: var(--surface); border: 1px solid var(--border); color: var(--text); border-radius: 0.375rem; padding: 0.375rem 0.5rem; font-size: 0.8rem; font-family: inherit; color-scheme: dark; }}
  .date-range input[type="date"]::-webkit-calendar-picker-indicator {{ filter: invert(0.8); opacity: 0.6; }}
  .date-range input[type="date"]::-webkit-calendar-picker-indicator:hover {{ opacity: 1; }}
  .date-range button {{ background: var(--border); color: var(--muted); border: none; border-radius: 0.375rem; padding: 0.375rem 0.75rem; font-size: 0.75rem; cursor: pointer; transition: all 0.15s; }}
  .date-range button:hover {{ background: var(--accent); color: var(--text); }}
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
  .assumptions {{ margin-top: 2rem; color: var(--muted); font-size: 0.8rem; }}
  .assumptions summary {{ cursor: pointer; color: var(--text); font-size: 0.9rem; padding: 0.75rem 0; }}
  .assumptions summary:hover {{ color: var(--accent); }}
  .assumptions-body {{ padding: 1rem 0; }}
  .assumptions-body h4 {{ color: var(--text); margin: 1rem 0 0.5rem; font-size: 0.85rem; }}
  .assumptions-body ul {{ padding-left: 1.25rem; }}
  .assumptions-body li {{ margin-bottom: 0.25rem; }}
  .assumptions-body table {{ width: 100%; border-collapse: collapse; margin: 0.5rem 0; table-layout: fixed; }}
  .assumptions-body td {{ padding: 0.375rem 0.75rem; border-bottom: 1px solid var(--border); font-size: 0.8rem; vertical-align: top; }}
  .assumptions-body td:first-child {{ color: var(--text); width: 35%; }}
  .assumptions-body td:nth-child(2) {{ width: 22%; font-variant-numeric: tabular-nums; }}
  .assumptions-body td:nth-child(3) {{ color: var(--muted); font-style: italic; width: 43%; }}
  .assumptions-body code {{ background: var(--surface); padding: 0.1rem 0.3rem; border-radius: 0.25rem; }}
</style>
</head>
<body>
<h1><span style="font-size: 1.1em; filter: grayscale(1) brightness(10);">⚡</span> AI Usage & Impact</h1>
<p class="subtitle"><span id="dateRange">{date_range} ({len(data)} active days)</span> &middot; <span id="genTime">Last updated {datetime.now().strftime("%Y-%m-%d %H:%M")}</span> &middot; <button id="updateBtn" style="background:var(--accent);color:var(--text);border:none;border-radius:0.375rem;padding:0.15rem 0.5rem;font-size:0.75rem;cursor:pointer;opacity:0.8;" onmouseover="this.style.opacity='1'" onmouseout="this.style.opacity='0.8'">Update</button></p>
<p class="token-summary" id="tokenSummary">{total_tokens:,} total tokens &middot; {totals['input_tokens']:,} input &middot; {totals['output_tokens']:,} output &middot; {totals['cache_read_tokens']:,} cached</p>

<div class="date-range">
  <label>Range:</label>
  <input type="date" id="startDate" value="{min_date}" min="{min_date}" max="{max_date}">
  <span style="color: var(--muted); font-size: 0.8rem;">to</span>
  <input type="date" id="endDate" value="{max_date}" min="{min_date}" max="{max_date}">
  <button onclick="resetDates()">Reset</button>
</div>

<div class="legend">
  <div class="legend-item{'' if provider_has_data.get('claude') else ' off'}" data-provider="claude" onclick="toggleProvider(this)"><div class="legend-dot" style="background: var(--claude)"></div> Claude Code</div>
  <div class="legend-item{'' if provider_has_data.get('codex') else ' off'}" data-provider="codex" onclick="toggleProvider(this)"><div class="legend-dot" style="background: var(--codex)"></div> Codex CLI</div>
  <div class="legend-item{'' if provider_has_data.get('gemini') else ' off'}" data-provider="gemini" onclick="toggleProvider(this)"><div class="legend-dot" style="background: var(--gemini)"></div> Gemini CLI</div>
</div>

{"<div class='no-data'>No usage data found. Make sure ccusage is installed (npm i -g ccusage).</div>" if not data else f'''
<div class="cards">
  <div class="card">
    <div class="label">Total API Cost</div>
    <div class="value" id="cardCostVal">{fmt_cost(totals["cost"])}</div>
    <div class="detail" id="cardCostDetail">{fmt_cost(cost_per_m)}/M tokens &middot; {" &middot; ".join(f"{p.title()} {(provider_cost[p] / totals['cost'] * 100 if totals['cost'] else 0):.0f}%" for p in ["claude", "codex", "gemini"] if provider_has_data.get(p))}</div>
  </div>
  <div class="card">
    <div class="label">Total Tokens</div>
    <div class="value" id="cardTokensVal">{fmt_tokens(total_tokens)}</div>
    <div class="detail" id="cardTokensDetail">{fmt_tokens(total_tokens / len(data))}/day avg &middot; busiest: {fmt_tokens(busiest_tokens)} ({busiest_date})</div>
  </div>
  <div class="card">
    <div class="label">Input Tokens</div>
    <div class="value" id="cardInputVal">{fmt_tokens(totals["input_tokens"])}</div>
    <div class="detail" id="cardInputDetail">{cache_hit_rate:.0f}% cache hit rate &middot; ~{fmt_cost(cache_savings)} saved vs uncached</div>
  </div>
  <div class="card">
    <div class="label">Output Tokens</div>
    <div class="value" id="cardOutputVal">{fmt_tokens(totals["output_tokens"])}</div>
    <div class="detail" id="cardOutputDetail">{fmt_cost(cost_per_m_output)}/M output tokens &middot; drives ~{output_cost_pct:.0f}% of total cost</div>
  </div>
</div>

<div class="matrix-box">
  <h3>Monthly Estimated API Cost by Provider</h3>
  <table class="cost-matrix">
    <thead id="matrixHead"><tr><th></th><th class="claude">Claude</th><th class="codex">Codex</th><th class="gemini">Gemini</th><th>Total</th></tr></thead>
    <tbody id="matrixBody">{matrix_rows_html}{matrix_footer_html}</tbody>
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
    <div class="value" id="cardEnergyVal">{energy_display}</div>
    <div class="detail" id="cardEnergyDetail">{energy_context} · Claude {fmt_energy(provider_energy["claude"])} · Codex {fmt_energy(provider_energy["codex"])}</div>
  </div>
  <div class="card">
    <div class="label">CO2 Emitted</div>
    <div class="value" id="cardCarbonVal">{carbon_display}</div>
    <div class="detail" id="cardCarbonDetail">Claude {fmt_carbon(provider_carbon["claude"])} · Codex {fmt_carbon(provider_carbon["codex"])} · Gemini {fmt_carbon(provider_carbon["gemini"])}</div>
  </div>
  <div class="card">
    <div class="label">Water Used</div>
    <div class="value" id="cardWaterVal">{water_display}</div>
    <div class="detail" id="cardWaterDetail">{water_context}</div>
  </div>
  <div class="card">
    <div class="label">Electricity Cost</div>
    <div class="value" id="cardElecVal">${electricity_cost:.2f}</div>
    <div class="detail" id="cardElecDetail">{energy_pct_of_api:.2f}% of API cost</div>
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
  <div class="equiv-card"><div class="emoji">🏠</div><div class="eq-content"><div class="num" id="eqHousehold">{fmt_num(household_months)}</div><div class="desc">Household-months of electricity</div></div></div>
  <div class="equiv-card"><div class="emoji">🚗</div><div class="eq-content"><div class="num" id="eqCar">{fmt_num(car_miles)}</div><div class="desc">Miles in a gas car (25 mpg avg)</div></div></div>
  <div class="equiv-card"><div class="emoji">✈️</div><div class="eq-content"><div class="num" id="eqFlights">{fmt_num(flights_pct)}</div><div class="desc">NYC-LA flights</div></div></div>
  <div class="equiv-card"><div class="emoji">🌳</div><div class="eq-content"><div class="num" id="eqTrees">{fmt_num(trees_needed)}</div><div class="desc">Trees needed (1 year offset)</div></div></div>
  <div class="equiv-card"><div class="emoji">🚿</div><div class="eq-content"><div class="num" id="eqShowers">{fmt_num(showers)}</div><div class="desc">Showers (water)</div></div></div>
  <div class="equiv-card"><div class="emoji">📱</div><div class="eq-content"><div class="num" id="eqIphone">{fmt_num(iphone_charges)}</div><div class="desc">iPhone charges</div></div></div>
</div>

<details class="assumptions">
<summary>📋 Methodology & Assumptions</summary>
<div class="assumptions-body">
<h4>Data Sources</h4>
<ul>
<li><strong>Claude Code:</strong> <code>ccusage daily --json</code> — reads local JSONL logs from Claude Code sessions</li>
<li><strong>Codex CLI:</strong> <code>npx @ccusage/codex@latest daily --json</code> — reads local Codex CLI session logs</li>
<li><strong>Gemini CLI:</strong> OpenTelemetry file export at <code>~/.gemini/telemetry.log</code> (requires one-time setup). Only tracks sessions after telemetry is enabled.</li>
</ul>

<h4>Cost Estimates</h4>
<ul>
<li><strong>Claude:</strong> Cost from ccusage (uses Anthropic's published API pricing per model)</li>
<li><strong>Codex (gpt-5-codex):</strong> Cost from ccusage (uses OpenAI's published pricing)</li>
<li><strong>Codex (gpt-5.3-codex):</strong> No official API pricing yet. Estimated using per-token-type rates (input, output, cached) derived from gpt-5-codex priced days with standard 4:1 output:input ratio</li>
<li><strong>Gemini:</strong> Estimated at $1.25/M input, $10.00/M output, $0.315/M cached (Gemini 2.5 Pro pricing)</li>
</ul>

<h4>Energy Model</h4>
<table>
<tr><td>Output tokens</td><td>0.001 Wh/token</td><td>Industry estimate for large language models</td></tr>
<tr><td>Input tokens</td><td>0.0002 Wh/token</td><td>~5x less compute than output</td></tr>
<tr><td>Cached tokens</td><td>0.00005 Wh/token</td><td>~4x less than input (cache lookup)</td></tr>
<tr><td>PUE (Power Usage Effectiveness)</td><td>1.2</td><td>Typical hyperscale data center overhead (cooling, networking)</td></tr>
<tr><td>Grid transmission loss</td><td>6%</td><td>US average grid losses from plant to data center</td></tr>
<tr><td>Electricity price</td><td>$0.12/kWh</td><td>US average commercial rate</td></tr>
</table>

<h4>Carbon Model</h4>
<table>
<tr><td>Grid carbon intensity</td><td>390 gCO2e/kWh</td><td>US average grid mix (EIA)</td></tr>
<tr><td>Embodied carbon</td><td>+20%</td><td>Hardware manufacturing, shipping, end-of-life</td></tr>
</table>

<h4>Water Model</h4>
<table>
<tr><td>Water Usage Effectiveness (WUE)</td><td>0.5 L/kWh</td><td>Typical evaporative cooling in data centers</td></tr>
</table>

<h4>Real-World Equivalents</h4>
<table>
<tr><td>US household electricity</td><td>~900 kg CO2/month</td><td>EPA average</td></tr>
<tr><td>Gas car emissions</td><td>404 g CO2/mile</td><td>EPA average (25 mpg)</td></tr>
<tr><td>NYC-LA flight</td><td>~90 kg CO2/passenger</td><td>Economy class, one way</td></tr>
<tr><td>Tree offset</td><td>~22 kg CO2/year</td><td>Mature tree annual absorption</td></tr>
<tr><td>Shower</td><td>~65 L water</td><td>8-minute average shower</td></tr>
<tr><td>iPhone charge</td><td>~12.7 Wh</td><td>iPhone 15 battery capacity</td></tr>
<tr><td>Tesla</td><td>~0.25 kWh/mile</td><td>Model 3 average efficiency</td></tr>
<tr><td>US household electricity</td><td>~30 kWh/day</td><td>EIA average</td></tr>
</table>

<h4>Limitations</h4>
<ul>
<li>Energy per token is a rough industry estimate — actual consumption varies by model, hardware, and data center</li>
<li>Carbon intensity varies significantly by region and time of day (renewables vs fossil)</li>
<li>Codex gpt-5.3 pricing is estimated and will update when official pricing is available</li>
<li>Gemini data only available from the point telemetry is enabled (no historical backfill)</li>
<li>"Active days" counts only days with recorded usage, not calendar days</li>
</ul>
</div>
</details>
'''}

<script>
const dates = {dates_json};
// Carbon equivalents for energy tooltip
const dailyCarbonG = {daily_carbon_json};
const carbonDivisor = {carbon_divisor};

// Smart token formatter: auto-scale to best unit
const TOKEN_DIV = {token_divisor};
function fmtTok(val) {{
  const abs = Math.abs(val) * TOKEN_DIV;
  if (abs >= 1e9) return (abs/1e9).toFixed(2) + ' B tokens';
  if (abs >= 1e6) return (abs/1e6).toFixed(2) + ' M tokens';
  if (abs >= 1e3) return (abs/1e3).toFixed(2) + ' K tokens';
  return abs.toFixed(0) + ' tokens';
}}

const baseOpts = {{
  responsive: true,
  plugins: {{
    legend: {{
      display: true,
      labels: {{ color: '#94a3b8', boxWidth: 12, padding: 12, font: {{ size: 11 }}, usePointStyle: true, pointStyle: 'circle' }}
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

// Helper: build daily tooltip with unit + optional extra line
function dailyTooltipOpts(unit, extraFn) {{
  const opts = JSON.parse(JSON.stringify(stackOpts));
  opts.plugins.tooltip = {{
    usePointStyle: true,
    callbacks: {{
      label: function(ctx) {{
        return ' ' + ctx.dataset.label + ': ' + unit + ctx.formattedValue;
      }},
      footer: function(items) {{
        const total = items.reduce((s,i) => s + (i.raw||0), 0);
        let lines = ['Total: ' + unit + fFix(total,2)];
        if (extraFn) lines.push(extraFn(items));
        return lines;
      }}
    }}
  }};
  return opts;
}}

// Daily cost: $ prefix
const costDailyOpts = dailyTooltipOpts('$', null);

// Daily energy: unit suffix + electricity cost context
const energyOpts = dailyTooltipOpts('', function(items) {{
  let totalWh = 0;
  items.forEach(i => totalWh += (i.raw || 0) * {energy_divisor});
  const kwh = totalWh / 1000;
  return 'Electricity: $' + fFix(kwh * {ELECTRICITY_COST_KWH},2) + ' (~' + fFix(kwh / 1.25,1) + ' hrs household use)';
}});
// Patch energy label to show unit suffix instead of prefix
energyOpts.plugins.tooltip.callbacks.label = function(ctx) {{
  return ' ' + ctx.dataset.label + ': ' + ctx.formattedValue + ' {energy_unit}';
}};
energyOpts.plugins.tooltip.callbacks.footer = function(items) {{
  const total = items.reduce((s,i) => s + (i.raw||0), 0);
  let totalWh = total * {energy_divisor};
  const kwh = totalWh / 1000;
  return ['Total: ' + fFix(total,2) + ' {energy_unit}', 'Electricity: $' + fFix(kwh * {ELECTRICITY_COST_KWH},2) + ' (~' + fFix(kwh / 1.25,1) + ' hrs household use)'];
}};

// Daily carbon: unit suffix + miles context
const carbonOpts = JSON.parse(JSON.stringify(stackOpts));
carbonOpts.plugins.tooltip = {{
  usePointStyle: true,
  callbacks: {{
    label: function(ctx) {{
      return ' ' + ctx.dataset.label + ': ' + ctx.formattedValue + ' {carbon_unit}';
    }},
    footer: function(items) {{
      const idx = items[0].dataIndex;
      const cg = dailyCarbonG[idx];
      const total = items.reduce((s,i) => s + (i.raw||0), 0);
      return ['Total: ' + fFix(total,4) + ' {carbon_unit}', '~' + fFix(cg / 1000 / 0.404,3) + ' mi in a gas car (25 mpg)'];
    }}
  }}
}};

// Daily token: smart auto-scaling units
const tokenDailyOpts = JSON.parse(JSON.stringify(stackOpts));
tokenDailyOpts.plugins.tooltip = {{
  usePointStyle: true,
  callbacks: {{
    label: function(ctx) {{
      return ' ' + ctx.dataset.label + ': ' + fmtTok(ctx.raw||0);
    }},
    footer: function(items) {{
      const total = items.reduce((s,i) => s + (i.raw||0), 0);
      return 'Total: ' + fmtTok(total);
    }}
  }}
}};

// Cumulative options: circles in legend, index hover, date range + daily avg
function cumTooltipOpts(unit, unitSuffix, extraFn) {{
  const opts = JSON.parse(JSON.stringify(baseOpts));
  opts.plugins.legend.labels.usePointStyle = true;
  opts.plugins.legend.labels.pointStyle = 'circle';
  opts.interaction = {{ mode: 'index', intersect: false }};
  const pre = unitSuffix ? '' : unit;
  const suf = unitSuffix ? ' ' + unit : '';
  opts.plugins.tooltip = {{
    mode: 'index', intersect: false, usePointStyle: true,
    callbacks: {{
      label: function(ctx) {{
        return ' ' + ctx.dataset.label + ': ' + pre + ctx.formattedValue + suf;
      }},
      afterBody: function(items) {{
        const idx = items[0].dataIndex;
        const total = items.reduce((s,i) => s + (i.raw||0), 0);
        const days = idx + 1;
        const avg = total / days;
        let lines = ['', 'Total: ' + pre + fFix(total,2) + suf,
                     'Daily avg: ' + pre + fFix(avg,2) + suf + ' over ' + days + ' days'];
        if (extraFn) lines.push(extraFn(items, total, idx));
        return lines;
      }}
    }}
  }};
  return opts;
}}

const cumCostOpts = cumTooltipOpts('$', false, null);
// Cumulative tokens: custom smart formatting
const cumTokenOpts = (function() {{
  const o = JSON.parse(JSON.stringify(baseOpts));
  o.plugins.legend.labels.usePointStyle = true;
  o.plugins.legend.labels.pointStyle = 'circle';
  o.interaction = {{mode:'index',intersect:false}};
  o.plugins.tooltip = {{mode:'index',intersect:false, usePointStyle:true, callbacks: {{
    label: function(ctx) {{ return ' '+ctx.dataset.label+': '+fmtTok(ctx.raw||0); }},
    afterBody: function(items) {{
      const idx = items[0].dataIndex;
      const total = items.reduce((s,i)=>s+(i.raw||0),0);
      const days = idx+1, avg = total/days;
      return ['','Total: '+fmtTok(total),'Daily avg: '+fmtTok(avg)+' over '+days+' days'];
    }}
  }}}};
  return o;
}})();
const cumEnergyOpts = cumTooltipOpts('{energy_unit}', true, function(items, total, idx) {{
  const totalWh = total * {energy_divisor};
  const kwh = totalWh / 1000;
  return 'Electricity: $' + fFix(kwh * {ELECTRICITY_COST_KWH},2) + ' (~' + fFix(kwh / 30,1) + ' days household use)';
}});
const cumCarbonOpts = cumTooltipOpts('{carbon_unit}', true, function(items, total, idx) {{
  const totalG = total * {carbon_divisor};
  return '~' + fFix(totalG / 1000 / 0.404,2) + ' mi in a gas car (25 mpg)';
}});

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
    ], options: costDailyOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Total', data: {cum_total_cost_json}, borderColor: '#e2e8f0', backgroundColor: '#e2e8f0', borderDash: [5,3], borderWidth: 2, fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Claude', data: {cum_claude_cost_json}, borderColor: '#6366f1', backgroundColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Codex', data: {cum_codex_cost_json}, borderColor: '#22c55e', backgroundColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Gemini', data: {cum_gemini_cost_json}, borderColor: '#f59e0b', backgroundColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
    ], options: cumCostOpts }},
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
    ], options: tokenDailyOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Total', data: {cum_total_tok_json}, borderColor: '#e2e8f0', backgroundColor: '#e2e8f0', borderDash: [5,3], borderWidth: 2, fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Claude', data: {cum_claude_tok_json}, borderColor: '#6366f1', backgroundColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Codex', data: {cum_codex_tok_json}, borderColor: '#22c55e', backgroundColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Gemini', data: {cum_gemini_tok_json}, borderColor: '#f59e0b', backgroundColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
    ], options: cumTokenOpts }},
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
      {{ label: 'Total', data: {cum_total_energy_json}, borderColor: '#e2e8f0', backgroundColor: '#e2e8f0', borderDash: [5,3], borderWidth: 2, fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Claude', data: {cum_claude_energy_json}, borderColor: '#6366f1', backgroundColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Codex', data: {cum_codex_energy_json}, borderColor: '#22c55e', backgroundColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Gemini', data: {cum_gemini_energy_json}, borderColor: '#f59e0b', backgroundColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
    ], options: cumEnergyOpts }},
  }},
  carbon: {{
    canvas: 'carbonChart',
    titleEl: 'carbonTitle',
    dailyTitle: 'Daily CO2 Emissions ({carbon_unit})',
    cumTitle: 'Cumulative CO2 ({carbon_unit})',
    daily: {{ type: 'bar', datasets: [
      {{ label: 'Claude', data: {claude_carbon}, backgroundColor: '#6366f1' }},
      {{ label: 'Codex', data: {codex_carbon}, backgroundColor: '#22c55e' }},
      {{ label: 'Gemini', data: {gemini_carbon}, backgroundColor: '#f59e0b' }},
    ], options: carbonOpts }},
    cum: {{ type: 'line', datasets: [
      {{ label: 'Total', data: {cum_total_carbon_json}, borderColor: '#e2e8f0', backgroundColor: '#e2e8f0', borderDash: [5,3], borderWidth: 2, fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Claude', data: {cum_claude_carbon_json}, borderColor: '#6366f1', backgroundColor: '#6366f1', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Codex', data: {cum_codex_carbon_json}, borderColor: '#22c55e', backgroundColor: '#22c55e', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
      {{ label: 'Gemini', data: {cum_gemini_carbon_json}, borderColor: '#f59e0b', backgroundColor: '#f59e0b', fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }},
    ], options: cumCarbonOpts }},
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
  // Button always same style; just swap label
}}

// --- Date range filtering ---
const RAW = {raw_data_json};
const PROVS = ['claude', 'codex', 'gemini'];
const PKEYS = ['c', 'x', 'g'];
const PCOLORS = ['#6366f1', '#22c55e', '#f59e0b'];
const PNAMES = ['Claude', 'Codex', 'Gemini'];
const EN = {{OUT: 0.001, IN: 0.0002, CACHE: 0.00005, PUE: 1.2, GRID: 1.06}};
const CN = {{INT: 390, EMB: 1.2, WUE: 0.5, ELEC: {ELECTRICITY_COST_KWH}}};

// Provider toggle
function toggleProvider(el) {{
  el.classList.toggle('off');
  updateDashboard();
}}
function enabledProviders() {{
  const items = document.querySelectorAll('.legend-item');
  const on = [];
  items.forEach(el => {{ if (!el.classList.contains('off')) on.push(el.dataset.provider); }});
  return on;
}}

function cE(i,o,c) {{ return (o*EN.OUT + i*EN.IN + c*EN.CACHE) * EN.PUE * EN.GRID; }}
function cC(wh) {{ return (wh/1000) * CN.INT * CN.EMB; }}
function cW(wh) {{ return (wh/1000) * CN.WUE * 1000; }}
function fC(v) {{ return v >= 1000 ? '$'+v.toLocaleString('en',{{maximumFractionDigits:0}}) : v >= 1 ? '$'+v.toFixed(2) : '$'+v.toFixed(4); }}
function fT(v) {{ return v >= 1e9 ? (v/1e9).toFixed(2)+' B' : v >= 1e6 ? (v/1e6).toFixed(2)+' M' : v >= 1e3 ? (v/1e3).toFixed(2)+' K' : v.toLocaleString('en'); }}
function fEn(wh) {{ return wh >= 1e6 ? (wh/1e6).toFixed(2)+' MWh' : wh >= 1e3 ? (wh/1e3).toFixed(2)+' kWh' : wh.toFixed(1)+' Wh'; }}
function fCO(g) {{ return g >= 1e6 ? (g/1e6).toFixed(2)+' tonnes' : g >= 1e3 ? (g/1e3).toFixed(2)+' kg' : g.toFixed(1)+' g'; }}
function fWa(ml) {{ return ml >= 1e6 ? (ml/1e6).toFixed(2)+' m³' : ml >= 1e3 ? (ml/1e3).toFixed(2)+' L' : ml.toFixed(0)+' mL'; }}
function fN(v) {{ return v >= 10 ? v.toLocaleString('en',{{maximumFractionDigits:0}}) : v >= 1 ? v.toFixed(1) : v.toFixed(2); }}
function fFix(v,d) {{ return v.toLocaleString('en',{{minimumFractionDigits:d,maximumFractionDigits:d}}); }}
function setText(id, t) {{ const el = document.getElementById(id); if (el) el.textContent = t; }}

function tipH(t) {{
  return '<div class="tip"><div class="tip-row"><span class="tip-label">Input</span><span class="tip-val">'+t.i.toLocaleString()+'</span></div>'
    +'<div class="tip-row"><span class="tip-label">Output</span><span class="tip-val">'+t.o.toLocaleString()+'</span></div>'
    +'<div class="tip-row"><span class="tip-label">Cached</span><span class="tip-val">'+t.c.toLocaleString()+'</span></div></div>';
}}

function updateDashboard() {{
  const s = document.getElementById('startDate').value;
  const e = document.getElementById('endDate').value;
  const fd = RAW.filter(r => r.d >= s && r.d <= e);
  if (!fd.length) return;
  const n = fd.length;
  const dl = fd.map(r => r.d);
  const ep = enabledProviders();
  const epSet = new Set(ep);

  // Totals (only enabled providers)
  let tot = {{cost:0,inp:0,out:0,cached:0,energy:0,carbon:0,water:0}};
  let pv = {{claude:{{cost:0,en:0,co:0}},codex:{{cost:0,en:0,co:0}},gemini:{{cost:0,en:0,co:0}}}};
  fd.forEach(row => {{
    PKEYS.forEach((k,i) => {{
      if (!epSet.has(PROVS[i])) return;
      const [inp,out,cached,cost] = row[k];
      const en = cE(inp,out,cached);
      tot.cost += cost; tot.inp += inp; tot.out += out; tot.cached += cached;
      tot.energy += en; tot.carbon += cC(en); tot.water += cW(en);
      pv[PROVS[i]].cost += cost; pv[PROVS[i]].en += en; pv[PROVS[i]].co += cC(en);
    }});
  }});
  const tTok = tot.inp + tot.out + tot.cached;

  // Header
  setText('dateRange', dl[0]+' to '+dl[dl.length-1]+' ('+n+' active days)');
  setText('tokenSummary', tTok.toLocaleString()+' total tokens · '+tot.inp.toLocaleString()+' input · '+tot.out.toLocaleString()+' output · '+tot.cached.toLocaleString()+' cached');

  // Usage cards
  const allInp = tot.inp + tot.cached;
  const cacheRate = allInp > 0 ? (tot.cached / allInp * 100).toFixed(0) : 0;

  // Cost: per-M-token rate + provider percentages
  const costPerM = tTok > 0 ? tot.cost / (tTok / 1e6) : 0;
  let costParts = [];
  [['claude','Claude'],['codex','Codex'],['gemini','Gemini']].forEach(([key,name]) => {{
    if (epSet.has(key)) {{
      const pct = tot.cost > 0 ? (pv[key].cost/tot.cost*100).toFixed(0) : 0;
      costParts.push(name+' '+pct+'%');
    }}
  }});
  let costDetail = fC(costPerM)+'/M tokens \u00b7 '+costParts.join(' \u00b7 ');
  setText('cardCostVal', fC(tot.cost));
  setText('cardCostDetail', costDetail);

  // Tokens: daily avg + busiest day (enabled providers only)
  let busiestVal = 0, busiestDate = '';
  fd.forEach(row => {{
    let dt = 0;
    PKEYS.forEach((k,i) => {{ if (epSet.has(PROVS[i])) dt += row[k][0]+row[k][1]+row[k][2]; }});
    if (dt > busiestVal) {{ busiestVal = dt; busiestDate = row.d; }}
  }});
  const bDateObj = new Date(busiestDate+'T00:00:00');
  const bDateStr = bDateObj.toLocaleDateString('en',{{month:'short',day:'numeric'}});
  setText('cardTokensVal', fT(tTok));
  setText('cardTokensDetail', fT(tTok/n)+'/day avg \u00b7 busiest: '+fT(busiestVal)+' ('+bDateStr+')');

  // Input: cache hit rate + savings
  const nonCacheTok = tot.inp + tot.out;
  const blendedRate = nonCacheTok > 0 ? tot.cost / nonCacheTok : 0;
  const cacheSavings = tot.cached * blendedRate * 0.75;
  setText('cardInputVal', fT(tot.inp));
  setText('cardInputDetail', cacheRate+'% cache hit rate \u00b7 ~'+fC(cacheSavings)+' saved vs uncached');

  // Output: estimate actual output cost using known rates per provider
  // c=Claude[inp,out,cached], x=Codex, g=Gemini
  const RATES = {{c:[3e-6,15e-6,0.30e-6], x:[0.69e-6,2.76e-6,0.17e-6], g:[0.15e-6,0.60e-6,0.0375e-6]}};
  let estOutCost = 0, estAllCost = 0;
  fd.forEach(row => {{
    [['c','claude',RATES.c],['x','codex',RATES.x],['g','gemini',RATES.g]].forEach(([k,p,r]) => {{
      if (!epSet.has(p)) return;
      const [inp,out,cached] = row[k];
      estOutCost += out * r[1];
      estAllCost += inp * r[0] + out * r[1] + cached * r[2];
    }});
  }});
  const outCostPct = estAllCost > 0 ? (estOutCost / estAllCost * 100).toFixed(0) : 0;
  const costPerMOut = tot.out > 0 ? estOutCost / (tot.out / 1e6) : 0;
  setText('cardOutputVal', fT(tot.out));
  setText('cardOutputDetail', fC(costPerMOut)+'/M output tokens \u00b7 drives ~'+outCostPct+'% of total cost');

  // Env cards
  const ec = (tot.energy/1000)*CN.ELEC;
  const elecPct = tot.cost > 0 ? (ec/tot.cost*100) : 0;
  const usDays = (tot.energy/1000)/30;
  const eCtx = usDays >= 1 ? '~'+fFix(usDays,1)+' days of avg US household electricity' : '~'+fFix(tot.energy/12.7,0)+' iPhone charges';
  setText('cardEnergyVal', fEn(tot.energy));
  const enParts = []; ep.forEach(p => {{ if (pv[p].en > 0) enParts.push(p.charAt(0).toUpperCase()+p.slice(1)+' '+fEn(pv[p].en)); }});
  setText('cardEnergyDetail', eCtx+(enParts.length ? ' · '+enParts.join(' · ') : ''));
  setText('cardCarbonVal', fCO(tot.carbon));
  const coParts = []; ep.forEach(p => {{ if (pv[p].co > 0) coParts.push(p.charAt(0).toUpperCase()+p.slice(1)+' '+fCO(pv[p].co)); }});
  setText('cardCarbonDetail', coParts.join(' · ') || 'No data');
  setText('cardWaterVal', fWa(tot.water));
  setText('cardWaterDetail', '~'+fN(tot.water/65000)+' showers');
  setText('cardElecVal', '$'+fFix(ec,2));
  setText('cardElecDetail', fFix(elecPct,2)+'% of API cost');

  // Equivalents
  const cKg = tot.carbon/1000;
  setText('eqHousehold', fN(cKg/900));
  setText('eqCar', fN(cKg/0.404));
  setText('eqFlights', fN(cKg/90));
  setText('eqTrees', fN(cKg/22));
  setText('eqShowers', fN(tot.water/65000));
  setText('eqIphone', fN(tot.energy/12.7));

  // Matrix (only enabled provider columns)
  const epIdx = []; // indices of enabled providers
  PROVS.forEach((p,i) => {{ if (epSet.has(p)) epIdx.push(i); }});
  const mo = {{}}, mt = {{}};
  fd.forEach(row => {{
    const m = row.d.slice(0,7);
    if (!mo[m]) {{ mo[m] = [0,0,0]; mt[m] = PKEYS.map(()=>({{i:0,o:0,c:0}})); }}
    epIdx.forEach(i => {{
      mo[m][i] += row[PKEYS[i]][3];
      mt[m][i].i += row[PKEYS[i]][0]; mt[m][i].o += row[PKEYS[i]][1]; mt[m][i].c += row[PKEYS[i]][2];
    }});
  }});
  const mk = Object.keys(mo).sort();
  if (mk.length >= 2) {{
    let cur = new Date(mk[0]+'-01');
    const end = new Date(mk[mk.length-1]+'-01');
    while (cur <= end) {{
      const k = cur.toISOString().slice(0,7);
      if (!mo[k]) {{ mo[k] = [0,0,0]; mt[k] = PKEYS.map(()=>({{i:0,o:0,c:0}})); }}
      cur.setMonth(cur.getMonth()+1);
    }}
  }}
  const sm = Object.keys(mo).sort();
  const ct = [0,0,0], ctk = PKEYS.map(()=>({{i:0,o:0,c:0}}));
  // Rebuild header with only enabled providers
  let hdr = '<tr><th></th>';
  epIdx.forEach(i => hdr += '<th class="'+PROVS[i]+'">'+PNAMES[i]+'</th>');
  hdr += '<th>Total</th></tr>';
  document.getElementById('matrixHead').innerHTML = hdr;
  let mh = '';
  sm.forEach(m => {{
    const c = mo[m], t = mt[m];
    let rt = 0; epIdx.forEach(i => rt += c[i]);
    epIdx.forEach(i => {{ ct[i]+=c[i]; ctk[i].i+=t[i].i; ctk[i].o+=t[i].o; ctk[i].c+=t[i].c; }});
    mh += '<tr><td class="month-label">'+m+'</td>';
    epIdx.forEach(i => mh += '<td class="has-tip">$'+fFix(c[i],2)+tipH(t[i])+'</td>');
    mh += '<td class="row-total">$'+fFix(rt,2)+'</td></tr>';
  }});
  let gt = 0; epIdx.forEach(i => gt += ct[i]);
  mh += '<tr class="col-totals"><td class="month-label">Total</td>';
  epIdx.forEach(i => mh += '<td class="has-tip">$'+fFix(ct[i],2)+tipH(ctk[i])+'</td>');
  mh += '<td class="row-total">$'+fFix(gt,2)+'</td></tr>';
  document.getElementById('matrixBody').innerHTML = mh;

  // Charts (only enabled providers)
  const pd = {{}};
  PROVS.forEach(p => {{ pd[p] = {{cost:[],tok:[],en:[],co:[]}}; }});
  const dcg = [];
  fd.forEach(row => {{
    let dc = 0;
    PKEYS.forEach((k,i) => {{
      if (!epSet.has(PROVS[i])) return;
      const [inp,out,cached,cost] = row[k];
      const en = cE(inp,out,cached), co = cC(en);
      pd[PROVS[i]].cost.push(Math.round(cost*100)/100);
      pd[PROVS[i]].tok.push(inp+out+cached);
      pd[PROVS[i]].en.push(en);
      pd[PROVS[i]].co.push(co);
      dc += co;
    }});
    dcg.push(dc);
  }});

  const sumEp = (obj, key, i) => ep.reduce((s,p) => s + (pd[p][key][i]||0), 0);
  const maxE = Math.max(...fd.map((_,i) => sumEp(pd,'en',i)), 0);
  const [eD,eU] = maxE >= 1e6 ? [1e6,'MWh'] : maxE >= 500 ? [1e3,'kWh'] : [1,'Wh'];
  const maxCo = Math.max(...dcg, 0);
  const [cD,cU] = maxCo >= 1e6 ? [1e6,'tonnes'] : maxCo >= 500 ? [1e3,'kg'] : [1,'g'];
  const maxTk = Math.max(...fd.map((_,i) => sumEp(pd,'tok',i)), 0);
  const [tD,tU] = maxTk >= 1e9 ? [1e9,'B tokens'] : maxTk >= 1e6 ? [1e6,'M tokens'] : maxTk >= 1e3 ? [1e3,'K tokens'] : [1,'tokens'];

  const sc = {{}}, cu = {{}};
  ep.forEach(p => {{
    sc[p] = {{
      cost: pd[p].cost,
      tok: pd[p].tok.map(v => Math.round(v/tD*100)/100),
      en: pd[p].en.map(v => Math.round(v/eD*10000)/10000),
      co: pd[p].co.map(v => Math.round(v/cD*10000)/10000),
    }};
    cu[p] = {{cost:[],tok:[],en:[],co:[]}};
    let cc=0,ct2=0,ce2=0,co2=0;
    fd.forEach((_,i) => {{
      cc+=pd[p].cost[i]; ct2+=pd[p].tok[i]; ce2+=pd[p].en[i]; co2+=pd[p].co[i];
      cu[p].cost.push(Math.round(cc*100)/100);
      cu[p].tok.push(Math.round(ct2/tD*100)/100);
      cu[p].en.push(Math.round(ce2/eD*100)/100);
      cu[p].co.push(Math.round(co2/cD*100)/100);
    }});
  }});

  // Total cumulative (sum of enabled providers)
  const cuTotal = {{cost:[],tok:[],en:[],co:[]}};
  fd.forEach((_,i) => {{
    ['cost','tok','en','co'].forEach(k => {{
      cuTotal[k].push(Math.round(ep.reduce((s,p) => s + cu[p][k][i], 0)*100)/100);
    }});
  }});

  // Build dynamic tooltip options matching the static ones
  function dynDailyOpts(unit, isPrefix, extraFn) {{
    const o = JSON.parse(JSON.stringify(stackOpts));
    const pre = isPrefix ? unit : '';
    const suf = isPrefix ? '' : ' '+unit;
    o.plugins.tooltip = {{ usePointStyle:true, callbacks: {{
      label: function(ctx) {{ return ' '+ctx.dataset.label+': '+pre+ctx.formattedValue+suf; }},
      footer: function(items) {{
        const total = items.reduce((s,i)=>s+(i.raw||0),0);
        let l = ['Total: '+pre+fFix(total,2)+suf];
        if (extraFn) l.push(extraFn(items, total));
        return l;
      }}
    }} }};
    return o;
  }}
  function dynCumOpts(unit, isPrefix, extraFn) {{
    const o = JSON.parse(JSON.stringify(baseOpts));
    o.plugins.legend.labels.usePointStyle = true;
    o.plugins.legend.labels.pointStyle = 'circle';
    o.interaction = {{mode:'index',intersect:false}};
    const pre = isPrefix ? unit : '';
    const suf = isPrefix ? '' : ' '+unit;
    o.plugins.tooltip = {{ mode:'index', intersect:false, usePointStyle:true, callbacks: {{
      label: function(ctx) {{ return ' '+ctx.dataset.label+': '+pre+ctx.formattedValue+suf; }},
      afterBody: function(items) {{
        const idx = items[0].dataIndex;
        const total = items.reduce((s,i)=>s+(i.raw||0),0);
        const days = idx+1, avg = total/days;
        let l = ['','Total: '+pre+fFix(total,2)+suf, 'Daily avg: '+pre+fFix(avg,2)+suf+' over '+days+' days'];
        if (extraFn) l.push(extraFn(items,total,idx));
        return l;
      }}
    }} }};
    return o;
  }}

  const dCostO = dynDailyOpts('$', true, null);
  // Smart token formatting for filtered data
  function fmtTokD(val) {{
    const abs = Math.abs(val) * tD;
    if (abs >= 1e9) return (abs/1e9).toFixed(2) + ' B tokens';
    if (abs >= 1e6) return (abs/1e6).toFixed(2) + ' M tokens';
    if (abs >= 1e3) return (abs/1e3).toFixed(2) + ' K tokens';
    return abs.toFixed(0) + ' tokens';
  }}
  const dTokO = (function() {{
    const o = JSON.parse(JSON.stringify(stackOpts));
    o.plugins.tooltip = {{ usePointStyle:true, callbacks: {{
      label: function(ctx) {{ return ' '+ctx.dataset.label+': '+fmtTokD(ctx.raw||0); }},
      footer: function(items) {{
        const total = items.reduce((s,i)=>s+(i.raw||0),0);
        return 'Total: '+fmtTokD(total);
      }}
    }} }};
    return o;
  }})();
  const dEnO = dynDailyOpts(eU, false, function(items, total) {{
    const kw = total*eD/1000;
    return 'Electricity: $'+fFix(kw*CN.ELEC,2)+' (~'+fFix(kw/1.25,1)+' hrs household use)';
  }});
  const dCoO = dynDailyOpts(cU, false, function(items, total) {{
    const idx = items[0].dataIndex;
    return '~'+fFix(dcg[idx]/1000/0.404,3)+' mi in a gas car (25 mpg)';
  }});
  const cCostO = dynCumOpts('$', true, null);
  const cTokO = (function() {{
    const o = JSON.parse(JSON.stringify(baseOpts));
    o.plugins.legend.labels.usePointStyle = true;
    o.plugins.legend.labels.pointStyle = 'circle';
    o.interaction = {{mode:'index',intersect:false}};
    o.plugins.tooltip = {{mode:'index',intersect:false, usePointStyle:true, callbacks: {{
      label: function(ctx) {{ return ' '+ctx.dataset.label+': '+fmtTokD(ctx.raw||0); }},
      afterBody: function(items) {{
        const idx = items[0].dataIndex;
        const total = items.reduce((s,i)=>s+(i.raw||0),0);
        const days = idx+1, avg = total/days;
        return ['','Total: '+fmtTokD(total),'Daily avg: '+fmtTokD(avg)+' over '+days+' days'];
      }}
    }}}};
    return o;
  }})();
  const cEnO = dynCumOpts(eU, false, function(items, total) {{
    const kw = total*eD/1000;
    return 'Electricity: $'+fFix(kw*CN.ELEC,2)+' (~'+fFix(kw/30,1)+' days household use)';
  }});
  const cCoO = dynCumOpts(cU, false, function(items, total) {{
    return '~'+fFix(total*cD/1000/0.404,2)+' mi in a gas car (25 mpg)';
  }});

  function mkDS(key, bar) {{
    if (bar) {{
      return ep.map(p => {{
        const i = PROVS.indexOf(p);
        return {{ label: PNAMES[i], data: sc[p][key], backgroundColor: PCOLORS[i] }};
      }});
    }}
    // Cumulative: Total line first, then per-provider
    const ds = [{{ label: 'Total', data: cuTotal[key], borderColor: '#e2e8f0', backgroundColor: '#e2e8f0', borderDash: [5,3], borderWidth: 2, fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }}];
    ep.forEach(p => {{
      const i = PROVS.indexOf(p);
      ds.push({{ label: PNAMES[i], data: cu[p][key], borderColor: PCOLORS[i], backgroundColor: PCOLORS[i], fill: false, tension: 0.3, pointRadius: 0, pointHoverRadius: 5, pointHitRadius: 8 }});
    }});
    return ds;
  }}

  chartConfigs.cost = {{
    canvas:'costChart', titleEl:'costTitle',
    dailyTitle:'Daily Cost by Provider ($)', cumTitle:'Cumulative Cost by Provider ($)',
    daily: {{type:'bar', datasets: mkDS('cost',true), options: dCostO}},
    cum: {{type:'line', datasets: mkDS('cost',false), options: cCostO}},
  }};
  chartConfigs.token = {{
    canvas:'tokenChart', titleEl:'tokenTitle',
    dailyTitle:'Daily Token Use by Provider ('+tU+')', cumTitle:'Cumulative Tokens by Provider ('+tU+')',
    daily: {{type:'bar', datasets: mkDS('tok',true), options: dTokO}},
    cum: {{type:'line', datasets: mkDS('tok',false), options: cTokO}},
  }};
  chartConfigs.energy = {{
    canvas:'energyChart', titleEl:'energyTitle',
    dailyTitle:'Daily Energy by Provider ('+eU+')', cumTitle:'Cumulative Energy ('+eU+')',
    daily: {{type:'bar', datasets: mkDS('en',true), options: dEnO}},
    cum: {{type:'line', datasets: mkDS('en',false), options: cEnO}},
  }};
  chartConfigs.carbon = {{
    canvas:'carbonChart', titleEl:'carbonTitle',
    dailyTitle:'Daily CO2 Emissions ('+cU+')', cumTitle:'Cumulative CO2 ('+cU+')',
    daily: {{type:'bar', datasets: mkDS('co',true), options: dCoO}},
    cum: {{type:'line', datasets: mkDS('co',false), options: cCoO}},
  }};

  Object.keys(chartConfigs).forEach(key => {{
    const cfg = chartConfigs[key];
    const mode = chartState[key] === 'cum' ? cfg.cum : cfg.daily;
    if (charts[key]) charts[key].destroy();
    charts[key] = new Chart(document.getElementById(cfg.canvas), {{
      type: mode.type, data: {{ labels: dl, datasets: mode.datasets }}, options: mode.options,
    }});
    document.getElementById(cfg.titleEl).textContent = chartState[key]==='cum' ? cfg.cumTitle : cfg.dailyTitle;
  }});
}}

document.getElementById('startDate').addEventListener('change', updateDashboard);
document.getElementById('endDate').addEventListener('change', updateDashboard);
document.getElementById('updateBtn').addEventListener('click', function() {{
  this.textContent = 'Updating...';
  this.style.opacity = '0.5';
  setTimeout(() => window.location.reload(), 200);
}});
function resetDates() {{
  document.getElementById('startDate').value = RAW[0].d;
  document.getElementById('endDate').value = RAW[RAW.length-1].d;
  updateDashboard();
}}
// Initial render: rebuild table/cards with correct provider visibility
updateDashboard();
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
