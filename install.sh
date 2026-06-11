#!/usr/bin/env bash
# install.sh — one-line installer for cc-minimax-status
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/samir-abis/cc-minimax-status/main/install.sh | bash
#
# Flags (after the pipe):
#   --uninstall         Remove the Claude Code statusline, the opencode
#                       TUI plugin, the /minimax slash command, and
#                       the settings.json patch
#   --claude-only       Only patch ~/.claude/ (skip opencode)
#   --opencode-only     Only install the opencode bits (skip ~/.claude/)
#   --force, -f         Overwrite files even if they already exist
#   --help, -h          Show this help

set -euo pipefail

REPO="samir-abis/cc-minimax-status"
BRANCH="main"
SCRIPT_NAME="statusline.sh"
PLUGIN_NAME="minimax-status.tsx"
COMMAND_NAME="minimax.md"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

CLAUDE_DIR="${HOME}/.claude"
SCRIPT_PATH="${CLAUDE_DIR}/${SCRIPT_NAME}"
SETTINGS_PATH="${CLAUDE_DIR}/settings.json"
STATUSLINE_BLOCK='{"type":"command","command":"~/.claude/statusline.sh","padding":2,"refreshInterval":30}'

OPENCODE_DIR="${HOME}/.config/opencode"
OPENCODE_PLUGINS_DIR="${OPENCODE_DIR}/plugins"
PLUGIN_PATH="${OPENCODE_PLUGINS_DIR}/${PLUGIN_NAME}"
OPENCODE_COMMANDS_DIR="${OPENCODE_DIR}/commands"
COMMAND_PATH="${OPENCODE_COMMANDS_DIR}/${COMMAND_NAME}"
TUI_JSONC="${OPENCODE_DIR}/tui.jsonc"
TUI_JSON="${OPENCODE_DIR}/tui.json"
OPENCODE_JSONC="${OPENCODE_DIR}/opencode.jsonc"
OPENCODE_JSON="${OPENCODE_DIR}/opencode.json"
OPENCODE_PKG_PATH="${OPENCODE_DIR}/package.json"

# --- Parse args ---
FORCE=0
UNINSTALL=0
CLAUDE_ONLY=0
OPENCODE_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --uninstall)     UNINSTALL=1 ;;
    --claude-only)   CLAUDE_ONLY=1 ;;
    --opencode-only) OPENCODE_ONLY=1 ;;
    --force|-f)      FORCE=1 ;;
    --help|-h)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

if [[ $CLAUDE_ONLY -eq 1 && $OPENCODE_ONLY -eq 1 ]]; then
  printf '\033[31m ✗\033[0m --claude-only and --opencode-only are mutually exclusive.\n' >&2
  exit 1
fi
INSTALL_CLAUDE=1
INSTALL_OPENCODE=1
if [[ $OPENCODE_ONLY -eq 1 ]]; then INSTALL_CLAUDE=0; fi
if [[ $CLAUDE_ONLY -eq 1 ]]; then INSTALL_OPENCODE=0; fi

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
  printf '     sudo apt install jq        # Fedora / RHEL (or: sudo dnf install jq)\n'
  exit 1
fi

# --- Download helper: $1 url, $2 dest, $3 human label ---
download() {
  local url="$1" dest="$2" label="$3"
  if ! curl -fsSL "$url" -o "${dest}.tmp"; then
    err "Download failed for ${label}: $url"
    rm -f "${dest}.tmp"
    return 1
  fi
  mv "${dest}.tmp" "$dest"
}

# Strip any stale v0.3.0 / v0.4.0 / v0.5.0 `plugin: [...]` entry from the
# SERVER config (opencode.jsonc). The TUI plugin belongs in tui.jsonc.
strip_legacy_server_plugin_entry() {
  local target
  if [[ -f "$OPENCODE_JSONC" ]]; then target="$OPENCODE_JSONC"
  elif [[ -f "$OPENCODE_JSON" ]]; then target="$OPENCODE_JSON"
  else return 0; fi
  if ! grep -qE 'minimax-status' "$target" 2>/dev/null; then return 0; fi
  if ! jq '.plugin = ((.plugin // []) | map(select(
    (type == "string" and (contains("minimax-status") | not)) or
    (type == "array"  and (.[0] | type == "string" and (contains("minimax-status") | not)))
  )))' "$target" > "${target}.tmp" 2>/dev/null; then
    warn "Failed to clean stale plugin entry from $target — leaving as-is."
    return 0
  fi
  cp "$target" "${target}.bak.$(date +%Y%m%d%H%M%S)"
  mv "${target}.tmp" "$target"
  ok "Removed stale plugin entry from $target (the TUI plugin belongs in tui.json[c])"
}

