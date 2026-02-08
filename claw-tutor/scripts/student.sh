#!/usr/bin/env bash
# student.sh — Multi-student management for claw-tutor
#
# Usage:
#   student.sh <data-dir> register <name> [--messaging-id <id>]
#   student.sh <data-dir> identify <messaging-id>
#   student.sh <data-dir> link <student-slug> <messaging-id>
#   student.sh <data-dir> profile <student-slug>
#   student.sh <data-dir> list
#   student.sh <data-dir> set-admin <student-slug>
#   student.sh <data-dir> is-admin <student-slug>
#   student.sh <data-dir> delete <student-slug>

set -euo pipefail

DATA_DIR="${1:?Usage: student.sh <data-dir> <command> ...}"
CMD="${2:?Usage: student.sh <data-dir> <command> ...}"
shift 2

STUDENTS_DIR="${DATA_DIR}/students"
IDENTITY_MAP="${STUDENTS_DIR}/_identity-map.json"
ADMIN_FILE="${STUDENTS_DIR}/_admin.json"

mkdir -p "$STUDENTS_DIR"
[ ! -f "$IDENTITY_MAP" ] && echo '{}' > "$IDENTITY_MAP"
[ ! -f "$ADMIN_FILE" ] && echo '{"admins":[]}' > "$ADMIN_FILE"

# --- Helpers ---
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

student_exists() {
  [ -d "${STUDENTS_DIR}/$1" ] && [ -f "${STUDENTS_DIR}/$1/profile.json" ]
}

