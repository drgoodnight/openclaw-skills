#!/usr/bin/env bash
# index-library.sh — Extract, chunk, embed, and index a teaching document library
#
# Production version. Handles:
#   - PDF, EPUB, PPTX, DOCX, Markdown, plain text
#   - Table-heavy documents (strips pandoc table scaffolding)
#   - Oversized paragraphs (splits on line boundaries)
#   - Batch embedding via Ollama with per-chunk retry on failure
#   - Topic registry built from Qdrant (not fragile bash arrays)
#   - Image/diagram detection
#
# Usage: index-library.sh <library-dir> <data-dir> [--reindex]

set -euo pipefail

LIBRARY_DIR="${1:?Usage: index-library.sh <library-dir> <data-dir> [--reindex]}"
DATA_DIR="${2:?Usage: index-library.sh <library-dir> <data-dir> [--reindex]}"
REINDEX="${3:-}"

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"
COLLECTION="teaching_library"
CHUNK_TARGET=1000
BATCH_SIZE=10
QDRANT_CONTAINER="claw-tutor-qdrant"
QDRANT_VOLUME="${DATA_DIR}/qdrant-storage"
TOPIC_REGISTRY="${DATA_DIR}/topic-registry.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
fail()  { echo -e "${RED}[✗]${NC} $*"; }

# ─── Preflight ──────────────────────────────────────────────
for bin in docker curl pdftotext pandoc jq awk; do
  command -v "$bin" &>/dev/null || { fail "'$bin' not found."; exit 1; }
done
[ ! -d "$LIBRARY_DIR" ] && { fail "Library dir not found: $LIBRARY_DIR"; exit 1; }
mkdir -p "$DATA_DIR" "$QDRANT_VOLUME"

# ─── Ensure Qdrant ──────────────────────────────────────────
if docker ps --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER}$"; then
  info "Qdrant running."
elif docker ps -a --format '{{.Names}}' | grep -q "^${QDRANT_CONTAINER}$"; then
  docker start "$QDRANT_CONTAINER" >/dev/null; info "Qdrant restarted."
else
  docker run -d --name "$QDRANT_CONTAINER" -p 6333:6333 \
    -v "${QDRANT_VOLUME}:/qdrant/storage" --restart unless-stopped \
    qdrant/qdrant:latest >/dev/null
  info "Qdrant created."
fi
echo -n "Waiting for Qdrant..."
for i in $(seq 1 30); do
  curl -sf "${QDRANT_URL}/collections" >/dev/null 2>&1 && { echo " ready."; break; }
  [ "$i" -eq 30 ] && { echo " TIMEOUT"; exit 1; }
  echo -n "."; sleep 1
done

# ─── Ensure Ollama ──────────────────────────────────────────
curl -sf "${OLLAMA_URL}/api/tags" >/dev/null 2>&1 || { fail "Ollama not reachable at ${OLLAMA_URL}"; exit 1; }
if ! curl -sf "${OLLAMA_URL}/api/tags" | jq -e ".models[] | select(.name | startswith(\"${EMBED_MODEL}\"))" >/dev/null 2>&1; then
  warn "Pulling ${EMBED_MODEL}..."; ollama pull "$EMBED_MODEL"
fi
info "Ollama ready."

# ─── Setup collection ───────────────────────────────────────
if [ "$REINDEX" = "--reindex" ]; then
  curl -sf -X DELETE "${QDRANT_URL}/collections/${COLLECTION}" >/dev/null 2>&1 || true
fi
if ! curl -sf "${QDRANT_URL}/collections/${COLLECTION}" | jq -e '.result' >/dev/null 2>&1; then
  curl -sf -X PUT "${QDRANT_URL}/collections/${COLLECTION}" \
    -H 'Content-Type: application/json' \
    -d '{"vectors":{"size":768,"distance":"Cosine"}}' >/dev/null
  info "Collection created."
else
  info "Collection exists."
fi

# ─── Text extraction ────────────────────────────────────────
extract_text() {
  local filepath="$1" tmpfile="$2"
  local ext
  ext=$(echo "${filepath##*.}" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    pdf)      pdftotext -layout "$filepath" "$tmpfile" 2>/dev/null ;;
    epub)     pandoc -f epub -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    pptx)     pandoc -f pptx -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    docx)     pandoc -f docx -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    doc)      pandoc -f doc -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    odt)      pandoc -f odt -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    rtf)      pandoc -f rtf -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    html|htm) pandoc -f html -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    csv|tsv)  cp "$filepath" "$tmpfile" 2>/dev/null ;;
    rst)      pandoc -f rst -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    org)      pandoc -f org -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    tex|latex) pandoc -f latex -t plain --wrap=none "$filepath" -o "$tmpfile" 2>/dev/null ;;
    md|txt)   cp "$filepath" "$tmpfile" 2>/dev/null ;;
    *)        return 1 ;;
  esac
}

