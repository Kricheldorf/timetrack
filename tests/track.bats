#!/usr/bin/env bats
# scripts/tests/track.bats

setup() {
  export TIMETRACK_DATA_DIR="$(mktemp -d)"
  export CACHE_FILE="$TIMETRACK_DATA_DIR/ticket-cache.json"
  TRACK="$BATS_TEST_DIRNAME/../bin/track"
  export TIMETRACK_ENV_FILE="/dev/null"
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
  source "$BATS_TEST_DIRNAME/../bin/track"
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

@test "ticket_from_branch extracts SA ticket from branch" {
  load_track
  git() { echo "SA-1440-task-description"; }
  export -f git
  result=$(ticket_from_branch)
  [ "$result" = "SA-1440" ]
}

@test "ticket_from_branch extracts ticket from feat/ prefix branch" {
  load_track
  git() { echo "feat/SA-1440-task-description"; }
  export -f git
  result=$(ticket_from_branch)
  [ "$result" = "SA-1440" ]
}

@test "ticket_from_branch extracts lowercase sa ticket and uppercases it" {
  load_track
  git() { echo "sa-1440-task-description"; }
  export -f git
  result=$(ticket_from_branch)
  [ "$result" = "SA-1440" ]
}

@test "ticket_from_branch extracts QDX ticket" {
  load_track
  git() { echo "qdx-99-some-feature"; }
  export -f git
  result=$(ticket_from_branch)
  [ "$result" = "QDX-99" ]
}

@test "ticket_from_branch returns empty for branch without ticket" {
  load_track
  git() { echo "main"; }
  export -f git
  result=$(ticket_from_branch)
  [ -z "$result" ]
}

@test "no args with ticket branch starts tracking" {
  echo '{"SA-1440":{"client":"ClientX","project":"ProjectY"}}' > "$CACHE_FILE"

  local mock_dir
  mock_dir="$(mktemp -d)"
  cat > "$mock_dir/git" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "rev-parse" ]]; then
  echo "feat/SA-1440-task-description"
else
  command git "$@"
fi
MOCK
  chmod +x "$mock_dir/git"

  PATH="$mock_dir:$PATH" run bash "$TRACK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tracking: SA-1440"* ]]
  rm -rf "$mock_dir"
}

@test "lowercase ticket arg is uppercased" {
  echo '{"SA-1440":{"client":"ClientX","project":"ProjectY"}}' > "$CACHE_FILE"
  run bash "$TRACK" sa-1440
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tracking: SA-1440"* ]]
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

## Alias tests

@test "track alias starts session with three-segment account" {
  load_track
  export TRACK_ALIASES="shipix=Shipix:General;quicargo=Quicargo:Maintenance"
  run bash "$TRACK" shipix
  [ "$status" -eq 0 ]
  [[ "$output" == *"Tracking: shipix"* ]]
  open=$(get_open_session)
  [ "$open" = "Shipix:General:shipix" ]
}

@test "track alias stops previous session before starting" {
  load_track
  export TRACK_ALIASES="shipix=Shipix:General;quicargo=Quicargo:Maintenance"
  clock_in "Shipix:General:shipix" "2026-03-19T09:00:00"
  run bash "$TRACK" quicargo
  [ "$status" -eq 0 ]
  [[ "$output" == *"Stopped: shipix"* ]]
  [[ "$output" == *"Tracking: quicargo"* ]]
  open=$(get_open_session)
  [ "$open" = "Quicargo:Maintenance:quicargo" ]
}

@test "track unknown alias exits 1" {
  export TRACK_ALIASES="shipix=Shipix:General"
  run bash "$TRACK" notanalias
  [ "$status" -eq 1 ]
}

@test "resolve_alias returns correct value" {
  load_track
  export TRACK_ALIASES="shipix=Shipix:General;action=IDL Action:MVP 1"
  result=$(resolve_alias "action")
  [ "$result" = "IDL Action:MVP 1" ]
}

@test "resolve_alias returns empty for unknown alias" {
  load_track
  export TRACK_ALIASES="shipix=Shipix:General"
  result=$(resolve_alias "nope")
  [ -z "$result" ]
}

@test "track status shows alias name for alias-based session" {
  load_track
  local start
  start=$(date -d "5 minutes ago" "+%Y-%m-%dT%H:%M:%S")
  clock_in "Shipix:General:shipix" "$start"
  run bash "$TRACK" status
  [ "$status" -eq 0 ]
  [[ "$output" == "shipix ("*")"* ]]
}

@test "track stop shows alias name for alias-based session" {
  load_track
  clock_in "Shipix:General:shipix" "2026-03-19T09:00:00"
  run bash "$TRACK" stop
  [ "$status" -eq 0 ]
  [ "$output" = "Stopped: shipix" ]
}

## Completions tests

@test "track completions fish outputs valid fish script" {
  export TRACK_ALIASES="shipix=Shipix:General;quicargo=Quicargo:Maintenance"
  run bash "$TRACK" completions fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -c track"* ]]
  [[ "$output" == *"shipix"* ]]
  [[ "$output" == *"quicargo"* ]]
}

@test "track completions zsh outputs valid zsh script" {
  export TRACK_ALIASES="shipix=Shipix:General;quicargo=Quicargo:Maintenance"
  run bash "$TRACK" completions zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"#compdef track"* ]]
  [[ "$output" == *"shipix"* ]]
  [[ "$output" == *"quicargo"* ]]
}

