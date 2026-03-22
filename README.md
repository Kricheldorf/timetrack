# timetrack

Built vibing with [Claude Code](https://claude.ai/code/family)

A CLI time tracker that logs work sessions to an [hledger](https://hledger.org/) timeclock file, with Jira integration for automatic client/project metadata.

## How it works

Each Jira ticket maps to an hledger account in the format `Client:Project:TICKET-123`. When you start tracking a ticket, the script fetches the client and project from Jira (caching the result locally) and writes clock-in/clock-out entries to a timeclock file. You can then use hledger to query and report on your time.

## Dependencies

- [hledger](https://hledger.org/) - Motive: I already use it for personal financial tracking
- [jq](https://jqlang.github.io/jq/)
- [curl](https://curl.se/)
- bash 4+ - Motive: Just for fun and getting more familiar with bash scripting

## Setup

1. Copy the example env file and fill in your values:

   ```sh
   cp .env.example .env
   ```

2. Configure your Jira connection in `.env`:

   ```
   JIRA_BASE_URL="https://yourcompany.atlassian.net"
   JIRA_EMAIL="your@email.com"
   JIRA_API_TOKEN="your-api-token"
   JIRA_CLIENT_FIELD="customfield_10080"
   JIRA_PROJECT_FIELD="customfield_10081"
   ```

   To discover the correct custom field IDs, run `track fields TICKET-123` with a known ticket.

## Usage

```sh
track SHIP-123          # Start tracking a ticket
track                   # Start tracking ticket detected from git branch name
track stop              # Stop the current session
track status            # Show current ticket and elapsed time
track report            # Show hledger report for today
track report 2026-03-19 # Show hledger report for a specific date
track edit              # Open timeclock file in $EDITOR
track refresh SHIP-123  # Re-fetch Jira metadata for a ticket
track fields SHIP-123   # List Jira field names/IDs for a ticket
track shipix            # Start tracking using an alias (see Aliases below)
track completions fish  # Output fish shell completions to stdout
track completions zsh   # Output zsh shell completions to stdout
```

Running `track` with no arguments extracts a ticket ID from the current git branch name (supports `SA-*` and `QDX-*` prefixes).

Starting a new ticket or alias automatically stops any currently running session.

## Aliases

Aliases let you quickly start tracking for known client/project combos without a Jira ticket (e.g. for meetings). Define them in `.env` via `TRACK_ALIASES`, semicolon-separated:

```bash
TRACK_ALIASES="shipix=Shipix:General;quicargo=Quicargo:Maintenance;action=IDL Action:MVP 1"
```

Then run `track shipix` to clock in as `Shipix:General:shipix`.

## Shell Completions

Generate completion scripts with `track completions`:

```sh
# Fish
track completions fish > ~/.config/fish/completions/track.fish

# Zsh
track completions zsh > "${fpath[1]}/_track"
```

Completions include all subcommands plus any configured aliases.

## Data

Time data is stored in `~/.local/share/timetrack/` by default (override with `TIMETRACK_DATA_DIR`):

- `time.timeclock` - hledger timeclock file
- `ticket-cache.json` - cached Jira ticket metadata

## Tests

Tests use [bats](https://github.com/bats-core/bats-core):

```sh
bats tests/
```
