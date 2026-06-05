#!/usr/bin/env bash
# Claude Code statusLine: MiniMax 5h quota.
#
# Fetches the 5h limit from the public /v1/token_plan/remains endpoint using
# the same API key that's wired up for Claude Code. Claude Code's own
# statusline already surfaces context-window usage, so we don't duplicate it.
#
# Output: "MiniMax: 47% / 5h (1h 29m)"

# ---------- 1. Fetch 5h quota from the public token-plan endpoint ----------
quota_str="n/a"
quota_pct=0

if [[ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
  response=$(curl -s --max-time 5 \
    -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    "https://www.minimax.io/v1/token_plan/remains" 2>/dev/null)

  # Pick the model slot with the LOWEST remaining_percent — that's the active
  # 5h limit (the "general" slot for chat/LLM usage; "video" is its own bucket
  # and tends to report 100% remaining).
  if echo "$response" | jq -e '.model_remains[0].current_interval_remaining_percent' >/dev/null 2>&1; then
    entry=$(echo "$response" | jq '
      .model_remains
      | map(select(.current_interval_remaining_percent != null))
      | min_by(.current_interval_remaining_percent)
    ')

    remaining_pct=$(echo "$entry" | jq '.current_interval_remaining_percent | floor')
    quota_pct=$((100 - remaining_pct))
    remains_ms=$(echo "$entry" | jq '.remains_time')

    # ms -> "Xh Ym" / "Xh" / "Ym" / "0m"
    total_min=$((remains_ms / 60000))
    h=$((total_min / 60))
    m=$((total_min % 60))
    if   [[ $h -gt 0 && $m -gt 0 ]]; then reset_str="${h}h ${m}m"
    elif [[ $h -gt 0 ]];              then reset_str="${h}h"
    elif [[ $m -gt 0 ]];              then reset_str="${m}m"
    else                                   reset_str="0m"
    fi

    quota_str="${quota_pct}% / 5h (${reset_str})"
  fi
fi

# ---------- 2. Color the percentage by threshold ----------
#   <40  -> green,  <60 -> yellow,  >=60 -> red
color_for() {
  local v=$1
  if   [[ $v -lt 40 ]]; then printf '\033[32m'   # green
  elif [[ $v -lt 60 ]]; then printf '\033[33m'   # yellow
  else                        printf '\033[31m'   # red
  fi
}
ansi_reset=$'\033[0m'

if [[ "$quota_str" != "n/a" ]]; then
  q_color=$(color_for "$quota_pct")
  quota_str_colored="${q_color}${quota_str}${ansi_reset}"
else
  quota_str_colored="$quota_str"
fi

# ---------- 3. Final output ----------
printf 'MiniMax: %s\n' "$quota_str_colored"
