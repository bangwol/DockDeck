# Contributing

## Build

```bash
swift build
swift test
.build/debug/DockDeck
```

## Project constraints

- Keep one app process with a key-capable terminal panel and a read-only,
  non-key usage panel.
- Keep Dock Accessibility reads, host-display resolution, auto-hide state, and
  collapsed frames in `DockCoordinator`.
- Hide a panel when its side lacks space; never extend it across the Dock.
- Pass the explicit `ShellEnvironment` to SwiftTerm.
- Keep Codex usage on the official `codex app-server` protocol.
- Keep Claude usage on the official local Claude Code `/usage` command and its
  documented status-line `rate_limits` payload. Automatic probes must use safe
  mode with tools disabled, bounded time and output, an isolated `0700` working
  directory, and an exact per-probe session ID. Cancel them when Claude is
  deselected, Status Line Only is selected, or the display/session is inactive;
  remove only the matching probe transcript afterward. Never auto-accept a
  workspace trust prompt.
- Keep manual Usage refresh single-flight. Rapid panel clicks must be debounced,
  and automatic Claude `/usage` probes must retain their one-minute minimum
  start interval and single pending timer.
- Do not add browser-cookie, browser-keychain, Full Disk Access, Screen
  Recording, or private usage-endpoint providers.
- Preserve macOS 13 support and avoid new dependencies when the platform or
  SwiftTerm already provides the required behavior.
- Keep bundled license notices synchronized with the revisions in
  `Package.resolved`.

## Settings and modules

- Give every panel module a stable `PanelModuleID` and register its metadata and
  optional settings pane in `PanelModuleRegistry`.
- Register its work in `ModuleRuntimeCoordinator`. Starting and stopping must be
  idempotent; a disabled module must not keep a timer, subprocess, sensor, or
  network request running. Read-only work must suspend while the display or
  login session is inactive and use reduced cadence in Low Power Mode or under
  serious thermal pressure.
- Keep placement and visibility in `PanelDeckConfiguration`; its versioned
  storage preserves unknown module IDs for forward compatibility.
- Keep module state and change events in `SettingsPanelModel`, module-specific
  controls in a focused settings view, and window hosting in `SettingsPanelView`.
- Keep shared surface controls under Appearance.
- Put provider-level controls in the owning module pane. Usage providers must
  stop their own polling or subprocess when deselected.
- Keep Service Monitor probes credential-free and on the ephemeral session.
  Public endpoints require HTTPS; local HTTP support must stay within the
  narrow `NSAllowsLocalNetworking` exception. Keep the Range-request fallback,
  transient-failure confirmation, and offline state distinct from endpoint
  failure.
- Keep Weather opt-in, selected-city only, and on the fixed Open-Meteo HTTPS
  hosts. Do not add IP geolocation or request Location permission. Preserve
  visible attribution, the non-commercial free-API warning, and disabled-state
  network shutdown.
- Keep Schedule read-only and permission-on-button only. Fetch EventKit data
  off the main thread, map only the displayed fields into value types, and
  release the event store and observer when disabled. Never log or persist
  event or Reminder content. Accept join links only from the conference HTTPS
  allowlist. Calendar and Reminders access remain separate and neither prompt
  may be triggered by enabling the module.
- Keep Project Pulse on bounded, non-interactive local `git` and authenticated
  `gh` commands. Persist only a standardized local path or selected
  `owner/repository` name. Never persist file names, command output, remote
  URLs, or credentials; GitHub authentication remains owned by GitHub CLI.
- Persist Focus Timer state only on transitions. Keep an absolute completion
  deadline separate from display refreshes so background and Low Power Mode
  cadence changes do not delay a completed phase.
- Keep notifications opt-in, local, and transition-based. Request macOS
  authorization only after the user enables notifications, and do not add
  separate network requests for alert evaluation.
- Keep World Clock local and minute-aligned. Do not add network time services;
  stop its timer when the module is disabled.
- Keep Battery on documented IOKit power-source fields only. Do not read or
  persist battery serial numbers, and stop sampling while disabled.
- Keep Network on primary-interface byte counters only. Do not inspect packets,
  addresses, or destinations. Use Network framework only for local route
  properties, and clear the previous sample when disabled.
- Read-only modules can be assigned to either Deck and must render correctly at
  the compact panel size before they are registered. Preserve enabled-first
  ordering and independent Deck selections, and test settings changes against
  the runtime. Automatic rotation must be opt-in, skip Terminal and unchecked
  modules, pause on an unchecked selection or interaction, and suspend with an
  inactive display or login session. Manual scrolling must continue to include
  every enabled module.

## PR guidelines

- **One change per PR.** A PR that bundles a bug fix with an unrelated
  feature (or several unrelated features) won't get approved as one
  unit — split it up, even if it was all written in one sitting.
- **Keep PRs small.** Prefer the smallest diff that does the thing. Put Dock
  queries and frame calculations in `DockCoordinator`, not in a panel view.

## Everything else

Open an issue for bugs or ideas. If a change touches the Dock-tracking
or code-signing logic, explain what you tested it against
(Accessibility permission state, Dock tile size, macOS version) since
those are the parts most sensitive to environment differences.
