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
