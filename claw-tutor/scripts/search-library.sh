#!/usr/bin/env bash
# search-library.sh — Semantic search over indexed teaching library
#
# All JSON payloads pass through temp files to avoid bash interpolation.
#
# Usage:
#   search-library.sh <data-dir> <query> [--topic <topic>] [--limit <n>]
#   search-library.sh <data-dir> --multi "<q1>" "<q2>" ... [--topic <topic>] [--limit <n>]

set -euo pipefail

DATA_DIR="${1:?Usage: search-library.sh <data-dir> <query|--multi> ...}"
shift

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"
COLLECTION="teaching_library"

QUERIES=()
TOPIC=""
LIMIT=5
MULTI=false

if [ "${1:-}" = "--multi" ]; then
  MULTI=true; shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --topic)  TOPIC="$2"; shift 2 ;;
    --limit)  LIMIT="$2"; shift 2 ;;
    --multi)  MULTI=true; shift ;;
    *)        QUERIES+=("$1"); shift ;;
  esac
done

[ ${#QUERIES[@]} -eq 0 ] && { echo "ERROR: No search query provided." >&2; exit 1; }

TMPDIR=$(mktemp -d /tmp/search-XXXXXX)
trap "rm -rf $TMPDIR" EXIT

# --- Single query search ---
search_single() {
  local query="$1"

  # Embed via file
  jq -nc --arg model "$EMBED_MODEL" --arg q "$query" \
    '{model: $model, input: $q}' > "${TMPDIR}/embed-req.json"

  curl -sf -H 'Content-Type: application/json' \
    "${OLLAMA_URL}/api/embed" \
    -d @"${TMPDIR}/embed-req.json" > "${TMPDIR}/embed-resp.json"

  local embedding
  embedding=$(jq -c '.embeddings[0]' "${TMPDIR}/embed-resp.json")
  [ -z "$embedding" ] || [ "$embedding" = "null" ] && { echo "ERROR: Embedding failed." >&2; exit 1; }

  # Build search request
  if [ -n "$TOPIC" ]; then
    jq -nc \
      --argjson vector "$embedding" \
      --argjson limit "$LIMIT" \
      --arg topic "$TOPIC" \
      '{vector: $vector, limit: $limit, with_payload: true, filter: {must: [{key: "topic", match: {value: $topic}}]}}' \
      > "${TMPDIR}/search-req.json"
  else
    jq -nc \
      --argjson vector "$embedding" \
      --argjson limit "$LIMIT" \
      '{vector: $vector, limit: $limit, with_payload: true}' \
      > "${TMPDIR}/search-req.json"
  fi

  curl -sf -X POST "${QDRANT_URL}/collections/${COLLECTION}/points/search" \
    -H 'Content-Type: application/json' \
    -d @"${TMPDIR}/search-req.json"
}

if [ "$MULTI" = true ] && [ ${#QUERIES[@]} -gt 1 ]; then
  ALL_RESULTS="[]"
  for query in "${QUERIES[@]}"; do
    response=$(search_single "$query")
    results=$(echo "$response" | jq -c '.result // []')
    ALL_RESULTS=$(echo "$ALL_RESULTS $results" | jq -sc 'add')
  done

  # Deduplicate by source+chunk_index, keep highest score
  MERGED=$(echo "$ALL_RESULTS" | jq -c '
    group_by(.payload.source + ":" + (.payload.chunk_index | tostring))
    | map(sort_by(-.score) | .[0])
    | sort_by(-.score)
    | .[0:'"$LIMIT"']
  ')

  num_results=$(echo "$MERGED" | jq 'length')
  echo "=== Multi-Search: ${QUERIES[*]} (${num_results} merged results) ==="
  [ -n "$TOPIC" ] && echo "=== Topic: \"$TOPIC\" ==="
  echo ""
  echo "$MERGED" | jq -r '.[] | "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\nSOURCE: \(.payload.source) | TOPIC: \(.payload.topic) | SCORE: \(.score | tostring | .[0:5])\(if .payload.has_images == true then " | 🖼 HAS IMAGES" else "" end)\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\(.payload.text)\n"'
else
  response=$(search_single "${QUERIES[0]}")
  num_results=$(echo "$response" | jq '.result | length')

  if [ "$num_results" -eq 0 ]; then
    echo "No results for: \"${QUERIES[0]}\""
    [ -n "$TOPIC" ] && echo "Topic filter: \"$TOPIC\""
    exit 0
  fi

  echo "=== Search: \"${QUERIES[0]}\" (${num_results} results) ==="
  [ -n "$TOPIC" ] && echo "=== Topic: \"$TOPIC\" ==="
  echo ""
  echo "$response" | jq -r '.result[] | "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\nSOURCE: \(.payload.source) | TOPIC: \(.payload.topic) | SCORE: \(.score | tostring | .[0:5])\(if .payload.has_images == true then " | 🖼 HAS IMAGES" else "" end)\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\(.payload.text)\n"'
fi
