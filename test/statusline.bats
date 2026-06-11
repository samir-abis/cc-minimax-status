#!/usr/bin/env bats
# Pure-logic unit tests for statusline.sh.
#
# The script self-sources: when sourced (BASH_SOURCE[0] != $0), the pure
# helpers below are exposed as functions. When run directly, main() executes.
# We `source` the script in setup() so each test can call the helpers.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../statusline.sh"
  # shellcheck disable=SC1090
  source "$SCRIPT"
}

# ---------- ms_to_human ----------

@test "ms_to_human: 0ms -> '0m'" {
  [ "$(ms_to_human 0)" = "0m" ]
}

@test "ms_to_human: 30s rounds down to '0m'" {
  [ "$(ms_to_human 30000)" = "0m" ]
}

@test "ms_to_human: 1m exact -> '1m'" {
  [ "$(ms_to_human 60000)" = "1m" ]
}

@test "ms_to_human: 59m -> '59m'" {
  [ "$(ms_to_human $((59 * 60000)))" = "59m" ]
}

@test "ms_to_human: 1h exact -> '1h'" {
  [ "$(ms_to_human 3600000)" = "1h" ]
}

@test "ms_to_human: 1h 1m -> '1h 1m'" {
  [ "$(ms_to_human 3660000)" = "1h 1m" ]
}

@test "ms_to_human: 2h 2m -> '2h 2m'" {
  [ "$(ms_to_human 7320000)" = "2h 2m" ]
}

@test "ms_to_human: 25h drops the zero-minute segment" {
  [ "$(ms_to_human $((25 * 3600000)))" = "25h" ]
}

# ---------- color_for ----------

@test "color_for: 0 -> green" {
  [ "$(color_for 0)" = $'\033[32m' ]
}

@test "color_for: 39 -> green (just under threshold)" {
  [ "$(color_for 39)" = $'\033[32m' ]
}

@test "color_for: 40 -> yellow (threshold)" {
  [ "$(color_for 40)" = $'\033[33m' ]
}

@test "color_for: 59 -> yellow (just under red threshold)" {
  [ "$(color_for 59)" = $'\033[33m' ]
}

@test "color_for: 60 -> red (threshold)" {
  [ "$(color_for 60)" = $'\033[31m' ]
}

@test "color_for: 100 -> red" {
  [ "$(color_for 100)" = $'\033[31m' ]
}

# ---------- pick_best_slot ----------

@test "pick_best_slot: picks the slot with the LOWEST remaining_percent" {
  json='{"model_remains":[
    {"model_name":"video","current_interval_remaining_percent":100,"remains_time":1000},
    {"model_name":"general","current_interval_remaining_percent":33,"remains_time":5000}
  ]}'
  result=$(printf '%s' "$json" | pick_best_slot)
  [ "$(printf '%s' "$result" | jq -r '.model_name')" = "general" ]
}

@test "pick_best_slot: skips slots with null remaining_percent" {
  json='{"model_remains":[
    {"model_name":"video","current_interval_remaining_percent":null,"remains_time":1000},
    {"model_name":"general","current_interval_remaining_percent":33,"remains_time":5000}
  ]}'
  result=$(printf '%s' "$json" | pick_best_slot)
  [ "$(printf '%s' "$result" | jq -r '.model_name')" = "general" ]
}

@test "pick_best_slot: returns non-zero when every percent is null" {
  json='{"model_remains":[
    {"model_name":"a","current_interval_remaining_percent":null,"remains_time":1},
    {"model_name":"b","current_interval_remaining_percent":null,"remains_time":1}
  ]}'
  run bash -c "source $SCRIPT; printf '%s' '$json' | pick_best_slot"
  [ "$status" -ne 0 ]
}

@test "pick_best_slot: returns non-zero when model_remains is empty" {
  run bash -c "source $SCRIPT; printf '%s' '{\"model_remains\":[]}' | pick_best_slot"
  [ "$status" -ne 0 ]
}

# ---------- format_slot ----------

@test "format_slot: known entry -> '67% / 5h (1h 25m)'" {
  entry='{"current_interval_remaining_percent":33,"remains_time":5124834}'
  [ "$(format_slot "$entry")" = "67% / 5h (1h 25m)" ]
}

@test "format_slot: floors fractional remaining_percent (34.5 -> used 66)" {
  entry='{"current_interval_remaining_percent":34.5,"remains_time":60000}'
  [ "$(format_slot "$entry")" = "66% / 5h (1m)" ]
}