# Drop @opentui/{core,solid} from opencode/package.json if a prior
# install added them. Not needed — opencode's binary ships them and
# the user's plugin resolves them at runtime.
drop_legacy_opentui_deps() {
  if [[ ! -f "$OPENCODE_PKG_PATH" ]]; then return 0; fi
  if ! grep -qE '"@opentui/(core|solid)"' "$OPENCODE_PKG_PATH" 2>/dev/null; then return 0; fi
  if ! jq 'del(.dependencies["@opentui/core"], .dependencies["@opentui/solid"])' \
       "$OPENCODE_PKG_PATH" > "${OPENCODE_PKG_PATH}.tmp" 2>/dev/null; then
    warn "Failed to clean @opentui/* from $OPENCODE_PKG_PATH — leaving as-is."
    return 0
  fi
  cp "$OPENCODE_PKG_PATH" "${OPENCODE_PKG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  mv "${OPENCODE_PKG_PATH}.tmp" "$OPENCODE_PKG_PATH"
  ok "Removed @opentui/{core,solid} from $OPENCODE_PKG_PATH (not needed at runtime)"
}

# --- Uninstall path ---
if [[ $UNINSTALL -eq 1 ]]; then
  log "Uninstalling cc-minimax-status"

  if [[ -f "$SCRIPT_PATH" ]]; then
    rm -f "$SCRIPT_PATH"
    ok "Removed $SCRIPT_PATH"
  else
    log "$SCRIPT_PATH not present, nothing to remove."
  fi

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
  else
    log "$SETTINGS_PATH not present, nothing to remove."
  fi

  for p in "$PLUGIN_PATH" "$COMMAND_PATH"; do
    if [[ -f "$p" ]]; then
      rm -f "$p"
      ok "Removed $p"
    else
      log "$p not present, nothing to remove."
    fi
  done

  for f in "$TUI_JSONC" "$TUI_JSON"; do
    if [[ -f "$f" ]] && grep -qE 'minimax-status\.tsx' "$f" 2>/dev/null; then
      backup="${f}.bak.$(date +%Y%m%d%H%M%S)"
      cp "$f" "$backup"
      if jq '.plugin = ((.plugin // []) | map(select(
        (type == "string" and (contains("minimax-status.tsx") | not)) or
        (type == "array"  and (.[0] | type == "string" and (contains("minimax-status.tsx") | not)))
      )))' "$f" > "${f}.tmp" 2>/dev/null && mv "${f}.tmp" "$f"; then
        ok "Removed plugin entry from $f (backup: $backup)"
      fi
    fi
  done

  strip_legacy_server_plugin_entry
  drop_legacy_opentui_deps

  printf '\nRestart Claude Code and/or opencode to apply.\n'
  exit 0
fi

# --- Install path ---
log "Installing cc-minimax-status"

# 1. Ensure ~/.claude exists (always, even in --opencode-only — we still
#    need a place for statusline.sh so the opencode plugin can find it)
mkdir -p "$CLAUDE_DIR"

# 2. Download the statusline script (atomic write via .tmp + mv)
if [[ -f "$SCRIPT_PATH" && $FORCE -eq 0 ]]; then
  warn "$SCRIPT_PATH already exists; skipping download. Use --force to overwrite."
else
  if ! download "${RAW_BASE}/${SCRIPT_NAME}" "$SCRIPT_PATH" "statusline.sh"; then
    exit 1
  fi
  chmod +x "$SCRIPT_PATH"
  ok "Installed $SCRIPT_NAME -> $SCRIPT_PATH"
fi

# 3. Claude Code: patch settings.json
if [[ $INSTALL_CLAUDE -eq 1 ]]; then
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

  if ! jq -e '.statusLine.command' "$SETTINGS_PATH" >/dev/null 2>&1; then
    err "Post-install verification failed: statusLine.command is missing from $SETTINGS_PATH"
    exit 1
  fi
else
  log "Skipping Claude Code (--opencode-only)"
fi

