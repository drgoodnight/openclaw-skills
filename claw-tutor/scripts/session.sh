#!/usr/bin/env bash
# session.sh — Teaching session logging per student
#
# Usage:
#   session.sh <data-dir> start <student-slug> <topic> <mode>
#   session.sh <data-dir> end <student-slug> <session-id> [--summary <text>]
#   session.sh <data-dir> log-event <student-slug> <session-id> <event-json>
#   session.sh <data-dir> history <student-slug> [--topic <topic>] [--limit <n>]
#   session.sh <data-dir> report <student-slug>
#   session.sh <data-dir> cohort-report

set -euo pipefail

DATA_DIR="${1:?Usage: session.sh <data-dir> <command> ...}"
CMD="${2:?Usage: session.sh <data-dir> <command> ...}"
shift 2

STUDENTS_DIR="${DATA_DIR}/students"

get_sessions_file() {
  local slug="$1"
  echo "${STUDENTS_DIR}/${slug}/sessions.json"
}

case "$CMD" in

  start)
    SLUG="${1:?}"
    TOPIC="${2:?}"
    MODE="${3:?}"
    SESSIONS_FILE=$(get_sessions_file "$SLUG")
    [ ! -f "$SESSIONS_FILE" ] && { echo "ERROR: Student '$SLUG' not found." >&2; exit 1; }

    SESSION_ID="sess_$(date +%Y%m%d_%H%M%S)_$$"

    tmp=$(mktemp)
    jq --arg id "$SESSION_ID" \
       --arg topic "$TOPIC" \
       --arg mode "$MODE" \
       --arg started "$(date -Iseconds)" \
       '. + [{
         id: $id,
         topic: $topic,
         mode: $mode,
         started: $started,
         ended: null,
         events: [],
         summary: null,
         score: null
       }]' "$SESSIONS_FILE" > "$tmp"
    mv "$tmp" "$SESSIONS_FILE"

    echo "{\"session_id\":\"$SESSION_ID\",\"topic\":\"$TOPIC\",\"mode\":\"$MODE\"}"
    ;;

  end)
    SLUG="${1:?}"
    SESSION_ID="${2:?}"
    shift 2
    SUMMARY=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --summary) SUMMARY="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    SESSIONS_FILE=$(get_sessions_file "$SLUG")

    tmp=$(mktemp)
    jq --arg id "$SESSION_ID" \
       --arg ended "$(date -Iseconds)" \
       --arg summary "$SUMMARY" \
       'map(if .id == $id then
         .ended = $ended |
         .summary = (if $summary != "" then $summary else .summary end)
       else . end)' "$SESSIONS_FILE" > "$tmp"
    mv "$tmp" "$SESSIONS_FILE"

    echo "{\"status\":\"ended\",\"session_id\":\"$SESSION_ID\"}"
    ;;

  log-event)
    SLUG="${1:?}"
    SESSION_ID="${2:?}"
    EVENT_JSON="${3:?}"

    SESSIONS_FILE=$(get_sessions_file "$SLUG")

    # Add timestamp to event
    tmp=$(mktemp)
    jq --arg id "$SESSION_ID" \
       --argjson event "$EVENT_JSON" \
       --arg ts "$(date -Iseconds)" \
       'map(if .id == $id then
         .events += [$event + {timestamp: $ts}]
       else . end)' "$SESSIONS_FILE" > "$tmp"
    mv "$tmp" "$SESSIONS_FILE"

    echo "{\"status\":\"logged\"}"
    ;;

  history)
    SLUG="${1:?}"
    shift
    TOPIC=""
    LIMIT=10
    while [ $# -gt 0 ]; do
      case "$1" in
        --topic) TOPIC="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    SESSIONS_FILE=$(get_sessions_file "$SLUG")

    if [ -n "$TOPIC" ]; then
      jq --arg topic "$TOPIC" --argjson limit "$LIMIT" \
        '[.[] | select(.topic == $topic)] | sort_by(.started) | reverse | .[0:$limit]' "$SESSIONS_FILE"
    else
      jq --argjson limit "$LIMIT" \
        'sort_by(.started) | reverse | .[0:$limit]' "$SESSIONS_FILE"
    fi
    ;;

  report)
    SLUG="${1:?}"
    SESSIONS_FILE=$(get_sessions_file "$SLUG")
    SCORES_FILE="${STUDENTS_DIR}/${SLUG}/scores.json"
    PROFILE_FILE="${STUDENTS_DIR}/${SLUG}/profile.json"

    name=$(jq -r '.name' "$PROFILE_FILE")
    total_sessions=$(jq 'length' "$SESSIONS_FILE")
    topics_covered=$(jq '[.[].topic] | unique | length' "$SESSIONS_FILE")
    topic_list=$(jq -r '[.[].topic] | unique | join(", ")' "$SESSIONS_FILE")

    # Recent sessions
    recent=$(jq '[sort_by(.started) | reverse | .[0:5] | .[] |
      {topic: .topic, mode: .mode, date: (.started | split("T")[0]), events: (.events | length)}
    ]' "$SESSIONS_FILE")

    # Score summary per topic
    scores=$(jq 'to_entries | map({
      topic: .key,
      attempts: (.value | length),
      avg_score: (.value | map(.score) | add / length * 100 | round / 100),
      last_attempt: (.value | sort_by(.date) | last.date)
    })' "$SCORES_FILE" 2>/dev/null || echo "[]")

    jq -nc \
      --arg name "$name" \
      --argjson total_sessions "$total_sessions" \
      --argjson topics_covered "$topics_covered" \
      --arg topics "$topic_list" \
      --argjson recent "$recent" \
      --argjson scores "$scores" \
      '{
        student: $name,
        total_sessions: $total_sessions,
        topics_covered: $topics_covered,
        topics_list: $topics,
        recent_sessions: $recent,
        score_summary: $scores
      }'
    ;;

  cohort-report)
    echo "["
    first=true
    for student_dir in "${STUDENTS_DIR}"/*/; do
      [ ! -d "$student_dir" ] && continue
      slug=$(basename "$student_dir")
      [ ! -f "${student_dir}profile.json" ] && continue

      name=$(jq -r '.name' "${student_dir}profile.json")
      sessions=$(jq 'length' "${student_dir}sessions.json" 2>/dev/null || echo "0")
      topics=$(jq '[.[].topic] | unique | length' "${student_dir}sessions.json" 2>/dev/null || echo "0")
      last_active=$(jq -r '[.[].started] | sort | last // "never"' "${student_dir}sessions.json" 2>/dev/null || echo "never")

      # Average score across all topics
      avg_score=$(jq '[to_entries[].value[].score] | if length > 0 then (add / length * 100 | round / 100) else null end' "${student_dir}scores.json" 2>/dev/null || echo "null")

      entry=$(jq -nc \
        --arg name "$name" \
        --arg slug "$slug" \
        --argjson sessions "$sessions" \
        --argjson topics "$topics" \
        --arg last_active "$last_active" \
        --argjson avg_score "$avg_score" \
        '{name: $name, slug: $slug, sessions: $sessions, topics: $topics, last_active: $last_active, avg_score: $avg_score}')

      if [ "$first" = true ]; then
        echo "$entry"
        first=false
      else
        echo ",$entry"
      fi
    done
    echo "]"
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
