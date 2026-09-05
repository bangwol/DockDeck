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
when DockDeck starts at login.

Command performance records the last duration, last successful completion, and
timeout/cancellation counts for this app session. Categories are fixed (Custom
Tiles, Docker, Integration Checks, Quick Actions, and Other Commands); no command
paths, arguments, or output are retained. Counts stop at 999,999 and reset when
the app quits. Opening or refreshing Diagnostics reads these counters without
adding a polling timer. Launch failures and oversized output are reported
separately from timeouts.

Disabling or reconfiguring Custom Tiles and Docker cancels their in-flight
commands. DockDeck terminates only the process it launched, allows one second
for graceful exit, then uses a bounded forced termination if needed. A custom
command is responsible for cleaning up any descendants it launches; avoid
detached daemons in tiles. Late results cannot overwrite a stopped module.
When the app quits, it stops accepting new bounded commands and spends at most
two seconds terminating and collecting existing ones. This also covers explicit
Quick Actions and diagnostic commands that are still running during shutdown.

Diagnostics reports dependency readiness, not service uptime or entitlement
details. Use the module's panel help and guide when a dependency is ready but a
specific refresh still fails.

Use **Copy Report** to place a support-ready snapshot on the clipboard. The
report contains only the DockDeck version, macOS version, architecture,
integration states and check times, system cadence, module runtime states, and
the fixed command performance counters.
It deliberately omits diagnostic detail strings, paths, URLs, account
identifiers, command output, and tokens. Review any clipboard content before
sharing it.

## Module runtime

The same page reports the latest runtime state for every registered module:

| State | Meaning |
| --- | --- |
| `VISIBLE` | Selected on a visible Deck and using its foreground cadence |
| `BACKGROUND` | Enabled behind another module and using its background cadence |
| `PAUSED` | Enabled but suspended because the display or login session is inactive |
| `DISABLED` | Stopped; owned requests and subprocesses are being cancelled within their cleanup limits |

`REDUCED CADENCE` means Low Power Mode or serious/critical thermal pressure is
slowing eligible timers. The terminal preserves its shell across display sleep
while read-only modules suspend. This snapshot is refreshed with the diagnostic
checks and does not add a runtime polling loop. Hover a module state to see when
its current state began; the timestamp is also included in a copied report.