# ─── Image detection ────────────────────────────────────────
detect_images() {
  local ext
  ext=$(echo "${1##*.}" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    pptx) echo "true" ;;
    pdf)
      if command -v pdfimages &>/dev/null; then
        local c; c=$(pdfimages -list "$1" 2>/dev/null | tail -n +3 | wc -l)
        [ "$c" -gt 0 ] && echo "true" || echo "false"
      else echo "false"; fi ;;
    *) echo "false" ;;
  esac
}

# ─── Topic from path ────────────────────────────────────────
derive_topic() {
  local relpath="$1" dir
  dir=$(dirname "$relpath")
  if [ "$dir" = "." ]; then
    basename "$relpath" | sed 's/\.[^.]*$//' | sed 's/[_-]/ /g'
  else
    echo "$dir" | cut -d'/' -f1 | sed 's/[_-]/ /g'
  fi
}

# ─── Chunking ───────────────────────────────────────────────
# 1. Strip table scaffolding (+---+, pipes)
# 2. Split on paragraph boundaries (double-newline)
# 3. If a single paragraph exceeds CHUNK_TARGET, split on single newlines
# 4. Output null-separated raw text → jq for JSON escaping
chunk_file() {
  local text_file="$1"
  local source="$2"
  local topic="$3"
  local has_images="$4"
  local output_jsonl="$5"

  local cleaned="${text_file}.clean"

  # Strip table scaffolding: +---+---+, pipes, collapse leading whitespace
  sed 's/+[-=+]*+//g; s/^|//; s/|$//; s/|/  /g' "$text_file" > "$cleaned"

  local chunk_num=0

  awk -v target="$CHUNK_TARGET" '
  BEGIN { RS=""; chunk=""; clen=0 }
  {
    para = $0
    gsub(/\r/, "", para)
    plen = length(para)

    # Oversized single paragraph: split on line boundaries
    if (plen > target) {
      # Flush anything accumulated
      if (clen > 100) printf "%s\0", chunk

      n = split(para, lines, "\n")
      chunk = ""; clen = 0
      for (i = 1; i <= n; i++) {
        llen = length(lines[i])
        if (llen < 3) continue
        if (clen > 0 && clen + llen > target) {
          printf "%s\0", chunk
          chunk = lines[i]; clen = llen
        } else {
          chunk = (clen > 0) ? chunk "\n" lines[i] : lines[i]
          clen += llen
        }
      }
      next
    }

    # Normal paragraph: accumulate until target
    if (clen > 0 && clen + plen > target) {
      printf "%s\0", chunk
      chunk = para; clen = plen
    } else {
      if (clen > 0) chunk = chunk "\n\n" para
      else chunk = para
      clen += plen
    }
  }
  END { if (clen > 100) printf "%s\0", chunk }
  ' "$cleaned" | while IFS= read -r -d '' raw_chunk; do
    chunk_num=$((chunk_num + 1))
    echo "$raw_chunk" | jq -Rsc \
      --arg source "$source" \
      --arg topic "$topic" \
      --argjson idx "$chunk_num" \
      --arg img "$has_images" \
      '{text: ., source: $source, topic: $topic, chunk_index: $idx, has_images: ($img == "true")}'
  done > "$output_jsonl"

  rm -f "$cleaned"
  wc -l < "$output_jsonl"
}

# ─── Build topic registry from Qdrant ───────────────────────
build_registry() {
  echo "Building topic registry..."

  local all_payloads="[]"
  local scroll_id=""
  local scroll_body scroll_resp batch_points batch_count

  while true; do
    if [ -z "$scroll_id" ]; then
      scroll_body='{"limit":100,"with_payload":{"include":["source","topic","has_images"]}}'
    else
      scroll_body="{\"limit\":100,\"offset\":${scroll_id},\"with_payload\":{\"include\":[\"source\",\"topic\",\"has_images\"]}}"
    fi

    scroll_resp=$(curl -sf -X POST "${QDRANT_URL}/collections/${COLLECTION}/points/scroll" \
      -H 'Content-Type: application/json' \
      -d "$scroll_body" 2>/dev/null || echo '{"result":{"points":[]}}')

    batch_points=$(echo "$scroll_resp" | jq -c '[.result.points[].payload]')
    batch_count=$(echo "$batch_points" | jq 'length')
    [ "$batch_count" -eq 0 ] && break

    all_payloads=$(echo "$all_payloads $batch_points" | jq -sc 'add')
    scroll_id=$(echo "$scroll_resp" | jq '.result.next_page_offset // empty' 2>/dev/null)
    [ -z "$scroll_id" ] && break
  done

  echo "$all_payloads" | jq '
    group_by(.topic) | map({
      topic: .[0].topic,
      sources: [.[].source] | unique,
      chunk_count: length,
      sources_with_images: [.[] | select(.has_images == true) | .source] | unique
    })
  ' > "$TOPIC_REGISTRY"

  info "Topic registry saved."
}

