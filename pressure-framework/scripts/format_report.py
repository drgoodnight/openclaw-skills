#!/usr/bin/env python3
"""
Pressure Framework — Report Formatter

Takes JSON scores from the agent and outputs formatted reports.

Usage:
  # Formatted report (for chat channels)
  python3 format_report.py --json '{"event":"...","scores":{...}}'

  # JSON export
  python3 format_report.py --export '{"event":"...","scores":{...}}'

  # Plain text (no emoji — for SimpleX or plain terminals)
  python3 format_report.py --plain --json '{"event":"...","scores":{...}}'

Input JSON schema:
{
  "event": "description",
  "scores": {
    "soram": {"S": 7, "O": 3, "R": 5, "A": 8, "M": 9},
    "prism": {"P": 4, "R": 7, "I": 6, "S": 5, "M": 8},
    "narcs": {"N": 7, "A": 8, "R": 6, "C": 7, "S": 8},
    "trapn": {"T": 8, "R": 3, "A": 6, "P": 7, "N": 2},
    "fate":  {"F": 7, "A": 8, "T": 6, "E": 8},
    "sixaxis": {"focus": 8, "openness": 7, "connection": 7,
                "suggestibility": 8, "compliance": 6, "expectancy": 7}
  },
  "diagnostic": "solving" or "adapting",
  "reasoning": {"soram": "...", ...},
  "key_observations": ["...", "..."],
  "historical_analog": "..."
}
"""

import argparse
import json
import sys
from datetime import datetime, timezone

MODELS = {
    "soram": {
        "name": "SORAM", "axes": {
            "S": "Societal", "O": "Operational", "R": "Regulatory",
            "A": "Alignment", "M": "Media"
        }
    },
    "prism": {
        "name": "PRISM", "axes": {
            "P": "Precursor", "R": "Repetition", "I": "Villains",
            "S": "Symbolism", "M": "Urgency"
        }
    },
    "narcs": {
        "name": "NARCS", "axes": {
            "N": "Narrative", "A": "Authority", "R": "Historical",
            "C": "CogLoad", "S": "Inversion"
        }
    },
    "trapn": {
        "name": "TRAP-N", "axes": {
            "T": "Tension", "R": "Rally", "A": "Authority",
            "P": "Polarise", "N": "Normalise"
        }
    },
    "fate": {
        "name": "FATE", "axes": {
            "F": "Focus", "A": "Authority", "T": "Tribe", "E": "Emotion"
        }
    },
    "sixaxis": {
        "name": "6-Axis", "axes": {
            "focus": "Focus", "openness": "Openness", "connection": "Connection",
            "suggestibility": "Suggestib.", "compliance": "Compliance",
            "expectancy": "Expectancy"
        }
    },
}

WEIGHTS = {"soram": 0.25, "prism": 0.20, "narcs": 0.25, "trapn": 0.15, "fate": 0.10, "sixaxis": 0.05}

TRAPN_LABELS = {
    "T": "TENSION BUILDING", "R": "RALLY PHASE", "A": "AUTHORITY CONSOLIDATION",
    "P": "POLARISATION ACTIVE", "N": "NORMALISATION UNDERWAY"
}


def severity(val, emoji=True):
    if emoji:
        return "🔴" if val >= 8 else "🟠" if val >= 6 else "🟡" if val >= 4 else "🟢"
    return "[!!!]" if val >= 8 else "[!! ]" if val >= 6 else "[!  ]" if val >= 4 else "[   ]"


def bar(val, width=10):
    filled = round((val / 10) * width)
    return "█" * filled + "░" * (width - filled)


def model_avg(scores):
    vals = [v for v in scores.values() if v is not None]
    return round(sum(vals) / len(vals), 2) if vals else 0


