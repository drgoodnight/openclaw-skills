# Pressure Analysis Framework — Project Summary

**Date:** 6 February 2026
**Status:** Skill installed and running on OpenClaw agent
**Agent:** @nerpaibot (Telegram)
**Platform:** OpenClaw 2026.2.3-1 on atlas-01 VPS

---

## What We Built

An OpenClaw agent skill called `pressure-framework` that analyses social media narratives, news events, and information operations for manufactured pressure patterns. The skill teaches the agent a complete 6-phase analytical framework and gives it tools to score, format, monitor, and report on influence operations across any channel (Telegram, WhatsApp, SimpleX, etc.).

The core principle: **you don't predict events — you predict pressure.**

The core diagnostic: **is this solving a problem, or is it teaching people how to adapt?** Those are not the same thing.

---

## The 6-Phase Framework

### Phase 1: SORAM — Where is the pressure coming from?

- **S** — Societal: moral panic, us-vs-them, language policing, safe/dangerous framing
- **O** — Operational: drills, simulations, exercises before events unfold
- **R** — Regulatory: regulation appearing before crisis peaks = preparation, not reaction
- **A** — Alignment: government, media, tech, academia, NGOs agree fast = coordination, not consensus
- **M** — Media: same phrases, metaphors, tone across platforms = shaped language

### Phase 2: PRISM — Is it being seeded?

- **P** — Precursor Anomalies: oddly timed simulations, studies creating familiarity
- **R** — Repetition Cycles: "disinformation", "safety", "protect democracy" everywhere
- **I** — Introduced Villains: a group/profession/belief named as THE problem
- **S** — Symbolism Injection: colours, hashtags, badges bypassing thinking
- **M** — Manufactured Urgency: no debate window, "act now" shuts down analysis

### Phase 3: NARCS → PPI — How likely is this influence?

- **N** — Narrative Volatility: extreme, emotional, memetic language
- **A** — Authority Involvement: more authority = less organic
- **R** — Repeat Historical Analog: follows known template?
- **C** — Cognitive Load: exhausted public easier to steer
- **S** — Sentiment Inversion: values flipped — questions = harmful, compliance = virtue

**PPI (Psyop Probability Index) = average of NARCS scores.** High PPI = conditions ripe, intention likely.

### Phase 4: TRAP-N — What phase is the operation in?

- **T** — Tension: fear, uncertainty, scary forecasts
- **R** — Rally: sudden coordinated calls to action
- **A** — Authority: celebrity/expert/political unity, censorship
- **P** — Polarisation: good vs bad, protests and counter-protests
- **N** — Normalisation: habits formed, memory rewritten, new baseline accepted

### Phase 5: FATE — What is it doing to humans?

- **F** — Focus narrows
- **A** — Authority increases
- **T** — Tribe hardens
- **E** — Emotion overrides cognition

### Phase 6: 6-Axis — Internal human shift under pressure

- Focus tightens
- Openness drops
- Connection erodes
- Suggestibility rises
- Compliance increases
- Expectancy gets managed

Once you see which axis is being pulled, human behaviour becomes predictable. Humans default under pressure.

---

## Three Operating Modes

**Mode 1 — Manual Analysis:** Paste an article or forward a message → agent runs all 6 phases → returns formatted pressure report with scores, visual indicators, PPI, current operational phase, diagnostic verdict, and historical analog match.

**Mode 2 — Scheduled Monitoring:** Say "monitor [topic]" → agent sets up cron job using blogwatcher/bird skills → periodic scans → alerts when pressure thresholds are exceeded (default: overall ≥6, PPI ≥6, any single axis ≥8).

**Mode 3 — Interactive Walkthrough:** Say "walk me through" → agent steps through each phase with you, you score each axis, it compiles the full report at the end.

---

## Skill File Structure

```
~/clawd/skills/pressure-framework/
├── SKILL.md                           # Agent instruction manual — full framework,
│                                      # scoring rules, output format, all 3 modes
├── scripts/
│   ├── format_report.py               # Deterministic report formatting
│   │                                  # Supports emoji (Telegram), plain (SimpleX),
│   │                                  # JSON export, threshold alerts
│   └── feed_scanner.py                # Monitoring state management
│                                      # Monitor CRUD, content deduplication,
│                                      # feed source config
└── references/
    ├── historical-analogs.md          # 9 known influence operation patterns
    │                                  # (Safety Pivot, Manufactured Consensus,
    │                                  # Villain Simplification, Overton Shift,
    │                                  # Crisis Ratchet, Tribal Split, Memory Wash,
    │                                  # Preemptive Frame, Compassion Trap)
    └── monitoring.md                  # Schema and setup for scheduled monitoring
                                       # Config format, cron setup, alert format,
                                       # deduplication strategy
```

---

## Scoring System

Each axis is scored 0–10 based on observable evidence only. No speculation.

**Weighted overall pressure:**

| Model | Weight |
|-------|--------|
| SORAM | 25% |
| PRISM | 20% |
| NARCS | 25% |
| TRAP-N | 15% |
| FATE | 10% |
| 6-Axis | 5% |

**Severity levels:** 🔴 ≥8 (critical) · 🟠 ≥6 (warning) · 🟡 ≥4 (moderate) · 🟢 <4 (low)

**Verdicts:** High pressure (≥7) · Moderate (≥4) · Low (<4)

---

## Infrastructure Changes Made During Session

1. **Updated OpenClaw** from 2026.1.24-3 to 2026.2.3-1 (patched CVE-2026-25253 — token exfiltration vulnerability)
2. **Migrated state directory** from `~/.clawdbot` to `~/.openclaw` (symlinked, legacy compat)
3. **Migrated config** from `clawdbot.json` to `openclaw.json`
4. **Disabled broken SimpleX plugin** entry in config (plugin still being built, manifest not yet created)
5. **Stopped legacy `clawdbot-gateway` systemd service**, started new `openclaw` gateway
6. **Gateway auth token** configured (post-CVE security hardening)
7. **Shell completions** installed for `openclaw` CLI

---

## Current Agent Status

- **Binary:** `openclaw` (also responds to `clawdbot`)
- **Version:** 2026.2.3-1
- **Gateway:** running on `ws://127.0.0.1:18789` (PID variable)
- **Agent model:** openai/gpt-5.2
- **Channels:** Telegram (@nerpaibot) active
- **Skills:** 20 eligible, `pressure-framework` ready
- **Workspace:** `/home/cypherdoc/clawd`
- **Skills path:** `~/clawd/skills/`
- **SimpleX:** plugin disabled pending manifest creation

---

## What's Next

- **Test the skill** — send articles to the Telegram bot and run analyses
- **Build the SimpleX plugin** — create `openclaw.plugin.json` manifest at `~/clawd/extensions/simplex/`
- **Install feed skills** — `blogwatcher` and `bird` to enable monitoring mode
- **Iterate** — refine scoring criteria and thresholds based on real-world use
- **Publish** — optionally push to ClawdHub as a community skill
