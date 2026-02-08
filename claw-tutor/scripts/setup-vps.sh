#!/usr/bin/env bash
# setup-vps.sh — Full setup for claw-tutor on a Linux VPS
#
# Supports: Ubuntu 20.04+, Debian 11+
# Run as: bash setup-vps.sh
#
# What it does:
#   1. Installs dependencies: Docker, Ollama, poppler-utils, pandoc, jq, bc
#   2. Pulls Qdrant Docker image and nomic-embed-text embedding model
#   3. Copies the skill into ~/.openclaw/skills/
#   4. Configures openclaw.json (interactive, with diff preview and backup)
#   5. Registers admin student profile
#
# Safe to re-run — idempotent, skips what's already done.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
fail()  { echo -e "${RED}[✗]${NC} $*"; }
step()  { echo -e "\n${GREEN}━━━ $* ━━━${NC}"; }

[ "$(uname -s)" != "Linux" ] && { fail "Linux only. Detected: $(uname -s)"; exit 1; }

if ! command -v apt-get &>/dev/null; then
  fail "Requires apt-get (Ubuntu/Debian). For other distros install manually:"
  echo "  docker, curl, jq, bc, poppler-utils, pandoc, ollama"
  exit 1
fi

SUDO=""
if [ "$EUID" -ne 0 ]; then
  command -v sudo &>/dev/null && SUDO="sudo" || { fail "Not root and no sudo."; exit 1; }
fi

# ─── System packages ───────────────────────────────────────
step "System packages"
$SUDO apt-get update -qq

PACKAGES=()
for pkg_bin in "jq:jq" "pdftotext:poppler-utils" "pandoc:pandoc" "curl:curl" "bc:bc"; do
  bin="${pkg_bin%%:*}"; pkg="${pkg_bin##*:}"
  if command -v "$bin" &>/dev/null; then
    info "$bin present"
  else
    PACKAGES+=("$pkg")
  fi
done

