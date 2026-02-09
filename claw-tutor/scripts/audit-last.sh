#!/usr/bin/env bash
# audit-last.sh — Print a human-readable audit trail for the most recent session.
#
# Usage:
#   audit-last.sh <data-dir> <student-slug> [--json]
#
# Output (default): compact, chat-friendly text.

set -euo pipefail

DATA_DIR="${1:?Usage: audit-last.sh <data-dir> <student-slug> [--json]}"
SLUG="${2:?Usage: audit-last.sh <data-dir> <student-slug> [--json]}"
MODE="text"

if [[ "${3-}" == "--json" ]]; then
  MODE="json"
fi

SESSIONS_FILE="${DATA_DIR}/students/${SLUG}/sessions.json"
if [[ ! -f "$SESSIONS_FILE" ]]; then
  echo "ERROR: sessions not found for slug '$SLUG'" >&2
  exit 1
fi

last_json=$(jq -c 'sort_by(.started) | reverse | .[0] // empty' "$SESSIONS_FILE")
if [[ -z "$last_json" ]]; then
  echo "No sessions found."
  exit 0
fi

if [[ "$MODE" == "json" ]]; then
  echo "$last_json" | jq '.'
  exit 0
fi

id=$(echo "$last_json" | jq -r '.id')
topic=$(echo "$last_json" | jq -r '.topic')
mode=$(echo "$last_json" | jq -r '.mode')
started=$(echo "$last_json" | jq -r '.started')
ended=$(echo "$last_json" | jq -r '.ended // ""')
summary=$(echo "$last_json" | jq -r '.summary // ""')
events_n=$(echo "$last_json" | jq -r '.events | length')

# Compact event rollup: type + (optional) source + timestamp
# We intentionally do NOT print full user-provided free text here (can contain PHI) unless you later choose to.
event_lines=$(echo "$last_json" | jq -r '
  .events
  | map({t:(.type // "event"), ts:(.timestamp // ""), src:(.source // .sources // "")})
  | map("- [\(.ts)] \(.t)" + (if (.src|tostring|length)>0 then " (src: \(.src|tostring))" else "" end))
  | .[]
' | head -n 40)

{
  echo "AUDIT (last session)"
  echo "Session: ${id}"
  echo "Topic: ${topic}"
  echo "Mode: ${mode}"
  echo "Started: ${started}"
  if [[ -n "$ended" && "$ended" != "null" ]]; then
    echo "Ended: ${ended}"
  fi
  echo "Events: ${events_n}"
  echo
  if [[ -n "$summary" && "$summary" != "null" ]]; then
    echo "Teaching Summary (logged):"
    echo "$summary"
    echo
  else
    echo "Teaching Summary (logged): <none>"
    echo
  fi
  echo "Event rollup (types only):"
  echo "$event_lines"
}