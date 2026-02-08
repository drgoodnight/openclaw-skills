#!/usr/bin/env bash
# manage-infra.sh — Manage Docker infrastructure for claw-tutor
#
# Usage: manage-infra.sh <data-dir> <command>
#   Commands: start, stop, status, destroy

set -euo pipefail

DATA_DIR="${1:?Usage: manage-infra.sh <data-dir> <command>}"
COMMAND="${2:?Usage: manage-infra.sh <data-dir> <command> (start|stop|status|destroy)}"

QDRANT_CONTAINER="claw-tutor-qdrant"
QDRANT_VOLUME="${DATA_DIR}/qdrant-storage"
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"

case "$COMMAND" in
  start)
    mkdir -p "$QDRANT_VOLUME" "${DATA_DIR}/students"

    if docker ps --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER}$"; then
      echo "Qdrant already running."
    elif docker ps -a --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER}$"; then
      docker start "$QDRANT_CONTAINER" >/dev/null
      echo "Qdrant restarted."
    else
      docker run -d --name "$QDRANT_CONTAINER" -p 6333:6333 \
        -v "${QDRANT_VOLUME}:/qdrant/storage" --restart unless-stopped \
        qdrant/qdrant:latest >/dev/null
      echo "Qdrant container created."
    fi

    echo -n "Waiting for Qdrant..."
    for i in $(seq 1 30); do
      curl -sf "${QDRANT_URL}/collections" >/dev/null 2>&1 && { echo " ready."; exit 0; }
      echo -n "."; sleep 1
    done
    echo " TIMEOUT"; exit 1
    ;;

  stop)
    if docker ps --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER}$"; then
      docker stop "$QDRANT_CONTAINER" >/dev/null
      echo "Qdrant stopped."
    else
      echo "Qdrant not running."
    fi
    ;;

  status)
    echo "=== Clinical Tutor Infrastructure ==="
    echo ""

    if docker ps --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER}$"; then
      echo "Qdrant: RUNNING"
      if curl -sf "${QDRANT_URL}/collections/teaching_library" >/dev/null 2>&1; then
        point_count=$(curl -sf "${QDRANT_URL}/collections/teaching_library" | jq '.result.points_count' 2>/dev/null || echo "?")
        echo "  Vectors: $point_count"
      fi
    else
      echo "Qdrant: STOPPED"
    fi

    if curl -sf "${OLLAMA_URL}/api/tags" >/dev/null 2>&1; then
      echo "Ollama: RUNNING"
      has_model=$(curl -sf "${OLLAMA_URL}/api/tags" | jq -r '.models[].name' 2>/dev/null | grep -c "nomic-embed" || true)
      echo "  Embedding model: $([ "$has_model" -gt 0 ] && echo 'available' || echo 'NOT PULLED')"
    else
      echo "Ollama: NOT REACHABLE"
    fi

    TOPIC_REGISTRY="${DATA_DIR}/topic-registry.json"
    if [ -f "$TOPIC_REGISTRY" ]; then
      echo "Topics: $(jq 'length' "$TOPIC_REGISTRY") indexed"
    else
      echo "Topics: NOT INDEXED"
    fi

    # Student count
    student_count=0
    for d in "${DATA_DIR}/students"/*/; do
      [ -f "${d}profile.json" ] && student_count=$((student_count + 1))
    done
    echo "Students: $student_count registered"
    ;;

  destroy)
    echo "Removing Qdrant container (data preserved on disk)."
    docker rm -f "$QDRANT_CONTAINER" 2>/dev/null || true
    echo "Done. To delete all data: rm -rf $DATA_DIR"
    ;;

  *) echo "Unknown: $COMMAND (start|stop|status|destroy)" >&2; exit 1 ;;
esac