[ ${#PACKAGES[@]} -gt 0 ] && { $SUDO apt-get install -y -qq "${PACKAGES[@]}"; info "Installed: ${PACKAGES[*]}"; } || info "All present."

# ─── Docker ─────────────────────────────────────────────────
step "Docker"
if command -v docker &>/dev/null; then
  info "Docker installed: $(docker --version)"
  docker info &>/dev/null 2>&1 || { $SUDO systemctl start docker; $SUDO systemctl enable docker; }
else
  curl -fsSL https://get.docker.com | $SUDO sh
  [ -n "${SUDO_USER:-}" ] && $SUDO usermod -aG docker "$SUDO_USER"
  $SUDO systemctl start docker; $SUDO systemctl enable docker
  info "Docker installed."
fi

step "Qdrant image"
if docker image inspect qdrant/qdrant:latest &>/dev/null 2>&1 || $SUDO docker image inspect qdrant/qdrant:latest &>/dev/null 2>&1; then
  info "Already pulled."
else
  $SUDO docker pull qdrant/qdrant:latest; info "Pulled."
fi

# ─── Ollama ─────────────────────────────────────────────────
step "Ollama"
if command -v ollama &>/dev/null; then
  info "Ollama installed."
else
  curl -fsSL https://ollama.com/install.sh | sh; info "Installed."
fi

if ! curl -sf http://localhost:11434/api/tags &>/dev/null 2>&1; then
  warn "Starting Ollama..."
  if systemctl list-unit-files 2>/dev/null | grep -q ollama; then
    $SUDO systemctl start ollama; $SUDO systemctl enable ollama
  else
    nohup ollama serve > /tmp/ollama.log 2>&1 &
  fi
  echo -n "Waiting..."
  for i in $(seq 1 20); do
    curl -sf http://localhost:11434/api/tags &>/dev/null 2>&1 && { echo " ready."; break; }
    echo -n "."; sleep 1
  done
fi

step "Embedding model"
if curl -sf http://localhost:11434/api/tags 2>/dev/null | jq -e '.models[] | select(.name | startswith("nomic-embed-text"))' &>/dev/null; then
  info "nomic-embed-text available."
else
  ollama pull nomic-embed-text; info "Pulled."
fi

# ─── Verify ─────────────────────────────────────────────────
step "Verification"
ALL_GOOD=true
for bin in docker curl jq bc pdftotext pandoc ollama; do
  command -v "$bin" &>/dev/null && info "$bin: OK" || { fail "$bin: MISSING"; ALL_GOOD=false; }
done

if docker image inspect qdrant/qdrant:latest &>/dev/null 2>&1 || $SUDO docker image inspect qdrant/qdrant:latest &>/dev/null 2>&1; then
  info "Qdrant image: OK"
else
  fail "Qdrant image: MISSING"; ALL_GOOD=false
fi

curl -sf http://localhost:11434/api/tags 2>/dev/null | jq -e '.models[] | select(.name | startswith("nomic-embed-text"))' &>/dev/null \
  && info "Ollama + model: OK" || { fail "Ollama/model: NOT READY"; ALL_GOOD=false; }

[ "$ALL_GOOD" != true ] && { fail "Fix errors above before continuing."; exit 1; }
info "All dependencies verified."

# ─── Install skill ──────────────────────────────────────────
step "Skill Installation"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DEST="$HOME/.openclaw/skills/claw-tutor"

if [ ! -f "${SKILL_SOURCE_DIR}/SKILL.md" ]; then
  warn "SKILL.md not found. Copy claw-tutor/ to ~/.openclaw/skills/ manually."
else
  if [ -d "$SKILL_DEST" ]; then
    info "Skill already installed."
    echo -n "  Overwrite? [y/N] "
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      rm -rf "$SKILL_DEST"; cp -r "$SKILL_SOURCE_DIR" "$SKILL_DEST"; info "Updated."
    else
      info "Kept existing."
    fi
  else
    mkdir -p "$HOME/.openclaw/skills"
    cp -r "$SKILL_SOURCE_DIR" "$SKILL_DEST"
    info "Installed to $SKILL_DEST"
  fi
fi

# ─── Configure openclaw.json ────────────────────────────────
step "OpenClaw Configuration"

OPENCLAW_JSON=""
for path in "$HOME/.openclaw/openclaw.json" "$HOME/.config/openclaw/openclaw.json" "./openclaw.json"; do
  [ -f "$path" ] && { OPENCLAW_JSON="$path"; break; }
done

if [ -z "$OPENCLAW_JSON" ]; then
  echo -n "  Path to openclaw.json (Enter for ~/.openclaw/openclaw.json): "
  read -r custom
  if [ -z "$custom" ]; then
    OPENCLAW_JSON="$HOME/.openclaw/openclaw.json"
    mkdir -p "$(dirname "$OPENCLAW_JSON")"
    [ ! -f "$OPENCLAW_JSON" ] && echo '{}' > "$OPENCLAW_JSON"
    info "Created $OPENCLAW_JSON"
  elif [ -f "$custom" ]; then
    OPENCLAW_JSON="$custom"
  else
    fail "Not found: $custom"; OPENCLAW_JSON=""
  fi
fi

LIBRARY_PATH=""
DATA_PATH=""

if [ -n "$OPENCLAW_JSON" ]; then
  info "Using: $OPENCLAW_JSON"

  SKIP_CONFIG=false
  if jq -e '.skills.entries["claw-tutor"]' "$OPENCLAW_JSON" &>/dev/null 2>&1; then
    info "claw-tutor already configured:"
    jq '.skills.entries["claw-tutor"]' "$OPENCLAW_JSON" | sed 's/^/    /'
    echo -n "  Reconfigure? [y/N] "
    read -r ans
    [[ ! "$ans" =~ ^[Yy]$ ]] && SKIP_CONFIG=true
  fi

  if [ "$SKIP_CONFIG" = false ]; then
    DEFAULT_LIB="$HOME/teaching-library"
    echo -n "  Teaching library path [$DEFAULT_LIB]: "
    read -r LIBRARY_PATH
    LIBRARY_PATH="${LIBRARY_PATH:-$DEFAULT_LIB}"
    LIBRARY_PATH="${LIBRARY_PATH/#\~/$HOME}"

    if [ ! -d "$LIBRARY_PATH" ]; then
      echo -n "  Create $LIBRARY_PATH? [Y/n] "
      read -r ans
      [[ ! "$ans" =~ ^[Nn]$ ]] && { mkdir -p "$LIBRARY_PATH"; info "Created."; }
    fi

    DEFAULT_DATA="$HOME/.openclaw/claw-tutor-data"
    echo -n "  Data/index directory [$DEFAULT_DATA]: "
    read -r DATA_PATH
    DATA_PATH="${DATA_PATH:-$DEFAULT_DATA}"
    DATA_PATH="${DATA_PATH/#\~/$HOME}"
    mkdir -p "$DATA_PATH"

    PATCH=$(jq -nc \
      --arg lp "$LIBRARY_PATH" \
      --arg dp "$DATA_PATH" \
      '{skills:{entries:{"claw-tutor":{enabled:true,config:{libraryPath:$lp,dataDir:$dp}}}}}')

    MERGED=$(jq -s '.[0] * .[1]' "$OPENCLAW_JSON" <(echo "$PATCH"))

    echo ""
    echo "  Proposed claw-tutor config:"
    echo "$MERGED" | jq '.skills.entries["claw-tutor"]' | sed 's/^/    /'
    echo ""
    echo -n "  Apply? [Y/n] "
    read -r ans

    if [[ ! "$ans" =~ ^[Nn]$ ]]; then
      BACKUP="${OPENCLAW_JSON}.backup.$(date +%Y%m%d_%H%M%S)"
      cp "$OPENCLAW_JSON" "$BACKUP"
      echo "$MERGED" | jq '.' > "$OPENCLAW_JSON"
      info "Config written. Backup: $BACKUP"
    else
      warn "Not applied."
    fi
  else
    # Extract existing paths for admin setup
    LIBRARY_PATH=$(jq -r '.skills.entries["claw-tutor"].config.libraryPath // empty' "$OPENCLAW_JSON" 2>/dev/null || true)
    DATA_PATH=$(jq -r '.skills.entries["claw-tutor"].config.dataDir // empty' "$OPENCLAW_JSON" 2>/dev/null || true)
  fi
fi

# ─── Admin setup ────────────────────────────────────────────
step "Admin Registration"

if [ -n "$DATA_PATH" ] && [ -d "$DATA_PATH" ] || [ -n "$DATA_PATH" ]; then
  mkdir -p "${DATA_PATH}/students"

  echo "  The admin can view all students' progress and manage the library."
  echo -n "  Your name (for admin profile): "
  read -r ADMIN_NAME

  if [ -n "$ADMIN_NAME" ]; then
    ADMIN_SLUG=$(echo "$ADMIN_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

    # Use the student script to register + set admin
    STUDENT_SCRIPT="${SKILL_SOURCE_DIR}/scripts/student.sh"
    if [ -f "$STUDENT_SCRIPT" ]; then
      if [ ! -d "${DATA_PATH}/students/${ADMIN_SLUG}" ]; then
        bash "$STUDENT_SCRIPT" "$DATA_PATH" register "$ADMIN_NAME" >/dev/null
        info "Registered: $ADMIN_NAME ($ADMIN_SLUG)"
      else
        info "Profile exists: $ADMIN_SLUG"
      fi
      bash "$STUDENT_SCRIPT" "$DATA_PATH" set-admin "$ADMIN_SLUG" >/dev/null
      info "Admin role set."

      echo -n "  Your messaging ID (WhatsApp/Telegram, or Enter to skip): "
      read -r MSG_ID
      if [ -n "$MSG_ID" ]; then
        bash "$STUDENT_SCRIPT" "$DATA_PATH" link "$ADMIN_SLUG" "$MSG_ID" >/dev/null
        info "Linked messaging ID."
      fi
    else
      warn "student.sh not found — register admin manually via the agent."
    fi
  else
    warn "Skipped admin registration."
  fi
fi

# ─── Done ───────────────────────────────────────────────────
step "Setup Complete"
echo ""
echo "  ✓ All dependencies installed"
echo "  ✓ Qdrant + Ollama ready"
[ -d "${SKILL_DEST:-}" ] && echo "  ✓ Skill installed"
[ -n "${LIBRARY_PATH:-}" ] && echo "  ✓ Library: $LIBRARY_PATH"
[ -n "${DATA_PATH:-}" ] && echo "  ✓ Data: $DATA_PATH"
[ -n "${ADMIN_NAME:-}" ] && echo "  ✓ Admin: $ADMIN_NAME"
echo ""
echo "  Next:"
echo "  1. Upload teaching materials to your library path"
echo "  2. Tell the agent: \"Index my teaching library\""
echo "  3. Then: \"What topics do you have?\""
echo ""