# 4. opencode: install the TUI plugin + slash command. The plugin
#    belongs in tui.json[c] (not opencode.json[c]) — the TUI runtime
#    reads tui.json[c] for `plugin:` via TuiConfig.get(), not the
#    server config. The auto-loader glob (`{plugin,plugins}/*.{ts,js}`)
#    doesn't include .tsx, so we register explicitly.
if [[ $INSTALL_OPENCODE -eq 1 ]]; then
  if [[ ! -d "$OPENCODE_DIR" ]]; then
    warn "$OPENCODE_DIR not found; skipping opencode install."
    warn "(Install opencode first, or run with --claude-only to silence this.)"
  else
    mkdir -p "$OPENCODE_PLUGINS_DIR" "$OPENCODE_COMMANDS_DIR"

    strip_legacy_server_plugin_entry
    drop_legacy_opentui_deps

    if [[ -f "$PLUGIN_PATH" && $FORCE -eq 0 ]]; then
      warn "$PLUGIN_PATH already exists; skipping download. Use --force to overwrite."
    else
      if ! download "${RAW_BASE}/opencode/${PLUGIN_NAME}" "$PLUGIN_PATH" "opencode TUI plugin"; then
        exit 1
      fi
      ok "Installed $PLUGIN_NAME -> $PLUGIN_PATH"
    fi

    if [[ -f "$COMMAND_PATH" && $FORCE -eq 0 ]]; then
      warn "$COMMAND_PATH already exists; skipping download. Use --force to overwrite."
    else
      if ! download "${RAW_BASE}/opencode/commands/${COMMAND_NAME}" "$COMMAND_PATH" "/minimax slash command"; then
        exit 1
      fi
      ok "Installed $COMMAND_NAME -> $COMMAND_PATH"
    fi

    # Register the plugin in tui.json[c]. Idempotent: skips if the
    # entry is already there.
    TUI_TARGET="$TUI_JSONC"
    [[ ! -f "$TUI_JSONC" && -f "$TUI_JSON" ]] && TUI_TARGET="$TUI_JSON"
    if [[ -f "$TUI_TARGET" ]] && grep -qE 'minimax-status\.tsx' "$TUI_TARGET" 2>/dev/null; then
      log "$TUI_TARGET already references minimax-status.tsx."
    else
      tui_tmp="$(mktemp)"
      if [[ -f "$TUI_TARGET" ]]; then
        cp "$TUI_TARGET" "${TUI_TARGET}.bak.$(date +%Y%m%d%H%M%S)"
        if jq --arg schema 'https://opencode.ai/tui.json' \
             '. + {($schema: ($schema // "https://opencode.ai/tui.json"))} | .plugin = ((.plugin // []) + ["./plugins/minimax-status.tsx"] | unique)' \
             "$TUI_TARGET" > "$tui_tmp" 2>/dev/null; then
          mv "$tui_tmp" "$TUI_TARGET"
          ok "Patched $TUI_TARGET (added TUI plugin entry)"
        else
          err "Failed to update $TUI_TARGET — your file is unchanged."
          err "Add manually: \"plugin\": [\"./plugins/minimax-status.tsx\"]"
          rm -f "$tui_tmp"
        fi
      else
        cat > "$TUI_TARGET" <<EOF
{
  "\$schema": "https://opencode.ai/tui.json",
  "plugin": ["./plugins/minimax-status.tsx"]
}
EOF
        ok "Created $TUI_TARGET (registered TUI plugin)"
      fi
    fi
  fi
else
  log "Skipping opencode (--claude-only)"
fi

printf '\n'
ok "Install complete."
printf '\n'
if [[ $INSTALL_CLAUDE -eq 1 ]]; then
  printf '   \033[1mClaude Code:\033[0m restart Claude Code to see the status line.\n'
fi
if [[ $INSTALL_OPENCODE -eq 1 && -d "$OPENCODE_DIR" ]]; then
  printf '   \033[1mopencode:\033[0m restart opencode. A new "MiniMax" row should appear\n'
  printf '   in the sidebar (between Context and MCP), refreshing every ~30s.\n'
  printf '   Also try \033[1m/minimax\033[0m in chat for an on-demand refresh.\n'
  printf '   The script is read from ~/.claude/statusline.sh\n'
  printf '   (override with \$OPENCODE_MINIMAX_SCRIPT).\n'
fi
printf '\n'
printf '     MiniMax: 100%% / 5h (39m)\n\n'
printf '   Need to uninstall?  Re-run with --uninstall.\n'
