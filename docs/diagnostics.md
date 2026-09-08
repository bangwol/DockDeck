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

Sign-in command stdout and stderr are discarded. DockDeck records the status,
check time, and last successful check in app memory; it does not display or store
account identifiers, raw command output, or tokens. A failed status check can
mean either an authentication problem or a CLI configuration error. Each command
check has a three-second limit. A local CLI wrapper's own directory is added to its child
`PATH`, allowing NVM and similar installations to resolve adjacent runtimes
when DockDeck starts at login.

Command performance records the last duration, last successful completion, and
timeout/cancellation counts for this app session. Categories are fixed (Custom
Tiles, Docker, Integration Checks, Quick Actions, and Other Commands); no command
paths, arguments, or output are retained. Counts stop at 999,999 and reset when
the app quits. Opening or refreshing Diagnostics reads these counters without
adding a polling timer. Launch failures and oversized output are reported
separately from timeouts.

Disabling or reconfiguring Custom Tiles, Docker, Project Pulse, or GitHub Inbox
cancels their in-flight and queued commands. DockDeck terminates only the
process it launched, allows one second for graceful exit, then uses a bounded
forced termination if needed. A custom
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

## CLI update guidance

Codex, Claude Code, and GitHub CLI rows also show the installed `--version`,
installation source, and update availability. Hover the installed version to
see the executable path; hover the update status for the metadata check time.
Updates are advisory and do not change the sign-in readiness badge.

- npm installations compare with their package's `latest` version on the public
  npm registry. The copied command targets the detected global prefix and Node
  runtime, including NVM installations.
- Homebrew installations compare with the detected cask or formula on the public
  Homebrew API. Claude Code's `claude-code` and `claude-code@latest` casks are
  checked separately. The command uses that Homebrew installation.
- Native Claude Code compares with the latest published npm version. Its
  `claude update` command follows the user's configured release channel; a newer
  published version may not yet be offered on the stable channel.
- App-bundled CLIs are updated through their containing app. Unknown installation
  methods show an installation guide instead of a guessed update command.
  Preview/custom versions are not compared with stable releases.

**Copy Update Command** only copies text. Run it yourself in a terminal, then
press **Refresh**. Commands are offered only when the matching package manager
is present. DockDeck never installs CLI updates or changes their settings.
Pinned versions and organization policies still apply; consult the linked
installation guide before changing an intentionally pinned installation.

Version metadata requests run only when Diagnostics opens or is refreshed,
without authentication, cookies, or persistent response storage. Successful
results are cached in memory for six hours, failures for five minutes. Installed
versions are read again on every refresh. An offline or malformed response shows
**Update check unavailable**, never **Up to date**. Each request has an eight-second
resource timeout and a 256 KiB response limit; version commands have a three-second
limit and 4 KiB output limit. No installed versions, local paths, or account data
are sent to these services. Copied reports continue to omit CLI version metadata,
paths, and update commands. DockDeck self-updates are not part of this feature.

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

Activity and power-state changes retain elapsed time in a module's polling
interval. Repeated deck switches therefore cannot postpone a poll indefinitely;
a poll that is already due runs when the main run loop can handle it. Explicit
reconfiguration and resuming a stopped module start a new polling interval.
In-flight work keeps each module's existing cancellation and timeout limits.

Process timeouts, terminal restart throttling, and network rate measurements use
monotonic elapsed time. System clock changes cannot extend those timeouts or
distort the measured rates. Public CLI release metadata and shared GitHub
response caches are invalidated when the system clock moves backwards. Calendar
events, quota reset times, and saved Focus Timer deadlines remain absolute dates.