def compute(data):
    scores = data.get("scores", {})
    averages = {k: model_avg(scores.get(k, {})) for k in MODELS}
    ppi = averages.get("narcs", 0)
    overall = round(sum(averages.get(k, 0) * w for k, w in WEIGHTS.items()), 2)

    # Dominant TRAP-N
    trapn_scores = scores.get("trapn", {})
    dominant = None
    if trapn_scores:
        top = max(trapn_scores.items(), key=lambda x: x[1] if x[1] else 0)
        if top[1] and top[1] > 0:
            dominant = f"{top[0]} — {TRAPN_LABELS.get(top[0], '?')}"

    if overall >= 7:
        verdict = "HIGH PRESSURE — conditions ripe for influence operation"
        level = "high"
    elif overall >= 4:
        verdict = "MODERATE PRESSURE — monitor closely, seeding possible"
        level = "moderate"
    else:
        verdict = "LOW PRESSURE — organic activity likely"
        level = "low"

    return {
        "averages": averages, "ppi": ppi, "overall": overall,
        "dominant_trapn": dominant, "verdict": verdict, "level": level
    }


def format_report(data, use_emoji=True):
    scores = data.get("scores", {})
    comp = compute(data)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    s = severity  # shorthand
    e = use_emoji

    lines = []
    lines.append("━" * 28)
    lines.append("⚡ PRESSURE ANALYSIS REPORT" if e else "   PRESSURE ANALYSIS REPORT")
    lines.append("━" * 28)
    lines.append(f"{'📌 ' if e else 'Event: '}{data.get('event', 'Unknown')}")
    lines.append(f"{'🕐 ' if e else 'Time:  '}{ts}")
    lines.append("")

    level_i = s(comp["overall"], e)
    lines.append(f"{level_i} OVERALL: {comp['overall']}/10")
    lines.append(f"   {bar(comp['overall'], 20)}")
    lines.append(f"   {comp['verdict']}")
    lines.append("")

    lines.append(f"{'📊 ' if e else ''}PHASE SCORES")
    lines.append("─" * 28)
    for mk, mdef in MODELS.items():
        avg = comp["averages"][mk]
        mi = s(avg, e)
        lines.append(f"{mi} {mdef['name']:8s} {avg:4.1f}/10  {bar(avg)}")
        ms = scores.get(mk, {})
        for ak, al in mdef["axes"].items():
            v = ms.get(ak)
            if v is not None:
                ai = s(v, e)
                lines.append(f"   {ai} {ak}·{al[:10]:10s} {v:2d}/10 {bar(v, 8)}")
        lines.append("")

    # PPI
    pi = s(comp["ppi"], e)
    lines.append("━" * 28)
    lines.append(f"{pi} PPI (Psyop Probability Index): {comp['ppi']}/10")
    if comp["ppi"] >= 7:
        lines.append("   Conditions ripe. Intention highly likely.")
    elif comp["ppi"] >= 4:
        lines.append("   Developing. Could be organic or manufactured.")
    else:
        lines.append("   Low probability of coordinated influence.")
    lines.append("")

    if comp["dominant_trapn"]:
        lines.append(f"{'📍 ' if e else ''}CURRENT PHASE: {comp['dominant_trapn']}")
        lines.append("")

    diag = data.get("diagnostic")
    if diag:
        di = "⚙️" if diag == "solving" and e else "⚡" if e else ""
        dt = "Solving a genuine problem" if diag == "solving" else "Teaching adaptation — not solving a real problem"
        lines.append(f"{di} DIAGNOSTIC: {dt}")
        lines.append("")

    # 6-Axis
    sa = scores.get("sixaxis", {})
    if any(v and v > 0 for v in sa.values()):
        dirs = {"focus": "tightens", "openness": "drops", "connection": "erodes",
                "suggestibility": "rises", "compliance": "increases", "expectancy": "managed"}
        lines.append(f"{'🧠 ' if e else ''}HUMAN IMPACT (6-Axis)")
        lines.append("─" * 28)
        for ak, v in sa.items():
            if v is not None:
                ai = s(v, e)
                lines.append(f"   {ai} {ak:14s} {v:2d}/10 ({dirs.get(ak, '')})")
        lines.append("")

    obs = data.get("key_observations", [])
    if obs:
        lines.append(f"{'🔍 ' if e else ''}KEY OBSERVATIONS")
        lines.append("─" * 28)
        for i, o in enumerate(obs, 1):
            lines.append(f"   {i}. {o}")
        lines.append("")

    analog = data.get("historical_analog", "")
    if analog:
        lines.append(f"{'📜 ' if e else ''}HISTORICAL ANALOG: {analog}")
        lines.append("")

    lines.append("━" * 28)
    lines.append("SORAM → PRISM → NARCS/PPI → TRAP-N → FATE → 6-Axis")
    lines.append("You don't predict events. You predict pressure.")

    return "\n".join(lines)


