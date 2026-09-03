# Diagnostics

Open **Settings → Diagnostics** to check the local dependencies used by
DockDeck. Checks run once when the page opens and again only when **Refresh** is
pressed; there is no diagnostics polling timer.

| Check | Ready means |
| --- | --- |
| Codex | The installed CLI reports an active local sign-in |
| Claude Code | The installed CLI reports an active local sign-in |
| GitHub CLI | `gh` reports an active `github.com` sign-in |
| Accessibility | Dock geometry tracking permission is granted |
| Temperature sensor | The validated signed Stats SMC helper is available |
| Network | macOS reports an active primary interface |

CLI stdout and stderr are discarded. DockDeck records only the status, check
time, and the last successful check in app memory; it does not display or store
account identifiers, command output, or tokens. Each command check has a
three-second limit. A local CLI wrapper's own directory is added to its child
`PATH`, allowing NVM and similar installations to resolve adjacent runtimes
when DockDeck starts as a LaunchAgent.

Diagnostics reports dependency readiness, not service uptime or entitlement
details. Use the module's panel help and guide when a dependency is ready but a
specific refresh still fails.

## Module runtime

The same page reports the latest runtime state for every registered module:

| State | Meaning |
| --- | --- |
| `VISIBLE` | Selected on a visible Deck and using its foreground cadence |
| `BACKGROUND` | Enabled behind another module and using its background cadence |
| `PAUSED` | Enabled but suspended because the display or login session is inactive |
| `DISABLED` | Stopped with no module timer, observer, request, or subprocess |

`REDUCED CADENCE` means Low Power Mode or serious/critical thermal pressure is
slowing eligible timers. The terminal preserves its shell across display sleep
while read-only modules suspend. This snapshot is refreshed with the diagnostic
checks and does not add a runtime polling loop.