@test "format_slot: 100% remaining -> used 0%" {
  entry='{"current_interval_remaining_percent":100,"remains_time":3600000}'
  [ "$(format_slot "$entry")" = "0% / 5h (1h)" ]
}

# ---------- format_status (n/a fallbacks) ----------

@test "format_status: real-shaped response produces a percent / 5h string" {
  json='{"model_remains":[
    {"model_name":"general","current_interval_remaining_percent":50,"remains_time":3600000},
    {"model_name":"video","current_interval_remaining_percent":100,"remains_time":3600000}
  ]}'
  [ "$(format_status "$json")" = "50% / 5h (1h)" ]
}

@test "format_status: empty model_remains -> 'n/a'" {
  [ "$(format_status '{"model_remains":[]}')" = "n/a" ]
}

@test "format_status: all-null percents -> 'n/a'" {
  json='{"model_remains":[
    {"model_name":"a","current_interval_remaining_percent":null,"remains_time":1},
    {"model_name":"b","current_interval_remaining_percent":null,"remains_time":1}
  ]}'
  [ "$(format_status "$json")" = "n/a" ]
}

@test "format_status: malformed JSON -> 'n/a'" {
  [ "$(format_status 'not json at all')" = "n/a" ]
}

@test "format_status: missing model_remains key -> 'n/a'" {
  [ "$(format_status '{"other":[]}')" = "n/a" ]
}

# ---------- URL sanity: the script must point at the token-plan endpoint ----------

@test "script URL targets the minimax.io token_plan/remains endpoint" {
  grep -qE 'https://(www|api)\.minimax\.io/v1/token_plan/remains' "$SCRIPT"
}

# ---------- pick_token: env-var precedence ----------

@test "pick_token: empty when no token vars are set" {
  unset MINIMAX_TOKEN_VAR MINIMAX_API_KEY ANTHROPIC_AUTH_TOKEN
  [ -z "$(pick_token)" ]
}

@test "pick_token: MINIMAX_API_KEY wins over ANTHROPIC_AUTH_TOKEN" {
  MINIMAX_API_KEY="from_minimax" ANTHROPIC_AUTH_TOKEN="from_claude" \
    run bash -c "source $SCRIPT; pick_token"
  [ "$output" = "from_minimax" ]
}

@test "pick_token: ANTHROPIC_AUTH_TOKEN is the back-compat fallback" {
  unset MINIMAX_API_KEY
  ANTHROPIC_AUTH_TOKEN="from_claude" \
    run bash -c "source $SCRIPT; pick_token"
  [ "$output" = "from_claude" ]
}

@test "pick_token: MINIMAX_TOKEN_VAR routes to the named var (ANTHROPIC_API_KEY)" {
  MINIMAX_TOKEN_VAR="ANTHROPIC_API_KEY" ANTHROPIC_API_KEY="via_indirect" \
    run bash -c "source $SCRIPT; pick_token"
  [ "$output" = "via_indirect" ]
}

@test "pick_token: MINIMAX_TOKEN_VAR overrides the default chain" {
  MINIMAX_TOKEN_VAR="CUSTOM" MINIMAX_API_KEY="from_minimax" CUSTOM="from_custom" \
    run bash -c "source $SCRIPT; pick_token"
  [ "$output" = "from_custom" ]
}

@test "pick_token: MINIMAX_TOKEN_VAR with an unset target returns empty" {
  unset MY_OTHER_VAR
  MINIMAX_TOKEN_VAR="MY_OTHER_VAR" \
    run bash -c "source $SCRIPT; pick_token"
  [ -z "$output" ]
}

# ---------- opencode plugin sanity ----------

PLUGIN="$BATS_TEST_DIRNAME/../opencode/minimax-status.tsx"

@test "opencode plugin file is present" {
  [ -f "$PLUGIN" ]
}

@test "opencode plugin is a .tsx (uses JSX) — no leftover .ts from the old toast plugin" {
  [ -f "$PLUGIN" ]
  [ "${PLUGIN##*.}" = "tsx" ]
  [ ! -f "$BATS_TEST_DIRNAME/../opencode/minimax-status.ts" ]
}

@test "opencode plugin uses the @opentui/solid JSX runtime" {
  grep -q '@jsxImportSource @opentui/solid' "$PLUGIN"
}

@test "opencode plugin declares the official TuiPlugin type" {
  grep -q 'import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"' "$PLUGIN"
}

@test "opencode plugin registers a sidebar_content slot" {
  grep -q 'api.slots.register' "$PLUGIN"
  grep -q 'sidebar_content' "$PLUGIN"
}

@test "opencode plugin registers at order 150 (between context 100 and mcp 200)" {
  grep -qE 'order:\s*150' "$PLUGIN"
}

