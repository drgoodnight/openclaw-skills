#!/usr/bin/env bash
# list-topics.sh — Display available topics
# Usage: list-topics.sh <data-dir> [--json]
set -euo pipefail

DATA_DIR="${1:?Usage: list-topics.sh <data-dir> [--json]}"
FORMAT="${2:-}"
TOPIC_REGISTRY="${DATA_DIR}/topic-registry.json"

if [ ! -f "$TOPIC_REGISTRY" ]; then
  echo "ERROR: No topic registry found. Run index-library.sh first." >&2
  exit 1
fi

if [ "$FORMAT" = "--json" ]; then
  cat "$TOPIC_REGISTRY"
  exit 0
fi

echo "=== Available Topics ==="
echo ""
jq -r 'to_entries[] | "\(.key + 1). \(.value.topic) (\(.value.chunk_count) chunks, \(.value.sources | length) sources)\(if (.value.sources_with_images | length) > 0 then " 🖼" else "" end)\n   Sources: \(.value.sources | join(", "))\n"' "$TOPIC_REGISTRY"

total_topics=$(jq 'length' "$TOPIC_REGISTRY")
total_chunks=$(jq '[.[].chunk_count] | add // 0' "$TOPIC_REGISTRY")
total_sources=$(jq '[.[].sources | length] | add // 0' "$TOPIC_REGISTRY")
echo "─────────────────────────────────"
echo "Total: ${total_topics} topics, ${total_sources} sources, ${total_chunks} chunks"