# --- Commands ---
case "$CMD" in

  register)
    NAME="${1:?Usage: student.sh <data-dir> register <name> [--messaging-id <id>]}"
    shift
    MESSAGING_ID=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --messaging-id) MESSAGING_ID="$2"; shift 2 ;;
        *) shift ;;
      esac
    done

    SLUG=$(slugify "$NAME")
    STUDENT_DIR="${STUDENTS_DIR}/${SLUG}"

    if student_exists "$SLUG"; then
      echo "ERROR: Student '$SLUG' already exists." >&2
      exit 1
    fi

    mkdir -p "$STUDENT_DIR"

    # Profile
    jq -nc \
      --arg name "$NAME" \
      --arg slug "$SLUG" \
      --arg registered "$(date -Iseconds)" \
      '{
        name: $name,
        slug: $slug,
        registered: $registered,
        preferences: {
          difficulty: "adaptive",
          preferred_mode: null,
          notes: ""
        }
      }' > "${STUDENT_DIR}/profile.json"

    # Empty data files
    echo '[]' > "${STUDENT_DIR}/sessions.json"
    echo '{}' > "${STUDENT_DIR}/scores.json"
    echo '{}' > "${STUDENT_DIR}/srs-queue.json"

    # Link messaging ID if provided
    if [ -n "$MESSAGING_ID" ]; then
      tmp=$(mktemp)
      jq --arg mid "$MESSAGING_ID" --arg slug "$SLUG" '.[$mid] = $slug' "$IDENTITY_MAP" > "$tmp"
      mv "$tmp" "$IDENTITY_MAP"
    fi

    echo "{\"status\":\"registered\",\"slug\":\"$SLUG\",\"name\":\"$NAME\"}"
    ;;

  identify)
    MESSAGING_ID="${1:?Usage: student.sh <data-dir> identify <messaging-id>}"
    SLUG=$(jq -r --arg mid "$MESSAGING_ID" '.[$mid] // empty' "$IDENTITY_MAP")

    if [ -z "$SLUG" ]; then
      echo "{\"status\":\"unknown\",\"messaging_id\":\"$MESSAGING_ID\"}"
      exit 0
    fi

    if student_exists "$SLUG"; then
      cat "${STUDENTS_DIR}/${SLUG}/profile.json" | jq --arg status "identified" '. + {status: $status}'
    else
      echo "{\"status\":\"orphaned\",\"slug\":\"$SLUG\"}"
    fi
    ;;

  link)
    SLUG="${1:?Usage: student.sh <data-dir> link <student-slug> <messaging-id>}"
    MESSAGING_ID="${2:?Usage: student.sh <data-dir> link <student-slug> <messaging-id>}"

    if ! student_exists "$SLUG"; then
      echo "ERROR: Student '$SLUG' not found." >&2
      exit 1
    fi

    tmp=$(mktemp)
    jq --arg mid "$MESSAGING_ID" --arg slug "$SLUG" '.[$mid] = $slug' "$IDENTITY_MAP" > "$tmp"
    mv "$tmp" "$IDENTITY_MAP"
    echo "{\"status\":\"linked\",\"slug\":\"$SLUG\",\"messaging_id\":\"$MESSAGING_ID\"}"
    ;;

  profile)
    SLUG="${1:?Usage: student.sh <data-dir> profile <student-slug>}"

    if ! student_exists "$SLUG"; then
      echo "ERROR: Student '$SLUG' not found." >&2
      exit 1
    fi

    STUDENT_DIR="${STUDENTS_DIR}/${SLUG}"

    # Enrich profile with stats
    session_count=$(jq 'length' "${STUDENT_DIR}/sessions.json")
    topic_count=$(jq 'keys | length' "${STUDENT_DIR}/scores.json")
    srs_due=$(jq '[to_entries[] | select(.value.next_review <= now | todate)] | length' "${STUDENT_DIR}/srs-queue.json" 2>/dev/null || echo "0")

    # Is admin?
    is_admin=$(jq -r --arg slug "$SLUG" '.admins | index($slug) != null' "$ADMIN_FILE")

    jq --argjson sessions "$session_count" \
       --argjson topics "$topic_count" \
       --argjson srs_due "$srs_due" \
       --argjson is_admin "$is_admin" \
       '. + {session_count: $sessions, topics_studied: $topics, srs_items_due: $srs_due, is_admin: $is_admin}' \
       "${STUDENT_DIR}/profile.json"
    ;;

  list)
    echo "["
    first=true
    for student_dir in "${STUDENTS_DIR}"/*/; do
      [ ! -d "$student_dir" ] && continue
      profile="${student_dir}profile.json"
      [ ! -f "$profile" ] && continue

      slug=$(basename "$student_dir")
      session_count=$(jq 'length' "${student_dir}sessions.json" 2>/dev/null || echo "0")
      is_admin=$(jq -r --arg slug "$slug" '.admins | index($slug) != null' "$ADMIN_FILE")

      entry=$(jq --argjson sessions "$session_count" --argjson is_admin "$is_admin" \
        '. + {session_count: $sessions, is_admin: $is_admin}' "$profile")

      if [ "$first" = true ]; then
        echo "$entry"
        first=false
      else
        echo ",$entry"
      fi
    done
    echo "]"
    ;;

  set-admin)
    SLUG="${1:?Usage: student.sh <data-dir> set-admin <student-slug>}"
    if ! student_exists "$SLUG"; then
      echo "ERROR: Student '$SLUG' not found." >&2
      exit 1
    fi
    tmp=$(mktemp)
    jq --arg slug "$SLUG" '.admins = (.admins + [$slug] | unique)' "$ADMIN_FILE" > "$tmp"
    mv "$tmp" "$ADMIN_FILE"
    echo "{\"status\":\"admin_set\",\"slug\":\"$SLUG\"}"
    ;;

  is-admin)
    SLUG="${1:?Usage: student.sh <data-dir> is-admin <student-slug>}"
    result=$(jq -r --arg slug "$SLUG" '.admins | index($slug) != null' "$ADMIN_FILE")
    echo "{\"is_admin\":$result,\"slug\":\"$SLUG\"}"
    ;;

  delete)
    SLUG="${1:?Usage: student.sh <data-dir> delete <student-slug>}"
    if ! student_exists "$SLUG"; then
      echo "ERROR: Student '$SLUG' not found." >&2
      exit 1
    fi

    # Remove from identity map
    tmp=$(mktemp)
    jq --arg slug "$SLUG" 'with_entries(select(.value != $slug))' "$IDENTITY_MAP" > "$tmp"
    mv "$tmp" "$IDENTITY_MAP"

    # Remove from admins
    tmp=$(mktemp)
    jq --arg slug "$SLUG" '.admins -= [$slug]' "$ADMIN_FILE" > "$tmp"
    mv "$tmp" "$ADMIN_FILE"

    # Remove directory
    rm -rf "${STUDENTS_DIR}/${SLUG}"
    echo "{\"status\":\"deleted\",\"slug\":\"$SLUG\"}"
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Commands: register, identify, link, profile, list, set-admin, is-admin, delete" >&2
    exit 1
    ;;
esac
