---
name: pressure-framework
description: >
  Analyse social media narratives, news events, and information operations for pressure patterns
  using a 6-phase analytical framework: SORAM, PRISM, NARCS/PPI, TRAP-N, FATE, and 6-Axis.
  Trigger when the user asks to analyse news, narratives, media events, propaganda, psyops,
  influence operations, social media trends, or information warfare. Also trigger when the user
  says "analyse this", "run pressure analysis", "check this narrative", "is this a psyop",
  "monitor news", "watch for pressure", or forwards a news article for analysis.
  Three modes: (1) manual analysis of pasted content, (2) scheduled monitoring via cron +
  blogwatcher/bird skills, (3) interactive walkthrough scoring each phase with the user.
  Core principle: you don't predict events — you predict pressure.
---

# Pressure Analysis Framework

You don't predict events. You predict pressure.

## Core Principle

When something shows up, ask: **is this solving a problem, or is it teaching people how to adapt to a new condition?** Those are not the same thing.

## The 6-Phase Framework

Run all 6 phases in order. Score each axis 0–10 based on observable evidence only.

### Phase 1: SORAM — Where is the pressure coming from?

| Axis | Name | What to look for |
|------|------|-------------------|
| S | Societal | Moral panic, us-vs-them framing, language obsession, sudden focus on who is safe/dangerous, "misinformed" narratives |
| O | Operational | Drills, simulations, tabletop exercises, cyber/military/infrastructure exercises occurring before events unfold |
| R | Regulatory | Regulation appearing before crisis peaks — this is preparation, not reaction |
| A | Alignment | Government, media, tech, academia, NGOs agree fast — coordination, not consensus |
| M | Media | Same phrases, metaphors, emotional tone across platforms — uniform language = shaped pressure |

### Phase 2: PRISM — Is it being seeded?

| Axis | Name | What to look for |
|------|------|-------------------|
| P | Precursor Anomalies | Oddly timed simulations, tabletop exercises, scientific studies — rehearsals creating familiarity before the event |
| R | Repetition Cycles | Phrases like "disinformation", "safety", "protect democracy" repeated everywhere — repetition builds acceptance |
| I | Introduced Villains | A group, profession, belief, or nationality named as THE problem — simplifies complexity into emotional targets |
| S | Symbolism Injection | Colours, hashtags, badges pushed into discourse — symbols bypass thinking, go straight to identity |
| M | Manufactured Urgency | No onramp, no debate window, just "act now" — urgency shuts down analysis |

### Phase 3: NARCS → PPI — How likely is this influence?

| Axis | Name | What to look for |
|------|------|-------------------|
| N | Narrative Volatility | How extreme, emotionally charged, and memetic is the language? |
| A | Authority Involvement | Politicians, experts, officials, uniforms, celebrities — more authority = less organic |
| R | Repeat Historical Analog | Does this follow a structure known to have worked on humans before? Same emotional arc? |
| C | Cognitive Load | How exhausted is the public already? Tired populations are easier to steer |
| S | Sentiment Inversion | Values being flipped? Questions = harmful, silence = violence, compliance = virtue? |

**PPI (Psyop Probability Index) = average of all NARCS scores.** High PPI = conditions ripe, intention likely.

### Phase 4: TRAP-N — What phase is the operation in?

| Axis | Name | What to look for |
|------|------|-------------------|
| T | Tension | Fear, uncertainty, forecasts designed to scare |
| R | Rally | Sudden coordinated calls to action |
| A | Authority | Celebrity/expert/political unity, censorship |
| P | Polarisation | "Good vs bad people", protests and counter-protests |
| N | Normalisation | Habits formed, mass memory rewritten, new baseline accepted |

The highest-scoring axis indicates the current operational phase.

### Phase 5: FATE — What is it doing to humans?

| Axis | Name | Psyop signature |
|------|------|-----------------|
| F | Focus | Narrows — attention is directed, peripheral awareness drops |
| A | Authority | Increases — people defer upward, stop questioning |
| T | Tribe | Hardens — in-group loyalty intensifies, out-group hostility rises |
| E | Emotion | Overrides cognition — feeling replaces thinking |

### Phase 6: 6-Axis — Internal human shift under pressure

| Axis | Direction under pressure |
|------|------------------------|
| Focus | Tightens |
| Openness | Drops |
| Connection | Erodes |
| Suggestibility | Rises |
| Compliance | Increases |
| Expectancy | Gets managed |

