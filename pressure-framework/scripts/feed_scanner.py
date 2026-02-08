#!/usr/bin/env python3
"""
Pressure Framework — Feed Scanner

Utility for the monitoring mode. Manages monitor configs and checks
for content that needs analysis.

Usage:
  # List active monitors
  python3 feed_scanner.py --list

  # Add a monitor
  python3 feed_scanner.py --add --topic "digital ID" \
    --feeds "https://feeds.bbci.co.uk/news/rss.xml" \
    --keywords "digital ID,digital identity,#digitalID"

  # Remove a monitor
  python3 feed_scanner.py --remove --id monitor-001

  # Check if content hash has been seen (deduplication)
  python3 feed_scanner.py --seen "hash_string"

  # Mark content hash as seen
  python3 feed_scanner.py --mark "hash_string"
"""

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

STATE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "state")
MONITORS_FILE = os.path.join(STATE_DIR, "monitors.json")
SEEN_FILE = os.path.join(STATE_DIR, "seen_hashes.json")
MAX_SEEN = 500


def ensure_state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)


def load_monitors():
    ensure_state_dir()
    if os.path.exists(MONITORS_FILE):
        with open(MONITORS_FILE, "r") as f:
            return json.load(f)
    return {"monitors": []}


def save_monitors(data):
    ensure_state_dir()
    with open(MONITORS_FILE, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def load_seen():
    ensure_state_dir()
    if os.path.exists(SEEN_FILE):
        with open(SEEN_FILE, "r") as f:
            return json.load(f)
    return {"hashes": []}


def save_seen(data):
    ensure_state_dir()
    # Rotate if over limit
    if len(data["hashes"]) > MAX_SEEN:
        data["hashes"] = data["hashes"][-MAX_SEEN:]
    with open(SEEN_FILE, "w") as f:
        json.dump(data, f, indent=2)


def content_hash(text):
    return hashlib.sha256(text.strip().encode("utf-8")).hexdigest()[:16]


def list_monitors():
    data = load_monitors()
    if not data["monitors"]:
        print("No active monitors.")
        return
    for m in data["monitors"]:
        status = "ACTIVE" if m.get("active", False) else "PAUSED"
        print(f"[{status}] {m['id']}: {m['topic']}")
        if m.get("sources", {}).get("blogwatcher"):
            print(f"  Feeds: {', '.join(m['sources']['blogwatcher'][:3])}")
        if m.get("sources", {}).get("bird"):
            print(f"  X/Twitter: {', '.join(m['sources']['bird'][:3])}")
        freq = m.get("frequency_minutes", 120)
        print(f"  Frequency: every {freq} min | Alerts: {m.get('alert_count', 0)}")
        print(f"  Last check: {m.get('last_check', 'never')}")
        print()


def add_monitor(topic, feeds=None, keywords=None, frequency=120):
    data = load_monitors()
    idx = len(data["monitors"]) + 1
    monitor_id = f"monitor-{idx:03d}"

    sources = {}
    if feeds:
        sources["blogwatcher"] = [f.strip() for f in feeds.split(",")]
    if keywords:
        sources["bird"] = [k.strip() for k in keywords.split(",")]
    if not feeds and not keywords:
        sources["web_search"] = [topic]

    monitor = {
        "id": monitor_id,
        "topic": topic,
        "created": datetime.now(timezone.utc).isoformat(),
        "active": True,
        "sources": sources,
        "thresholds": {
            "overall_pressure": 6.0,
            "ppi_score": 6.0,
            "any_single_axis": 8,
            "model_average": 7.0,
        },
        "frequency_minutes": frequency,
        "last_check": None,
        "last_alert": None,
        "alert_count": 0,
    }

    data["monitors"].append(monitor)
    save_monitors(data)
    print(f"Added {monitor_id}: {topic}")
    print(json.dumps(monitor, indent=2))


def remove_monitor(monitor_id):
    data = load_monitors()
    before = len(data["monitors"])
    data["monitors"] = [m for m in data["monitors"] if m["id"] != monitor_id]
    save_monitors(data)
    if len(data["monitors"]) < before:
        print(f"Removed {monitor_id}")
    else:
        print(f"Monitor {monitor_id} not found")


def check_seen(text):
    h = content_hash(text)
    seen = load_seen()
    if h in seen["hashes"]:
        print(f"SEEN:{h}")
        return True
    else:
        print(f"NEW:{h}")
        return False


def mark_seen(text):
    h = content_hash(text)
    seen = load_seen()
    if h not in seen["hashes"]:
        seen["hashes"].append(h)
        save_seen(seen)
    print(f"MARKED:{h}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pressure Framework Feed Scanner")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--add", action="store_true")
    parser.add_argument("--remove", action="store_true")
    parser.add_argument("--topic", type=str)
    parser.add_argument("--feeds", type=str, help="Comma-separated RSS/Atom feed URLs")
    parser.add_argument("--keywords", type=str, help="Comma-separated X/Twitter search terms")
    parser.add_argument("--frequency", type=int, default=120)
    parser.add_argument("--id", type=str)
    parser.add_argument("--seen", type=str, help="Check if content has been analysed")
    parser.add_argument("--mark", type=str, help="Mark content as analysed")

    args = parser.parse_args()

    if args.list:
        list_monitors()
    elif args.add:
        if not args.topic:
            print("Error: --topic required")
            sys.exit(1)
        add_monitor(args.topic, args.feeds, args.keywords, args.frequency)
    elif args.remove:
        if not args.id:
            print("Error: --id required")
            sys.exit(1)
        remove_monitor(args.id)
    elif args.seen:
        sys.exit(0 if check_seen(args.seen) else 1)
    elif args.mark:
        mark_seen(args.mark)
    else:
        parser.print_help()
