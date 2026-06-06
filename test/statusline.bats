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
