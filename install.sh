#!/usr/bin/env bash
# install.sh — one-line installer for cc-minimax-status
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/install.sh | bash
#
# Flags (after the pipe):
#   --uninstall    Remove the statusline script and the statusLine block
#   --force, -f    Overwrite the script even if ~/.claude/statusline.sh exists
#   --help, -h     Show this help

set -euo pipefail

REPO="samir-abis/cc-minimax-status"
BRANCH="main"
SCRIPT_NAME="statusline.sh"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
CLAUDE_DIR="${HOME}/.claude"
SCRIPT_PATH="${CLAUDE_DIR}/${SCRIPT_NAME}"
SETTINGS_PATH="${CLAUDE_DIR}/settings.json"
STATUSLINE_BLOCK='{"type":"command","command":"~/.claude/statusline.sh","padding":2}'

# --- Parse args ---
FORCE=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --force|-f)  FORCE=1 ;;
    --help|-h)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

# --- Helpers ---
log()  { printf '\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m !\033[0m %s\n' "$*"; }
err()  { printf '\033[31m ✗\033[0m %s\n' "$*" >&2; }

# --- Pre-flight: jq is required (we use it to safely edit settings.json) ---
if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed."
  printf '   Install with one of:\n'
  printf '     brew install jq            # macOS\n'
  printf '     sudo apt install jq        # Debian / Ubuntu\n'
  printf '     sudo dnf install jq        # Fedora / RHEL\n'
  exit 1
fi

# --- Uninstall path ---
if [[ $UNINSTALL -eq 1 ]]; then
  log "Uninstalling cc-minimax-status"
  [[ -f "$SCRIPT_PATH" ]] && rm -f "$SCRIPT_PATH" && ok "Removed $SCRIPT_PATH"

  if [[ -f "$SETTINGS_PATH" ]]; then
    backup="${SETTINGS_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS_PATH" "$backup"
    if jq 'del(.statusLine)' "$SETTINGS_PATH" > "${SETTINGS_PATH}.tmp" \
         && mv "${SETTINGS_PATH}.tmp" "$SETTINGS_PATH"; then
      ok "Removed statusLine from $SETTINGS_PATH (backup: $backup)"
    else
      err "Failed to update $SETTINGS_PATH — your settings are unchanged."
      exit 1
    fi
  fi
  printf '\nRestart Claude Code to apply.\n'
  exit 0
fi

# --- Install path ---
log "Installing cc-minimax-status"

# 1. Ensure ~/.claude exists
mkdir -p "$CLAUDE_DIR"

# 2. Download the statusline script (atomic write via .tmp + mv)
if [[ -f "$SCRIPT_PATH" && $FORCE -eq 0 ]]; then
  warn "$SCRIPT_PATH already exists; skipping download. Use --force to overwrite."
else
  if ! curl -fsSL "${RAW_BASE}/${SCRIPT_NAME}" -o "${SCRIPT_PATH}.tmp"; then
    err "Download failed. Check your network connection and try again."
    rm -f "${SCRIPT_PATH}.tmp"
    exit 1
  fi
  chmod +x "${SCRIPT_PATH}.tmp"
  mv "${SCRIPT_PATH}.tmp" "$SCRIPT_PATH"
  ok "Installed $SCRIPT_NAME -> $SCRIPT_PATH"
fi

# 3. Patch settings.json (with timestamped backup if it exists)
if [[ -f "$SETTINGS_PATH" ]]; then
  backup="${SETTINGS_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$SETTINGS_PATH" "$backup"
  if ! jq --argjson sl "$STATUSLINE_BLOCK" '.statusLine = $sl' "$SETTINGS_PATH" \
       > "${SETTINGS_PATH}.tmp" \
       || ! mv "${SETTINGS_PATH}.tmp" "$SETTINGS_PATH"; then
    err "Failed to update $SETTINGS_PATH — your settings are unchanged."
    rm -f "${SETTINGS_PATH}.tmp"
    exit 1
  fi
  ok "Patched $SETTINGS_PATH (backup: $backup)"
else
  printf '{\n  "statusLine": %s\n}\n' "$STATUSLINE_BLOCK" > "$SETTINGS_PATH"
  ok "Created $SETTINGS_PATH"
fi

# 4. Verify
if ! jq -e '.statusLine.command' "$SETTINGS_PATH" >/dev/null 2>&1; then
  err "Post-install verification failed: statusLine.command is missing from $SETTINGS_PATH"
  exit 1
fi

printf '\n'
ok "Install complete."
printf '\n'
printf '   \033[1mNext step:\033[0m restart Claude Code to see the status line.\n'
printf '   The line will look like:\n\n'
printf '     MiniMax: 100%% / 5h (39m) | Ctx: 12%%\n\n'
printf '   Need to uninstall?  Re-run with --uninstall.\n'