Once you see which axis is being pulled, human behaviour becomes predictable. Humans default under pressure.

## Scoring Rules

1. Score each axis 0–10 based on **evidence you can identify**, not speculation.
2. If you cannot score an axis, use `null` — do not guess.
3. Always identify **who benefits** from the pressure.
4. Always answer the core diagnostic: **solving or adapting?**
5. PPI = average of NARCS scores.
6. Overall pressure = weighted average: SORAM 25%, PRISM 20%, NARCS 25%, TRAP-N 15%, FATE 10%, 6-Axis 5%.

## Output Format

Use the formatting script for consistent output. Run:

```bash
python3 {baseDir}/scripts/format_report.py --json '<raw_json>'
```

Or construct output manually using this structure:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡ PRESSURE ANALYSIS REPORT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📌 [Event/narrative]
🕐 [Timestamp]

[🔴/🟠/🟢] OVERALL: [score]/10
   [verdict text]

📊 PHASE SCORES
────────────────────────────
[For each model: emoji indicator, name, average, then each axis with score]

PPI (Psyop Probability Index): [score]/10
📍 CURRENT PHASE: [dominant TRAP-N axis]
[⚙️/⚡] DIAGNOSTIC: [solving/adapting]

🧠 HUMAN IMPACT (6-Axis)
[Each axis with score and direction]

🔍 KEY OBSERVATIONS
[Top 3 findings]

📜 HISTORICAL ANALOG: [if any]
```

Severity indicators: 🔴 ≥8, 🟠 ≥6, 🟡 ≥4, 🟢 <4

For JSON export, use: `python3 {baseDir}/scripts/format_report.py --export '<raw_json>'`

## Three Operating Modes

### Mode 1: Manual Analysis

User pastes content or forwards a message → run all 6 phases → return formatted report.

When the user says "analyse this" or pastes an article, news content, or URL:
1. Read/fetch the content
2. Run all 6 phases, scoring each axis with evidence
3. Answer the core diagnostic (solving vs adapting)
4. Output the formatted report
5. Offer to export JSON with `/export`

### Mode 2: Scheduled Monitoring

User says "monitor [topic]" → set up cron job + search skill to periodically check.

**Requires:** `blogwatcher` skill (for RSS/Atom feeds) and/or `bird` skill (for X/Twitter). If neither is available, tell the user which skills to install and offer manual mode instead.

Setup steps:
1. Ask the user what topics/feeds to monitor
2. Ask for alert thresholds (default: overall ≥6, PPI ≥6, any axis ≥8)
3. Ask for check frequency (default: every 2 hours)
4. Create a cron job that:
   - Uses blogwatcher/bird to fetch latest content on the topic
   - Runs pressure analysis on each item
   - Only messages the user if thresholds are exceeded
5. Store monitoring config in `{baseDir}/state/monitors.json`

Monitoring config schema — see `references/monitoring.md`.

### Mode 3: Interactive Walkthrough

User says "walk me through" or "let's analyse together" → step through each phase interactively.

1. Ask what event/narrative to analyse
2. For each phase (SORAM → PRISM → NARCS → TRAP-N → FATE → 6-Axis):
   - Present the phase name, question, and all axes with descriptions
   - Ask the user to score each axis 0–10
   - Accept input as `S=7 O=3 R=5 A=8 M=9` or `7 3 5 8 9`
   - Show phase result with visual indicators
3. Ask the core diagnostic: solving or adapting?
4. Compile and output the full report

## Alert Thresholds (for monitoring mode)

| Threshold | Default | Description |
|-----------|---------|-------------|
| overall_pressure | 6.0 | Weighted average across all models |
| ppi_score | 6.0 | NARCS average |
| any_single_axis | 8 | Any individual axis spike |
| model_average | 7.0 | Any single model's average |

User can adjust with "set threshold [type] [value]".

## Historical Analogs Reference

When scoring NARCS.R (Repeat Historical Analog), consult `references/historical-analogs.md` for known patterns.

## Commands

These work in any channel (Telegram, WhatsApp, SimpleX, etc.):

- **analyse [content]** or **/analyse** — run full analysis on pasted content
- **monitor [topic]** — start scheduled monitoring
- **monitor stop** — stop all monitoring
- **walk** or **walkthrough** — interactive phase-by-phase scoring
- **export** — get last analysis as JSON
- **models** — quick reference for all 6 models
- **thresholds** — view/set monitoring thresholds
