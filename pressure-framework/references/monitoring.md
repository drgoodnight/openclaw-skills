# Monitoring Configuration

## Config Schema

Store monitoring state in `{baseDir}/state/monitors.json`:

```json
{
  "monitors": [
    {
      "id": "monitor-001",
      "topic": "digital ID legislation",
      "created": "2026-02-06T12:00:00Z",
      "active": true,
      "sources": {
        "blogwatcher": ["https://feeds.bbci.co.uk/news/rss.xml", "https://www.reddit.com/r/privacy/.rss"],
        "bird": ["digital ID", "digital identity", "#digitalID"],
        "web_search": ["digital ID legislation 2026"]
      },
      "thresholds": {
        "overall_pressure": 6.0,
        "ppi_score": 6.0,
        "any_single_axis": 8,
        "model_average": 7.0
      },
      "frequency_minutes": 120,
      "last_check": "2026-02-06T14:00:00Z",
      "last_alert": null,
      "alert_count": 0
    }
  ]
}
```

## Feed Source Priority

1. **blogwatcher** (if installed): Best for RSS/Atom feeds — news outlets, subreddits, blogs. Reliable, timestamped, structured.
2. **bird** (if installed): Best for X/Twitter — real-time narrative tracking, phrase monitoring, sentiment.
3. **web search** (via browser tool): Fallback — broader but noisier. Use for topics without dedicated feeds.

## Cron Setup

Use OpenClaw's built-in cron:

```
openclaw cron add --name "pressure-monitor-001" --schedule "0 */2 * * *" --command "Run pressure analysis on monitor-001 topics"
```

The cron job should:
1. Read `{baseDir}/state/monitors.json`
2. For each active monitor, fetch latest content from configured sources
3. Run pressure analysis on each new item
4. Compare scores against thresholds
5. If any threshold exceeded, send alert to the user's active channel
6. Update `last_check` timestamp

## Alert Format (Compact)

```
🚨 PRESSURE ALERT
━━━━━━━━━━━━━━━━━━━━━━━━
📌 [topic]
⚡ Overall: [n]/10 | PPI: [n]/10

🔴 [triggered threshold description]
🟠 [triggered threshold description]

📍 Phase: [TRAP-N dominant]
→ Say "analyse [topic]" for full report
```

## Deduplication

Track analysed content hashes in `{baseDir}/state/seen_hashes.json` to avoid re-analysing the same article. Keep last 500 hashes, rotate on overflow.