# ========================
# MAIN
# ========================

WORK_DIR=$(mktemp -d /tmp/ct-index-XXXXXX)
trap "rm -rf $WORK_DIR" EXIT

TOTAL=0; SUCCESS=0; FAILED=0; GLOBAL_OFFSET=0

# Get current max point ID to avoid collisions on non-reindex runs
if [ "$REINDEX" != "--reindex" ]; then
  EXISTING=$(curl -sf "${QDRANT_URL}/collections/${COLLECTION}" 2>/dev/null \
    | jq '.result.points_count // 0')
  GLOBAL_OFFSET="${EXISTING:-0}"
fi

echo ""
echo "============================================="
echo "Indexing: $LIBRARY_DIR"
echo "============================================="

while IFS= read -r -d '' filepath; do
  TOTAL=$((TOTAL + 1))
  relpath="${filepath#$LIBRARY_DIR/}"
  topic=$(derive_topic "$relpath")
  has_images=$(detect_images "$filepath")

  echo ""
  echo "[$TOTAL] $relpath"
  echo "  Topic: \"$topic\"$([ "$has_images" = "true" ] && echo " 🖼")"

  # Extract
  tmptext="${WORK_DIR}/extracted.txt"
  if ! extract_text "$filepath" "$tmptext" || [ ! -s "$tmptext" ]; then
    warn "Extraction failed or empty — skipping."
    FAILED=$((FAILED + 1)); continue
  fi
  echo "  Extracted: $(wc -c < "$tmptext") bytes"

  # Chunk
  chunk_jsonl="${WORK_DIR}/chunks.jsonl"
  num_chunks=$(chunk_file "$tmptext" "$relpath" "$topic" "$has_images" "$chunk_jsonl")
  echo "  Chunks: $num_chunks"

  if [ "$num_chunks" -eq 0 ]; then
    warn "No chunks produced — skipping."
    FAILED=$((FAILED + 1)); continue
  fi

  # Validate first chunk is valid JSON
  if ! head -1 "$chunk_jsonl" | jq '.' >/dev/null 2>&1; then
    warn "Chunk JSON invalid — skipping."
    FAILED=$((FAILED + 1)); continue
  fi

  # Embed and store
  stored=$(bash "${SCRIPT_DIR}/embed-and-store.sh" "$chunk_jsonl" "$GLOBAL_OFFSET" "$BATCH_SIZE")
  echo "  Stored: $stored vectors"
  GLOBAL_OFFSET=$((GLOBAL_OFFSET + num_chunks))

  SUCCESS=$((SUCCESS + 1))
  rm -f "$tmptext" "$chunk_jsonl"

done < <(find "$LIBRARY_DIR" -type f \( \
  -iname '*.pdf' -o -iname '*.epub' -o -iname '*.pptx' \
  -o -iname '*.docx' -o -iname '*.doc' -o -iname '*.odt' \
  -o -iname '*.rtf' -o -iname '*.html' -o -iname '*.htm' \
  -o -iname '*.csv' -o -iname '*.tsv' \
  -o -iname '*.rst' -o -iname '*.org' -o -iname '*.tex' -o -iname '*.latex' \
  -o -iname '*.md' -o -iname '*.txt' \
  \) -print0 | sort -z)

# ─── Registry ───────────────────────────────────────────────
echo ""
build_registry

# ─── Summary ────────────────────────────────────────────────
TOPIC_COUNT=$(jq 'length' "$TOPIC_REGISTRY")
TOTAL_VECTORS=$(curl -sf "${QDRANT_URL}/collections/${COLLECTION}" \
  | jq '.result.points_count // 0')

echo ""
echo "============================================="
echo "Done: $SUCCESS/$TOTAL files indexed, $FAILED failed"
echo "Vectors: $TOTAL_VECTORS in collection"
echo "Topics: $TOPIC_COUNT"
jq -r '.[] | "  • \(.topic) (\(.chunk_count) chunks)\(if (.sources_with_images | length) > 0 then " 🖼" else "" end)"' "$TOPIC_REGISTRY"
echo "============================================="
