#!/usr/bin/env bats
# scripts/tests/track.bats

setup() {
  export TIMETRACK_DATA_DIR="$(mktemp -d)"
  export CACHE_FILE="$TIMETRACK_DATA_DIR/ticket-cache.json"
  TRACK="$BATS_TEST_DIRNAME/../scripts/track"
}

teardown() {
  rm -rf "$TIMETRACK_DATA_DIR"
}

@test "no args prints usage and exits 1" {
  run bash "$TRACK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "unknown subcommand prints usage and exits 1" {
  run bash "$TRACK" foobar
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "data dir is created on first run" {
  local dir
  dir="$(mktemp -d)"
  rm -rf "$dir"
  TIMETRACK_DATA_DIR="$dir" run bash "$TRACK"
  [ -d "$dir" ]
}

load_track() {
  source "$BATS_TEST_DIRNAME/../scripts/track"
  init_data_dir  # files aren't created when sourcing (only when executing)
}

@test "get_open_session returns empty when file is empty" {
  load_track
  result=$(get_open_session)
  [ -z "$result" ]
}

@test "clock_in appends an i line" {
  load_track
  clock_in "Shipix:Backend Dev:SHIP-123" "2026-03-19T09:00:00"
  last=$(tail -1 "$TIMECLOCK_FILE")
  [ "$last" = "i 2026-03-19 09:00:00 Shipix:Backend Dev:SHIP-123" ]
}

@test "get_open_session returns account after clock_in" {
  load_track
  clock_in "Shipix:Backend Dev:SHIP-123" "2026-03-19T09:00:00"
  result=$(get_open_session)
  [ "$result" = "Shipix:Backend Dev:SHIP-123" ]
}

@test "clock_out appends an o line and clears open session" {
  load_track
  clock_in "Shipix:Backend Dev:SHIP-123" "2026-03-19T09:00:00"
  clock_out "2026-03-19T10:30:00"
  result=$(get_open_session)
  [ -z "$result" ]
  last=$(tail -1 "$TIMECLOCK_FILE")
  [ "$last" = "o 2026-03-19 10:30:00" ]
}

@test "clock_out on zero-duration session removes the i line" {
  load_track
  clock_in "Shipix:Backend Dev:SHIP-123" "2026-03-19T09:00:00"
  clock_out "2026-03-19T09:00:00"
  [ ! -s "$TIMECLOCK_FILE" ]
}

@test "track stop with no active session exits 0 with message" {
  run bash "$TRACK" stop
  [ "$status" -eq 0 ]
  [ "$output" = "No active session." ]
}

@test "track stop clocks out an open session" {
  load_track
  clock_in "Shipix:Backend Dev:SHIP-123" "2026-03-19T09:00:00"
  run bash "$TRACK" stop
  [ "$status" -eq 0 ]
  [ "$output" = "Stopped: SHIP-123" ]
  open=$(get_open_session)
  [ -z "$open" ]
}

@test "track status with no active session exits 0 with message" {
  run bash "$TRACK" status
  [ "$status" -eq 0 ]
  [ "$output" = "No active session." ]
}

@test "track status shows ticket and elapsed time" {
  load_track
  local start
  start=$(date -d "90 minutes ago" "+%Y-%m-%dT%H:%M:%S")
  clock_in "Shipix:Backend Dev:SHIP-123" "$start"
  run bash "$TRACK" status
  [ "$status" -eq 0 ]
  [[ "$output" == "SHIP-123 ("*")"* ]]
}

@test "track TICKET starts a new session using cached client/project" {
  echo '{"SHIP-123":{"client":"Shipix","project":"Backend Dev"}}' > "$CACHE_FILE"
  run bash "$TRACK" SHIP-123
  [ "$status" -eq 0 ]
  load_track
  open=$(get_open_session)
  [ "$open" = "Shipix:Backend Dev:SHIP-123" ]
}

@test "track TICKET closes previous session before starting new one" {
  echo '{"SHIP-123":{"client":"Shipix","project":"Backend Dev"},"QUIC-456":{"client":"Quicargo","project":"Platform"}}' > "$CACHE_FILE"
  load_track
  clock_in "Shipix:Backend Dev:SHIP-123" "2026-03-19T09:00:00"
  run bash "$TRACK" QUIC-456
  [ "$status" -eq 0 ]
  open=$(get_open_session)
  [ "$open" = "Quicargo:Platform:QUIC-456" ]
}

@test "invalid ticket format exits 1" {
  run bash "$TRACK" not-a-ticket
  [ "$status" -eq 1 ]
}

@test "validate_jira_env fails with missing var named in message" {
  load_track
  unset JIRA_BASE_URL 2>/dev/null || true
  run validate_jira_env
  [ "$status" -eq 1 ]
  [[ "$output" == *"JIRA_BASE_URL"* ]]
}

@test "get_ticket_info returns cached data without API call" {
  load_track
  echo '{"SHIP-123":{"client":"Shipix","project":"Backend Dev"}}' > "$CACHE_FILE"
  result=$(get_ticket_info "SHIP-123")
  [ "$(echo "$result" | jq -r '.client')" = "Shipix" ]
}

@test "fetch_from_jira parses client and project" {
  load_track
  export JIRA_BASE_URL="https://test.atlassian.net"
  export JIRA_EMAIL="u@example.com"
  export JIRA_API_TOKEN="tok"
  export JIRA_CLIENT_FIELD="customfield_10001"
  export JIRA_PROJECT_FIELD="customfield_10002"

  local mock_dir
  mock_dir="$(mktemp -d)"
  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
# Parse -o argument to get output file
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
echo '{"fields":{"customfield_10001":{"value":"Shipix"},"customfield_10002":{"value":"Backend Dev"}}}' > "$output_file"
echo "200"
MOCK
  chmod +x "$mock_dir/curl"

  PATH="$mock_dir:$PATH" result=$(fetch_from_jira "SHIP-123")
  [ "$(echo "$result" | jq -r '.client')" = "Shipix" ]
  [ "$(echo "$result" | jq -r '.project')" = "Backend Dev" ]
  rm -rf "$mock_dir"
}

@test "track refresh updates cache entry" {
  export JIRA_BASE_URL="https://test.atlassian.net"
  export JIRA_EMAIL="u@example.com"
  export JIRA_API_TOKEN="tok"
  export JIRA_CLIENT_FIELD="customfield_10001"
  export JIRA_PROJECT_FIELD="customfield_10002"

  echo '{"SHIP-123":{"client":"OldClient","project":"OldProject"}}' > "$CACHE_FILE"

  local mock_dir
  mock_dir="$(mktemp -d)"
  cat > "$mock_dir/curl" <<'MOCK'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output_file="$2"; shift 2 ;;
    *) shift ;;
  esac
done
echo '{"fields":{"customfield_10001":{"value":"Shipix"},"customfield_10002":{"value":"Backend Dev"}}}' > "$output_file"
echo "200"
MOCK
  chmod +x "$mock_dir/curl"

  PATH="$mock_dir:$PATH" run bash "$TRACK" refresh SHIP-123
  [ "$status" -eq 0 ]
  load_track
  [ "$(jq -r '.["SHIP-123"].client' "$CACHE_FILE")" = "Shipix" ]
  rm -rf "$mock_dir"
}

@test "track refresh with no ticket arg exits 1" {
  run bash "$TRACK" refresh
  [ "$status" -eq 1 ]
}

@test "track report delegates to hledger for given date" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:Backend Dev:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"

  run bash "$TRACK" report 2026-03-19
  [ "$status" -eq 0 ]
  [[ "$output" == *"SHIP-123"* ]]
}

@test "track report defaults to today without error" {
  run bash "$TRACK" report
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "track edit opens timeclock file with EDITOR" {
  local mock_dir called_with
  mock_dir="$(mktemp -d)"
  called_with="$mock_dir/called_with"
  cat > "$mock_dir/nvim" <<MOCK
#!/usr/bin/env bash
echo "\$1" > "$called_with"
MOCK
  chmod +x "$mock_dir/nvim"

  EDITOR="$mock_dir/nvim" run bash "$TRACK" edit
  [ "$status" -eq 0 ]
  [ "$(cat "$called_with")" = "$TIMETRACK_DATA_DIR/time.timeclock" ]
  rm -rf "$mock_dir"
}
