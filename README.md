# timetrack

A CLI time tracker that logs work sessions to an [hledger](https://hledger.org/) timeclock file, with Jira integration for automatic client/project metadata.

## How it works

Each Jira ticket maps to an hledger account in the format `Client:Project:TICKET-123`. When you start tracking a ticket, the script fetches the client and project from Jira (caching the result locally) and writes clock-in/clock-out entries to a timeclock file. You can then use hledger to query and report on your time.

## Dependencies

- [hledger](https://hledger.org/)
- [jq](https://jqlang.github.io/jq/)
- [curl](https://curl.se/)
- bash 4+

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
```

Running `track` with no arguments extracts a ticket ID from the current git branch name (supports `SA-*` and `QDX-*` prefixes).

Starting a new ticket automatically stops any currently running session.

## Data

Time data is stored in `~/.local/share/timetrack/` by default (override with `TIMETRACK_DATA_DIR`):

- `time.timeclock` - hledger timeclock file
- `ticket-cache.json` - cached Jira ticket metadata

## Tests

Tests use [bats](https://github.com/bats-core/bats-core):

```sh
bats tests/
```