@test "opencode plugin matches built-in sidebar shape (no padding, bold title, plain value)" {
  # Built-in plugins (Context, MCP) use a bare outer <box> with no padding,
  # a <b>Title</b> first text, then plain <text fg=textMuted> rows.
  # Our plugin should match that exactly so rows align in the sidebar.
  ! grep -qE 'paddingLeft|paddingRight' "$PLUGIN"
  grep -q '<b>MiniMax</b>' "$PLUGIN"
  grep -q 'theme().textMuted' "$PLUGIN"
}

@test "opencode plugin does not use semantic colors (no error/warning/success theming)" {
  # The sidebar JSX renderer doesn't interpret ANSI escape codes, so
  # coloring the percent from @opentui/solid wasn't useful — and
  # leaking the script's raw \033[31m... through caused the value
  # to render as literal "[31m" / "[0m" bytes. We now render the
  # whole value in textMuted to match Context / MCP / LSP.
  ! grep -qE 'theme\(\)\.(error|warning|success)\b' "$PLUGIN"
}

@test "opencode plugin sanitizes the script output (strips ANSI and 'MiniMax: ' prefix)" {
  grep -q 'function sanitize' "$PLUGIN"
  # The ANSI SGR regex source. grep -F so the backslash is literal.
  grep -qF 'x1b\[[0-9;]*m' "$PLUGIN"
  # The "MiniMax:" prefix strip is case-insensitive (matches the script).
  grep -qiE 'MiniMax:\s*\\?' "$PLUGIN"
}

@test "opencode plugin default script path is ~/.claude/statusline.sh" {
  grep -q '\.claude.*statusline\.sh' "$PLUGIN"
}

@test "opencode plugin default refresh interval is 30s" {
  grep -q 'OPENCODE_MINIMAX_REFRESH_MS ?? 30_000' "$PLUGIN"
}

@test "opencode plugin uses Bun.spawn to run the script (TUI plugin, no $ from input)" {
  grep -q 'Bun.spawn' "$PLUGIN"
}

@test "opencode plugin registers a dispose hook to clear the timer" {
  grep -q 'api.lifecycle.onDispose' "$PLUGIN"
  grep -q 'clearInterval' "$PLUGIN"
}

@test "opencode plugin exposes OPENCODE_MINIMAX_TOKEN_VAR knob" {
  grep -q 'OPENCODE_MINIMAX_TOKEN_VAR' "$PLUGIN"
  grep -q 'MINIMAX_TOKEN_VAR' "$PLUGIN"
}

# ---------- installer: tui.jsonc registration ----------

@test "JS installer registers minimax-status.tsx in tui.jsonc (NOT opencode.jsonc)" {
  grep -q 'ensureTuiPluginEntry' "$BATS_TEST_DIRNAME/../bin/cc-minimax-status.js"
  grep -q 'TUI_JSONC' "$BATS_TEST_DIRNAME/../bin/cc-minimax-status.js"
  grep -q '\./plugins/minimax-status\.tsx' "$BATS_TEST_DIRNAME/../bin/cc-minimax-status.js"
}

@test "JS installer strips any stale minimax-status entry from opencode.jsonc" {
  grep -q 'stripLegacyServerPluginEntry' "$BATS_TEST_DIRNAME/../bin/cc-minimax-status.js"
  grep -q 'OPENCODE_JSONC' "$BATS_TEST_DIRNAME/../bin/cc-minimax-status.js"
}

@test "bash installer writes to tui.jsonc (the TUI config, not the server config)" {
  grep -q 'minimax-status\.tsx' "$BATS_TEST_DIRNAME/../install.sh"
  grep -q 'TUI_JSONC' "$BATS_TEST_DIRNAME/../install.sh"
  grep -q 'strip_legacy_server_plugin_entry' "$BATS_TEST_DIRNAME/../install.sh"
  grep -q 'opencode\.ai/tui\.json' "$BATS_TEST_DIRNAME/../install.sh"
}

# ---------- /minimax slash command ----------

@test "/minimax slash command file is present" {
  [ -f "$BATS_TEST_DIRNAME/../opencode/commands/minimax.md" ]
  head -1 "$BATS_TEST_DIRNAME/../opencode/commands/minimax.md" | grep -q '^---$'
  grep -q 'description:' "$BATS_TEST_DIRNAME/../opencode/commands/minimax.md"
  grep -q '!`bash ~/.claude/statusline.sh`' "$BATS_TEST_DIRNAME/../opencode/commands/minimax.md"
}
