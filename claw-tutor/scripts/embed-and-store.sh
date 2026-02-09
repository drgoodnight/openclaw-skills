#!/usr/bin/env bash
# embed-and-store.sh — Embed JSONL chunks via Ollama, store in Qdrant
#
# All JSON payloads pass through temp files (curl -d @file) to avoid
# bash interpolation of $ and special characters in text content.
#
# On context-length errors, retries each chunk individually and skips
# any that still exceed the model's context window.
#
# Usage: embed-and-store.sh <jsonl-file> <start-id> [batch-size]
# Stdout: number of vectors stored

set -euo pipefail

JSONL_FILE="${1:?Usage: embed-and-store.sh <jsonl-file> <start-id> [batch-size]}"
START_ID="${2:?}"
BATCH_SIZE="${3:-10}"

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"
COLLECTION="teaching_library"

NUM_CHUNKS=$(wc -l < "$JSONL_FILE")
[ "$NUM_CHUNKS" -eq 0 ] && { echo "0"; exit 0; }

TMPDIR=$(mktemp -d /tmp/embed-XXXXXX)
trap "rm -rf $TMPDIR" EXIT

STORED=0
SKIPPED=0
BATCH_START=1

# --- Embed + upsert a single chunk (used for retries) ---
embed_single() {
  local line_num="$1"
  local point_id="$2"

  sed -n "${line_num}p" "$JSONL_FILE" \
    | jq -sc --arg model "$EMBED_MODEL" '{model: $model, input: [.[].text]}' \
    > "${TMPDIR}/single-req.json"

  local status
  status=$(curl -s -o "${TMPDIR}/single-resp.json" -w "%{http_code}" \
    -H 'Content-Type: application/json' \
    "${OLLAMA_URL}/api/embed" \
    -d @"${TMPDIR}/single-req.json" 2>/dev/null || echo "000")

  if [ "$status" != "200" ]; then
    return 1
  fi

  # Build upsert for single point
  sed -n "${line_num}p" "$JSONL_FILE" \
    | jq -sc \
      --slurpfile resp "${TMPDIR}/single-resp.json" \
      --argjson pid "$point_id" \
      '{points: [{id: $pid, vector: $resp[0].embeddings[0], payload: .[0]}]}' \
    > "${TMPDIR}/single-upsert.json"

  local up_status
  up_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "${QDRANT_URL}/collections/${COLLECTION}/points" \
    -H 'Content-Type: application/json' \
    -d @"${TMPDIR}/single-upsert.json" 2>/dev/null || echo "000")

  [ "$up_status" = "200" ]
}

# --- Main batch loop ---
while [ "$BATCH_START" -le "$NUM_CHUNKS" ]; do
  BATCH_END=$((BATCH_START + BATCH_SIZE - 1))
  [ "$BATCH_END" -gt "$NUM_CHUNKS" ] && BATCH_END="$NUM_CHUNKS"
  CURRENT_BATCH_SIZE=$((BATCH_END - BATCH_START + 1))

  # Build embed request as file
  sed -n "${BATCH_START},${BATCH_END}p" "$JSONL_FILE" \
    | jq -sc --arg model "$EMBED_MODEL" '{model: $model, input: [.[].text]}' \
    > "${TMPDIR}/embed-req.json"

  # Call Ollama
  EMBED_STATUS=$(curl -s -o "${TMPDIR}/embed-resp.json" -w "%{http_code}" \
    -H 'Content-Type: application/json' \
    "${OLLAMA_URL}/api/embed" \
    -d @"${TMPDIR}/embed-req.json" 2>/dev/null || echo "000")

  # Batch failed — try each chunk individually
  if [ "$EMBED_STATUS" != "200" ]; then
    echo "  Batch ${BATCH_START}-${BATCH_END} failed (HTTP ${EMBED_STATUS}), retrying individually..." >&2

    for line_num in $(seq "$BATCH_START" "$BATCH_END"); do
      local_id=$((START_ID + line_num))
      if embed_single "$line_num" "$local_id"; then
        STORED=$((STORED + 1))
      else
        SKIPPED=$((SKIPPED + 1))
        echo "  Skipped chunk ${line_num} (too large or embed error)" >&2
      fi
    done

    echo "  Embedded ${BATCH_END}/${NUM_CHUNKS} (${STORED} stored, ${SKIPPED} skipped)" >&2
    BATCH_START=$((BATCH_END + 1))
    continue
  fi

  # Verify embeddings count
  EMBED_COUNT=$(jq '.embeddings | length' "${TMPDIR}/embed-resp.json" 2>/dev/null || echo "0")
  if [ "$EMBED_COUNT" -ne "$CURRENT_BATCH_SIZE" ]; then
    echo "  WARN: Expected ${CURRENT_BATCH_SIZE} embeddings, got ${EMBED_COUNT}" >&2
    BATCH_START=$((BATCH_END + 1))
    continue
  fi

  # Build Qdrant upsert payload from files
  sed -n "${BATCH_START},${BATCH_END}p" "$JSONL_FILE" \
    | jq -sc \
      --slurpfile resp "${TMPDIR}/embed-resp.json" \
      --argjson start_id "$((START_ID + BATCH_START - 1))" \
      '{points: [to_entries[] | {
        id: (.key + $start_id + 1),
        vector: $resp[0].embeddings[.key],
        payload: .value
      }]}' \
    > "${TMPDIR}/upsert-req.json"

  # Upsert
  UPSERT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PUT "${QDRANT_URL}/collections/${COLLECTION}/points" \
    -H 'Content-Type: application/json' \
    -d @"${TMPDIR}/upsert-req.json" 2>/dev/null || echo "000")

  if [ "$UPSERT_STATUS" = "200" ]; then
    STORED=$((STORED + CURRENT_BATCH_SIZE))
  else
    echo "  WARN: Qdrant upsert failed (HTTP ${UPSERT_STATUS}) at batch ${BATCH_START}" >&2
  fi

  echo "  Embedded ${BATCH_END}/${NUM_CHUNKS} (${STORED} stored, ${SKIPPED} skipped)" >&2
  BATCH_START=$((BATCH_END + 1))
done

[ "$SKIPPED" -gt 0 ] && echo "  Total skipped: ${SKIPPED} chunks" >&2
echo "$STORED"