@test "track completions with unknown shell is a no-op" {
  run bash "$TRACK" completions powershell
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "track completions with no arg is a no-op" {
  run bash "$TRACK" completions
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

## Edit tests

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

## resolve_project_map tests

@test "resolve_project_map returns mapped value" {
  load_track
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General;Quicargo:Maintenance=Quicargo - Maintenance"
  result=$(resolve_project_map "Shipix:General")
  [ "$result" = "Shipix - General" ]
}

@test "resolve_project_map returns empty for unknown key" {
  load_track
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  result=$(resolve_project_map "Unknown:Project")
  [ -z "$result" ]
}

@test "resolve_project_map returns empty when env var unset" {
  load_track
  unset TRACK_PROJECT_MAP 2>/dev/null || true
  result=$(resolve_project_map "Shipix:General")
  [ -z "$result" ]
}

## CSV export tests

@test "track csv outputs header and rows for completed sessions" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  echo "i 2026-03-19 11:00:00 Shipix:General:SHIP-456" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 12:00:00" >> "$TIMECLOCK_FILE"
  export TRACK_CSV_DESCRIPTION="Coding and PR/Docs review"
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  local header
  header=$(echo "$output" | head -1)
  [ "$header" = '"date","start_time","end_time","project","description"' ]
  local row1
  row1=$(echo "$output" | sed -n '2p')
  [ "$row1" = '"2026-03-19","09:00:00","10:30:00","Shipix - General","Coding and PR/Docs review"' ]
  local row2
  row2=$(echo "$output" | sed -n '3p')
  [ "$row2" = '"2026-03-19","11:00:00","12:00:00","Shipix - General","Coding and PR/Docs review"' ]
}

@test "track csv skips entries already exported via .latest" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  echo "i 2026-03-19 11:00:00 Shipix:General:SHIP-456" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 12:00:00" >> "$TIMECLOCK_FILE"
  echo "2026-03-19T10:30:00" > "$TIMETRACK_DATA_DIR/.latest"
  export TRACK_CSV_DESCRIPTION="Working"
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  local lines
  lines=$(echo "$output" | wc -l)
  [ "$lines" -eq 2 ]
  [[ "$output" == *"11:00:00"* ]]
}

@test "track csv updates .latest after export" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  export TRACK_CSV_DESCRIPTION="Working"
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  [ -f "$TIMETRACK_DATA_DIR/.latest" ]
  [ "$(cat "$TIMETRACK_DATA_DIR/.latest")" = "2026-03-19T10:30:00" ]
}

@test "track csv with .latest equal to last entry shows no new entries" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  echo "2026-03-19T10:30:00" > "$TIMETRACK_DATA_DIR/.latest"
  export TRACK_CSV_DESCRIPTION="Working"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  # stdout should have no CSV rows (only stderr message)
  [[ "$output" == *"No new entries since last export."* ]]
}

@test "track csv resolves project names via TRACK_PROJECT_MAP" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  export TRACK_CSV_DESCRIPTION="Working"
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  [[ "$output" == *'"Shipix - General"'* ]]
}

@test "track csv warns and uses raw name for unmapped project" {
  load_track
  echo "i 2026-03-19 09:00:00 Unknown:Project:TICK-1" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  export TRACK_CSV_DESCRIPTION="Working"
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  [[ "$output" == *'"Unknown:Project"'* ]]
}

@test "track csv skips open session with warning" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 10:30:00" >> "$TIMECLOCK_FILE"
  echo "i 2026-03-19 11:00:00 Shipix:General:SHIP-456" >> "$TIMECLOCK_FILE"
  export TRACK_CSV_DESCRIPTION="Working"
  export TRACK_PROJECT_MAP="Shipix:General=Shipix - General"
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  # Should have header + 1 data row (the completed session)
  local stdout_lines
  stdout_lines=$(echo "$output" | grep -c '^"')
  [ "$stdout_lines" -eq 2 ]
}

@test "track csv on empty timeclock shows no new entries" {
  run bash "$TRACK" csv
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new entries since last export."* ]]
}

@test "track csv detects malformed timeclock with unpaired entry" {
  load_track
  echo "i 2026-03-19 09:00:00 Shipix:General:SHIP-123" >> "$TIMECLOCK_FILE"
  echo "i 2026-03-19 10:00:00 Shipix:General:SHIP-456" >> "$TIMECLOCK_FILE"
  echo "o 2026-03-19 11:00:00" >> "$TIMECLOCK_FILE"
  run bash "$TRACK" csv
  [ "$status" -eq 1 ]
  [[ "$output" == *"malformed timeclock"* ]]
}

@test "track completions fish includes csv" {
  run bash "$TRACK" completions fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"csv"* ]]
}
