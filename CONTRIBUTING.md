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
- Store only `rate_limits` from Claude Code's official status-line payload.
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
  network request running.
- Keep placement and visibility in `PanelDeckConfiguration`; its versioned
  storage preserves unknown module IDs for forward compatibility.
- Keep module state and change events in `SettingsPanelModel`, module-specific
  controls in a focused settings view, and window hosting in `SettingsPanelView`.
- Keep shared surface controls under Appearance.
- Put provider-level controls in the owning module pane. Usage providers must
  stop their own polling or subprocess when deselected.
- Keep Service Monitor probes credential-free and on the ephemeral session.
  Public endpoints require HTTPS; local HTTP support must stay within the
  narrow `NSAllowsLocalNetworking` exception.
- Keep Weather opt-in, selected-city only, and on the fixed Open-Meteo HTTPS
  hosts. Do not add IP geolocation or request Location permission. Preserve
  visible attribution, the non-commercial free-API warning, and disabled-state
  network shutdown.
- Keep Schedule read-only and permission-on-button only. Fetch EventKit data
  off the main thread, map only the displayed fields into value types, and
  release the event store and observer when disabled. Never log or persist
  event content.
- Keep World Clock local and minute-aligned. Do not add network time services;
  stop its timer when the module is disabled.
- Read-only modules share the read-only Deck and must render correctly at the
  compact panel size before they are registered. Keep module switching manual
  and predictable; do not add automatic rotation, drag reordering, or module
  installation without implementing and testing those runtime behaviors.

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
