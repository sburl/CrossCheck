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
        data = json.loads(output)
    except json.JSONDecodeError:
        print("  [skip] ccusage returned invalid JSON", file=sys.stderr)
        return {}

    daily = {}
    for entry in data:
        date = entry.get("date", "")
        if not date:
            continue
        daily[date] = {
            "provider": "claude",
            "input_tokens": entry.get("input_tokens", 0) or 0,
            "output_tokens": entry.get("output_tokens", 0) or 0,
            "cache_read_tokens": entry.get("cache_read_tokens", 0) or 0,
            "cache_write_tokens": entry.get("cache_write_tokens", 0) or 0,
            "cost": entry.get("total_cost", 0) or 0,
        }
    return daily


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
        data = json.loads(output)
    except json.JSONDecodeError:
        print("  [skip] @ccusage/codex returned invalid JSON", file=sys.stderr)
        return {}

    daily = {}
    for entry in data:
        date = entry.get("date", "")
        if not date:
            continue
        input_tok = entry.get("input_tokens", 0) or 0
        output_tok = entry.get("output_tokens", 0) or 0
        cost = entry.get("total_cost", 0)
        # If cost is missing/zero, estimate from tokens (codex model pricing)
        if not cost and (input_tok or output_tok):
            cost = (input_tok * 2.50 / 1_000_000) + (output_tok * 10.00 / 1_000_000)
        daily[date] = {
            "provider": "codex",
            "input_tokens": input_tok,
            "output_tokens": output_tok,
            "cache_read_tokens": entry.get("cache_read_tokens", 0) or 0,
            "cache_write_tokens": entry.get("cache_write_tokens", 0) or 0,
            "cost": cost or 0,
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

    # Equivalents
    carbon_kg = totals["carbon_g"] / 1000
    household_months = carbon_kg / 900
    car_miles = carbon_kg / 0.404
    flights_pct = carbon_kg / 90
    trees_needed = carbon_kg / 22
    showers = totals["water_ml"] / 65000
    iphone_charges = totals["energy_wh"] / 12.7

    # Build monthly cost matrix (months x providers)
    monthly = defaultdict(lambda: {"claude": 0, "codex": 0, "gemini": 0})
    for row in data:
        month_key = row["date"][:7]  # YYYY-MM
        for provider in ["claude", "codex", "gemini"]:
            monthly[month_key][provider] += row[provider]["cost"]

    sorted_months = sorted(monthly.keys())
    col_totals = {"claude": 0, "codex": 0, "gemini": 0}
    matrix_rows_html = ""
    for month in sorted_months:
        m = monthly[month]
        row_total = m["claude"] + m["codex"] + m["gemini"]
        col_totals["claude"] += m["claude"]
        col_totals["codex"] += m["codex"]
        col_totals["gemini"] += m["gemini"]
        matrix_rows_html += (
            f'<tr><td class="month-label">{month}</td>'
            f'<td>${m["claude"]:.2f}</td>'
            f'<td>${m["codex"]:.2f}</td>'
            f'<td>${m["gemini"]:.2f}</td>'
            f'<td class="row-total">${row_total:.2f}</td></tr>\n'
        )
    grand_total = col_totals["claude"] + col_totals["codex"] + col_totals["gemini"]
    matrix_footer_html = (
        f'<tr class="col-totals"><td class="month-label">Total</td>'
        f'<td>${col_totals["claude"]:.2f}</td>'
        f'<td>${col_totals["codex"]:.2f}</td>'
        f'<td>${col_totals["gemini"]:.2f}</td>'
        f'<td class="row-total">${grand_total:.2f}</td></tr>'
    )

    # Prepare chart data
    dates_json = json.dumps([r["date"] for r in data])
    claude_cost = json.dumps([round(r["claude"]["cost"], 2) for r in data])
    codex_cost = json.dumps([round(r["codex"]["cost"], 2) for r in data])
    gemini_cost = json.dumps([round(r["gemini"]["cost"], 2) for r in data])

    claude_energy = json.dumps([round(r["claude"]["energy_wh"], 2) for r in data])
    codex_energy = json.dumps([round(r["codex"]["energy_wh"], 2) for r in data])
    gemini_energy = json.dumps([round(r["gemini"]["energy_wh"], 2) for r in data])

    daily_carbon = [round(r["claude"]["carbon_g"] + r["codex"]["carbon_g"] + r["gemini"]["carbon_g"], 2) for r in data]
    carbon_colors = json.dumps(["#22c55e" if c < 5 else "#f59e0b" if c < 20 else "#ef4444" for c in daily_carbon])
    daily_carbon_json = json.dumps(daily_carbon)

    # Cumulative series
    cum_cost, cum_carbon = [], []
    rc, rcarb = 0, 0
    for row in data:
        for p in ["claude", "codex", "gemini"]:
            rc += row[p]["cost"]
            rcarb += row[p]["carbon_g"]
        cum_cost.append(round(rc, 2))
        cum_carbon.append(round(rcarb, 2))
    cum_cost_json = json.dumps(cum_cost)
    cum_carbon_json = json.dumps(cum_carbon)

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
  .chart-box h3 {{ font-size: 0.875rem; color: var(--muted); margin-bottom: 1rem; }}
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
</style>
</head>
<body>
<h1>AI Usage & Impact Dashboard</h1>
<p class="subtitle">{date_range} &middot; Generated {datetime.now().strftime("%Y-%m-%d %H:%M")}</p>

<div class="legend">
  <div class="legend-item"><div class="legend-dot" style="background: var(--claude)"></div> Claude Code</div>
  <div class="legend-item"><div class="legend-dot" style="background: var(--codex)"></div> Codex CLI</div>
  <div class="legend-item"><div class="legend-dot" style="background: var(--gemini)"></div> Gemini CLI</div>
</div>

<p class="token-summary">{total_tokens:,.0f} total tokens &middot; {totals['input_tokens']:,.0f} input &middot; {totals['output_tokens']:,.0f} output &middot; {totals['cache_read_tokens']:,.0f} cached</p>

{"<div class='no-data'>No usage data found. Make sure ccusage is installed (npm i -g ccusage).</div>" if not data else f'''
<div class="cards">
  <div class="card">
    <div class="label">Total API Cost</div>
    <div class="value">${totals["cost"]:.2f}</div>
    <div class="detail">{len(data)} days tracked</div>
  </div>
  <div class="card">
    <div class="label">Total Tokens</div>
    <div class="value">{total_tokens:,.0f}</div>
    <div class="detail">{totals["output_tokens"]:,.0f} output</div>
  </div>
  <div class="card">
    <div class="label">Input Tokens</div>
    <div class="value">{totals["input_tokens"]:,.0f}</div>
    <div class="detail">{totals["cache_read_tokens"]:,.0f} cached</div>
  </div>
  <div class="card">
    <div class="label">Output Tokens</div>
    <div class="value">{totals["output_tokens"]:,.0f}</div>
    <div class="detail">Most expensive token type</div>
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
    <h3>Daily Cost by Provider ($)</h3>
    <canvas id="costChart"></canvas>
  </div>
  <div class="chart-box">
    <h3>Cumulative Cost ($)</h3>
    <canvas id="cumCostChart"></canvas>
  </div>
</div>

<h3 class="section-title">Environmental Impact</h3>

<div class="cards">
  <div class="card">
    <div class="label">Energy Used</div>
    <div class="value">{totals["energy_wh"]:.1f} Wh</div>
    <div class="detail">{totals["energy_wh"]/1000:.4f} kWh</div>
  </div>
  <div class="card">
    <div class="label">CO2 Emitted</div>
    <div class="value">{totals["carbon_g"]:.1f} g</div>
    <div class="detail">{carbon_kg:.4f} kg CO2e</div>
  </div>
  <div class="card">
    <div class="label">Water Used</div>
    <div class="value">{totals["water_ml"]:.0f} mL</div>
    <div class="detail">{totals["water_ml"]/1000:.3f} L</div>
  </div>
  <div class="card">
    <div class="label">Electricity Cost</div>
    <div class="value">${electricity_cost:.4f}</div>
    <div class="detail">{energy_pct_of_api:.3f}% of API cost</div>
  </div>
</div>

<div class="charts">
  <div class="chart-box">
    <h3>Daily Energy by Provider (Wh)</h3>
    <canvas id="energyChart"></canvas>
  </div>
  <div class="chart-box">
    <h3>Daily CO2 Emissions (g)</h3>
    <canvas id="carbonChart"></canvas>
  </div>
  <div class="chart-box">
    <h3>Cumulative CO2 (g)</h3>
    <canvas id="cumCarbonChart"></canvas>
  </div>
</div>

<h3 class="section-title">Real-World Equivalents</h3>
<div class="equiv">
  <div class="equiv-card"><div class="num">{household_months:.4f}</div><div class="desc">Household-months of electricity</div></div>
  <div class="equiv-card"><div class="num">{car_miles:.2f}</div><div class="desc">Miles driven (avg car)</div></div>
  <div class="equiv-card"><div class="num">{flights_pct:.4f}</div><div class="desc">NYC-LA flights</div></div>
  <div class="equiv-card"><div class="num">{trees_needed:.4f}</div><div class="desc">Trees needed (1 year offset)</div></div>
  <div class="equiv-card"><div class="num">{showers:.4f}</div><div class="desc">Showers (water)</div></div>
  <div class="equiv-card"><div class="num">{iphone_charges:.1f}</div><div class="desc">iPhone charges</div></div>
</div>
'''}

<script>
const dates = {dates_json};
const opts = {{
  responsive: true,
  plugins: {{ legend: {{ display: false }} }},
  scales: {{
    x: {{ ticks: {{ color: '#94a3b8', maxRotation: 45 }}, grid: {{ color: '#1e293b' }} }},
    y: {{ ticks: {{ color: '#94a3b8' }}, grid: {{ color: '#334155' }} }}
  }}
}};
const stackOpts = JSON.parse(JSON.stringify(opts));
stackOpts.scales.x.stacked = true;
stackOpts.scales.y.stacked = true;

// Daily Cost
new Chart(document.getElementById('costChart'), {{
  type: 'bar', data: {{
    labels: dates,
    datasets: [
      {{ label: 'Claude', data: {claude_cost}, backgroundColor: '#6366f1' }},
      {{ label: 'Codex', data: {codex_cost}, backgroundColor: '#22c55e' }},
      {{ label: 'Gemini', data: {gemini_cost}, backgroundColor: '#f59e0b' }},
    ]
  }}, options: stackOpts
}});

// Daily Energy
new Chart(document.getElementById('energyChart'), {{
  type: 'bar', data: {{
    labels: dates,
    datasets: [
      {{ label: 'Claude', data: {claude_energy}, backgroundColor: '#6366f1' }},
      {{ label: 'Codex', data: {codex_energy}, backgroundColor: '#22c55e' }},
      {{ label: 'Gemini', data: {gemini_energy}, backgroundColor: '#f59e0b' }},
    ]
  }}, options: stackOpts
}});

// Daily Carbon
new Chart(document.getElementById('carbonChart'), {{
  type: 'bar', data: {{
    labels: dates,
    datasets: [{{ label: 'CO2', data: {daily_carbon_json}, backgroundColor: {carbon_colors} }}]
  }}, options: opts
}});

// Cumulative Cost
new Chart(document.getElementById('cumCostChart'), {{
  type: 'line', data: {{
    labels: dates,
    datasets: [{{ label: 'Cumulative $', data: {cum_cost_json}, borderColor: '#6366f1', fill: false, tension: 0.3 }}]
  }}, options: opts
}});

// Cumulative Carbon
new Chart(document.getElementById('cumCarbonChart'), {{
  type: 'line', data: {{
    labels: dates,
    datasets: [{{ label: 'Cumulative CO2 (g)', data: {cum_carbon_json}, borderColor: '#ef4444', fill: false, tension: 0.3 }}]
  }}, options: opts
}});
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
