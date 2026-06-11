#!/usr/bin/env bash
# Claude Code statusLine: MiniMax 5h quota.
#
# Fetches the 5h limit from the public /v1/token_plan/remains endpoint using
# the same API key that's wired up for Claude Code. Claude Code's own
# statusline already surfaces context-window usage, so we don't duplicate it.
#
# Output: "MiniMax: 47% / 5h (1h 29m)"
#
# When sourced (not executed), the pure helpers below are exposed for tests;
# when run directly, main() is invoked.

# ---------- pure helpers (safe to call from tests via `source`) ----------

# Convert a duration in ms to "Xh Ym" / "Xh" / "Ym" / "0m". No trailing newline.
ms_to_human() {
  local ms=$1 total_min h m
  total_min=$((ms / 60000))
  h=$((total_min / 60))
  m=$((total_min % 60))
  if   [[ $h -gt 0 && $m -gt 0 ]]; then printf '%dh %dm' "$h" "$m"
  elif [[ $h -gt 0 ]];              then printf '%dh' "$h"
  elif [[ $m -gt 0 ]];              then printf '%dm' "$m"
  else                                   printf '0m'
  fi
}

# Return an ANSI color escape for a used% value.
#   <40  -> green,  <60 -> yellow,  >=60 -> red
color_for() {
  local v=$1
  if   [[ $v -lt 40 ]]; then printf '\033[32m'
  elif [[ $v -lt 60 ]]; then printf '\033[33m'
  else                        printf '\033[31m'
  fi
}

# Pick the model slot with the LOWEST remaining_percent (skip nulls).
# Reads JSON on stdin. Returns non-zero if no usable slot.
pick_best_slot() {
  jq -e '
    .model_remains
    | map(select(.current_interval_remaining_percent != null))
    | min_by(.current_interval_remaining_percent)
  '
}

# Format a single model-slot entry into "X% / 5h (Ym)". No trailing newline.
format_slot() {
  local entry=$1 remaining_pct quota_pct remains_ms reset_str
  remaining_pct=$(printf '%s' "$entry" | jq '.current_interval_remaining_percent | floor')
  quota_pct=$((100 - remaining_pct))
  remains_ms=$(printf '%s' "$entry" | jq '.remains_time')
  reset_str=$(ms_to_human "$remains_ms")
  printf '%s%% / 5h (%s)' "$quota_pct" "$reset_str"
}

# Format an API response into the status string. No trailing newline.
# Echoes "n/a" on any failure (no usable slot, malformed JSON, etc.).
format_status() {
  local json=$1 entry
  if entry=$(printf '%s' "$json" | pick_best_slot); then
    format_slot "$entry"
  else
    printf 'n/a'
  fi
}

# Pick the bearer token from the env, in priority order:
#   1. $MINIMAX_TOKEN_VAR is set -> read ${!MINIMAX_TOKEN_VAR}
#      (lets a wrapper like the opencode plugin route to any name)
#   2. else $MINIMAX_API_KEY  (recommended for opencode users)
#   3. else $ANTHROPIC_AUTH_TOKEN  (Claude Code convention, back-compat)
# Echoes empty string if nothing is set.
pick_token() {
  if [[ -n "${MINIMAX_TOKEN_VAR:-}" ]]; then
    printf '%s' "${!MINIMAX_TOKEN_VAR:-}"
  else
    printf '%s' "${MINIMAX_API_KEY:-${ANTHROPIC_AUTH_TOKEN:-}}"
  fi
}

# ---------- main: runs only when this file is executed directly ----------

main() {
  local quota_str="n/a" quota_pct=0
  local token
  token=$(pick_token)

  if [[ -n "$token" ]]; then
    local response entry
    response=$(curl -s --max-time 5 \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      "https://www.minimax.io/v1/token_plan/remains" 2>/dev/null) || true

    if [[ -n "$response" ]] && entry=$(printf '%s' "$response" | pick_best_slot); then
      quota_str=$(format_slot "$entry")
      quota_pct=$((100 - $(printf '%s' "$entry" | jq '.current_interval_remaining_percent | floor')))
    fi
  fi

  local ansi_reset=$'\033[0m'
  if [[ "$quota_str" != "n/a" ]]; then
    local q_color
    q_color=$(color_for "$quota_pct")
    printf 'MiniMax: %s%s%s\n' "$q_color" "$quota_str" "$ansi_reset"
  else
    printf 'MiniMax: %s\n' "$quota_str"
  fi
}

# When sourced (e.g. by bats), do not run main. When executed, run it.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
