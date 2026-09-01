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
  controls in `SettingsPaneViews`, and window hosting in `SettingsPanelView`.
- Keep shared surface controls under Appearance.
- Put provider-level controls in the owning module pane. Usage providers must
  stop their own polling or subprocess when deselected.
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
