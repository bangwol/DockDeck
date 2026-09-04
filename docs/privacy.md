# Privacy and data sources

DockDeck is local-first. It does not read browser cookies, browser credential
stores, or private web endpoints. It observes only the occurrence of a global
mouse-down to collapse a focused terminal; it does not record keystrokes,
pointer coordinates, or clicked content.

## Module boundaries

| Module or provider | Source | Local behavior |
| --- | --- | --- |
| Codex | `codex app-server` using `account/rateLimits/read` | Runs the locally installed official Codex CLI as a long-lived subprocess. |
| Claude | Official Claude Code `/usage`; optional status-line JSON | Automatic mode briefly launches the signed-in local CLI in safe mode, captures bounded usage text in memory, then exits. Status Line Only stores only `rate_limits` and an observation timestamp in a local cache. DockDeck never reads Claude OAuth credentials. |
| System Stats | macOS host, file-system, routing, and `ProcessInfo` APIs; optional validated local Stats SMC tool | Samples selected CPU, memory, disk, network-counter, and temperature values locally. Trends stay in memory for at most 15 minutes. |
| Service Monitor | User-configured HTTPS or local HTTP URLs | Sends cookie-free `HEAD` requests with a byte-range `GET` fallback. Common URL credential fields are rejected before local storage; recent latency stays in memory for at most 15 minutes. |
| Weather | Open-Meteo forecast and geocoding APIs | Sends searches and selected coordinates over HTTPS only while used, and stores the selected city locally. |
| Schedule | Apple EventKit | Reads selected calendars, safe conference links, and optional due Reminders after separate explicit permissions. It never saves, edits, logs, or uploads items. |
| World Clock | macOS time-zone database | Formats time locally and stops its timer while disabled. |
| Battery | macOS IOKit | Reads the internal power source locally without battery identifiers or serial numbers. |
| Network | macOS routing and Network frameworks | Reads primary-interface byte counters and connection properties without inspecting traffic, addresses, or destinations. |
| Project Pulse | Local `git`; authenticated `gh` REST, GraphQL, and optional Actions calls | Stores a selected local path, GitHub view, or `owner/repository`. Parsed summaries stay in memory; command output and GitHub tokens are never stored. |
| GitHub Inbox | Authenticated `gh` notifications and optional Actions calls | Stores only an optional `owner/repository`. Bounded message previews and counts stay in memory; authentication remains owned by GitHub CLI. |
| Docker | Local Docker CLI and engine socket | Runs read-only `ps` and `stats` commands. Output stays in memory and Docker credentials are not read. |
| Custom Tile | User-selected executable or macOS Shortcut | Stores its path, arguments, or Shortcut name. Bounded output stays in memory; the trusted source runs with the user's permissions. |
| Focus Timer | Local countdown state | Stores phase, deadline, and remaining duration only when timer state changes. |
| Notifications | macOS UserNotifications | Evaluates enabled rules locally and sends no notification data to an external service. |

Disabled modules stop their timers, observers, network requests, and subprocesses.
Read-only modules suspend while the display or login session is inactive. Low
Power Mode and serious thermal pressure reduce eligible refresh rates.

## Local files and credentials

DockDeck stores module settings in macOS preferences. Terminal state and Usage
cache locations are documented in the [Terminal](modules/terminal.md#settings-and-local-files)
and [Usage](modules/usage.md#local-files-and-process-boundaries) guides.

Authentication remains with each official CLI. DockDeck neither copies nor
persists Codex, Claude, GitHub, or Docker credentials. Diagnostic reports use an
allowlist and omit paths, URLs, account identifiers, command output, and tokens.

## Network access

Network work is opt-in by module. Weather contacts Open-Meteo, Service Monitor
contacts only configured endpoints, and GitHub modules invoke authenticated
`gh` commands. Schedule, World Clock, Battery, Network counters, Focus Timer,
and the default System Stats metrics do not contact an external service.

See each [module guide](README.md#module-guides) for request cadence, retained
state, permissions, and provider-specific limits.