def format_json_export(data):
    comp = compute(data)
    export = {
        "event": data.get("event", ""),
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "scores": data.get("scores", {}),
        "averages": comp["averages"],
        "ppi_score": comp["ppi"],
        "overall_pressure": comp["overall"],
        "verdict": comp["verdict"],
        "verdict_level": comp["level"],
        "dominant_trapn_phase": comp["dominant_trapn"],
        "diagnostic": data.get("diagnostic"),
        "key_observations": data.get("key_observations", []),
        "historical_analog": data.get("historical_analog", ""),
        "reasoning": data.get("reasoning", {}),
    }
    return json.dumps(export, indent=2, ensure_ascii=False)


def format_alert(data, alerts):
    comp = compute(data)
    has_crit = any(a.get("level") == "critical" for a in alerts)
    lines = []
    lines.append(f"{'🚨' if has_crit else '⚠️'} PRESSURE ALERT")
    lines.append("━" * 24)
    lines.append(f"📌 {data.get('event', 'Unknown')[:60]}")
    lines.append(f"⚡ Overall: {comp['overall']}/10 | PPI: {comp['ppi']}/10")
    lines.append("")
    for a in alerts:
        icon = "🔴" if a.get("level") == "critical" else "🟠"
        lines.append(f"{icon} {a.get('message', '')}")
    if comp["dominant_trapn"]:
        lines.append(f"\n📍 Phase: {comp['dominant_trapn']}")
    lines.append('\n→ Say "analyse" for full report')
    return "\n".join(lines)


def check_thresholds(data, thresholds=None):
    if thresholds is None:
        thresholds = {"overall_pressure": 6.0, "ppi_score": 6.0,
                      "any_single_axis": 8, "model_average": 7.0}
    comp = compute(data)
    scores = data.get("scores", {})
    alerts = []

    if comp["overall"] >= thresholds["overall_pressure"]:
        alerts.append({"type": "overall", "level": "critical" if comp["overall"] >= 8 else "warning",
                       "message": f"Overall pressure at {comp['overall']}/10"})
    if comp["ppi"] >= thresholds["ppi_score"]:
        alerts.append({"type": "ppi", "level": "critical" if comp["ppi"] >= 8 else "warning",
                       "message": f"PPI at {comp['ppi']}/10"})
    for mk, mdef in MODELS.items():
        ms = scores.get(mk, {})
        for ak, v in ms.items():
            if v is not None and v >= thresholds["any_single_axis"]:
                alerts.append({"type": "axis", "level": "critical" if v >= 9 else "warning",
                               "message": f"{mdef['name']}.{ak} ({mdef['axes'].get(ak, ak)}) at {v}/10"})
        avg = comp["averages"].get(mk, 0)
        if avg >= thresholds["model_average"]:
            alerts.append({"type": "model", "level": "critical" if avg >= 8.5 else "warning",
                           "message": f"{mdef['name']} average at {avg}/10"})
    return alerts


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pressure Framework Report Formatter")
    parser.add_argument("--json", type=str, help="JSON input data")
    parser.add_argument("--export", type=str, help="JSON input → JSON export output")
    parser.add_argument("--plain", action="store_true", help="Plain text (no emoji)")
    parser.add_argument("--check", type=str, help="JSON input → check thresholds, output alerts")
    args = parser.parse_args()

    if args.export:
        data = json.loads(args.export)
        print(format_json_export(data))
    elif args.check:
        data = json.loads(args.check)
        alerts = check_thresholds(data)
        if alerts:
            print(format_alert(data, alerts))
        else:
            comp = compute(data)
            print(f"✅ No thresholds triggered. Overall: {comp['overall']}/10 | PPI: {comp['ppi']}/10")
    elif args.json:
        data = json.loads(args.json)
        print(format_report(data, use_emoji=not args.plain))
    else:
        parser.print_help()
        sys.exit(1)
