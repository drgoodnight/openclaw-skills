#!/usr/bin/env bash
# srs.sh — Spaced repetition scheduling and score tracking per student
#
# Implements a simplified SM-2 algorithm:
#   - Each topic has an interval, ease factor, and next review date
#   - After each quiz/session, the schedule updates based on performance
#   - Performance: 0.0 (total fail) to 1.0 (perfect)
#
# Usage:
#   srs.sh <data-dir> record <student-slug> <topic> <score> <total> [<mode>]
#   srs.sh <data-dir> due <student-slug>
#   srs.sh <data-dir> due-count <student-slug>
#   srs.sh <data-dir> history <student-slug> <topic>
#   srs.sh <data-dir> recommend <student-slug> [--count <n>]
#   srs.sh <data-dir> reset <student-slug> <topic>

set -euo pipefail

DATA_DIR="${1:?Usage: srs.sh <data-dir> <command> ...}"
CMD="${2:?}"
shift 2

STUDENTS_DIR="${DATA_DIR}/students"

case "$CMD" in

  record)
    SLUG="${1:?}"
    TOPIC="${2:?}"
    SCORE="${3:?}"  # correct answers
    TOTAL="${4:?}"  # total questions
    MODE="${5:-mcq}"

    SCORES_FILE="${STUDENTS_DIR}/${SLUG}/scores.json"
    SRS_FILE="${STUDENTS_DIR}/${SLUG}/srs-queue.json"
    [ ! -f "$SCORES_FILE" ] && { echo "ERROR: Student not found." >&2; exit 1; }

    # Record score
    PERFORMANCE=$(echo "scale=4; $SCORE / $TOTAL" | bc)
    TODAY=$(date +%Y-%m-%d)

    tmp=$(mktemp)
    jq --arg topic "$TOPIC" \
       --argjson score "$SCORE" \
       --argjson total "$TOTAL" \
       --arg performance "$PERFORMANCE" \
       --arg date "$TODAY" \
       --arg mode "$MODE" \
       'if .[$topic] then
         .[$topic] += [{score: $score, total: $total, performance: ($performance | tonumber), date: $date, mode: $mode}]
       else
         .[$topic] = [{score: $score, total: $total, performance: ($performance | tonumber), date: $date, mode: $mode}]
       end' "$SCORES_FILE" > "$tmp"
    mv "$tmp" "$SCORES_FILE"

    # Update SRS schedule (simplified SM-2)
    # Get current SRS state for this topic
    current_interval=$(jq -r --arg t "$TOPIC" '.[$t].interval // 1' "$SRS_FILE")
    current_ease=$(jq -r --arg t "$TOPIC" '.[$t].ease // 2.5' "$SRS_FILE")
    current_reps=$(jq -r --arg t "$TOPIC" '.[$t].reps // 0' "$SRS_FILE")

    PERF_NUM=$(echo "$PERFORMANCE" | awk '{printf "%.2f", $1}')

    # SM-2 logic
    if (( $(echo "$PERF_NUM >= 0.6" | bc -l) )); then
      # Pass: increase interval
      if [ "$current_reps" = "0" ]; then
        new_interval=1
      elif [ "$current_reps" = "1" ]; then
        new_interval=3
      else
        new_interval=$(echo "scale=0; $current_interval * $current_ease / 1" | bc)
      fi
      new_reps=$((current_reps + 1))

      # Adjust ease factor
      new_ease=$(echo "scale=4; $current_ease + (0.1 - (1.0 - $PERF_NUM) * (0.08 + (1.0 - $PERF_NUM) * 0.02))" | bc)
      # Floor ease at 1.3
      if (( $(echo "$new_ease < 1.3" | bc -l) )); then
        new_ease="1.3"
      fi
    else
      # Fail: reset
      new_interval=1
      new_reps=0
      new_ease="$current_ease"
    fi

    # Cap interval at 180 days
    [ "$new_interval" -gt 180 ] && new_interval=180

    NEXT_REVIEW=$(date -d "+${new_interval} days" +%Y-%m-%d 2>/dev/null || date -v+${new_interval}d +%Y-%m-%d 2>/dev/null || echo "$TODAY")

    tmp=$(mktemp)
    jq --arg topic "$TOPIC" \
       --argjson interval "$new_interval" \
       --arg ease "$new_ease" \
       --argjson reps "$new_reps" \
       --arg next_review "$NEXT_REVIEW" \
       --arg last_reviewed "$TODAY" \
       --arg performance "$PERFORMANCE" \
       '.[$topic] = {
         interval: $interval,
         ease: ($ease | tonumber),
         reps: $reps,
         next_review: $next_review,
         last_reviewed: $last_reviewed,
         last_performance: ($performance | tonumber)
       }' "$SRS_FILE" > "$tmp"
    mv "$tmp" "$SRS_FILE"

    jq -nc \
      --arg topic "$TOPIC" \
      --argjson score "$SCORE" \
      --argjson total "$TOTAL" \
      --arg performance "$PERFORMANCE" \
      --argjson interval "$new_interval" \
      --arg next_review "$NEXT_REVIEW" \
      '{topic: $topic, score: $score, total: $total, performance: ($performance | tonumber), next_interval_days: $interval, next_review: $next_review}'
    ;;

  due)
    SLUG="${1:?}"
    SRS_FILE="${STUDENTS_DIR}/${SLUG}/srs-queue.json"
    [ ! -f "$SRS_FILE" ] && { echo "[]"; exit 0; }

    TODAY=$(date +%Y-%m-%d)
    jq --arg today "$TODAY" \
      '[to_entries[]
        | select(.value.next_review <= $today)
        | {topic: .key, next_review: .value.next_review, last_performance: .value.last_performance, interval: .value.interval, reps: .value.reps}
      ] | sort_by(.next_review)' "$SRS_FILE"
    ;;

  due-count)
    SLUG="${1:?}"
    SRS_FILE="${STUDENTS_DIR}/${SLUG}/srs-queue.json"
    [ ! -f "$SRS_FILE" ] && { echo "0"; exit 0; }

    TODAY=$(date +%Y-%m-%d)
    jq --arg today "$TODAY" \
      '[to_entries[] | select(.value.next_review <= $today)] | length' "$SRS_FILE"
    ;;

  history)
    SLUG="${1:?}"
    TOPIC="${2:?}"
    SCORES_FILE="${STUDENTS_DIR}/${SLUG}/scores.json"
    SRS_FILE="${STUDENTS_DIR}/${SLUG}/srs-queue.json"

    scores=$(jq --arg t "$TOPIC" '.[$t] // []' "$SCORES_FILE")
    srs=$(jq --arg t "$TOPIC" '.[$t] // null' "$SRS_FILE")

    jq -nc --argjson scores "$scores" --argjson srs "$srs" \
      '{score_history: $scores, srs_state: $srs}'
    ;;

  recommend)
    SLUG="${1:?}"
    shift
    COUNT=3
    while [ $# -gt 0 ]; do
      case "$1" in
        --count) COUNT="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    SRS_FILE="${STUDENTS_DIR}/${SLUG}/srs-queue.json"
    SCORES_FILE="${STUDENTS_DIR}/${SLUG}/scores.json"
    TOPIC_REGISTRY="${DATA_DIR}/topic-registry.json"

    [ ! -f "$SRS_FILE" ] && { echo "[]"; exit 0; }

    TODAY=$(date +%Y-%m-%d)

    # Priority 1: Overdue items (sorted by how overdue)
    overdue=$(jq --arg today "$TODAY" \
      '[to_entries[]
        | select(.value.next_review <= $today)
        | {topic: .key, reason: "overdue", priority: 1, next_review: .value.next_review, last_performance: .value.last_performance}
      ] | sort_by(.next_review)' "$SRS_FILE")

    # Priority 2: Weak topics (last performance < 0.6)
    weak=$(jq \
      '[to_entries[]
        | select(.value.last_performance < 0.6)
        | {topic: .key, reason: "weak", priority: 2, last_performance: .value.last_performance}
      ] | sort_by(.last_performance)' "$SRS_FILE")

    # Priority 3: Unstudied topics (in registry but not in scores)
    if [ -f "$TOPIC_REGISTRY" ]; then
      studied=$(jq -r 'keys[]' "$SCORES_FILE")
      available=$(jq -r '.[].topic' "$TOPIC_REGISTRY")
      unstudied=$(comm -23 <(echo "$available" | sort) <(echo "$studied" | sort) | head -n "$COUNT")
      unstudied_json=$(echo "$unstudied" | jq -R '{topic: ., reason: "not_yet_studied", priority: 3}' | jq -sc '.')
    else
      unstudied_json="[]"
    fi

    # Merge and deduplicate, take top N
    echo "$overdue $weak $unstudied_json" | jq -sc \
      "add | unique_by(.topic) | sort_by(.priority) | .[0:$COUNT]"
    ;;

  reset)
    SLUG="${1:?}"
    TOPIC="${2:?}"
    SRS_FILE="${STUDENTS_DIR}/${SLUG}/srs-queue.json"

    tmp=$(mktemp)
    jq --arg t "$TOPIC" 'del(.[$t])' "$SRS_FILE" > "$tmp"
    mv "$tmp" "$SRS_FILE"
    echo "{\"status\":\"reset\",\"topic\":\"$TOPIC\"}"
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    exit 1
    ;;
esac
