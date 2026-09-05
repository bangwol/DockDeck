# Usage

The Usage module shows supported Codex and Claude quota windows. Either provider
can be enabled independently under **Settings → Usage**.

## Values and layout

Percentages and bars show **remaining** capacity by default. Select **Used**
under **Settings → Usage → Values** to invert both the number and filled bar.
For example, the same quota appears as either 22% remaining or 78% used.

Each meter shows the provider-supplied reset time in the Mac's local time zone.
A provider with one returned window uses a two-column header: usage is centered
in the first column and its reset time in the second. Providers with two or
three windows place each reset below its matching bar.

Resets later today use `HH:mm`; a different day uses `M/D HH:mm`. `--` means
that the provider did not supply a timestamp. Hover a meter for its full
localized reset date and time.

### Even-use pace marker

Enable **Even-use pace** under **Settings → Usage** to place a thin marker on
each bar. The marker shows how much of that window would be used (or remain) if
capacity were consumed evenly from the inferred window start to its supplied
reset time. Hover the bar to compare the current value with that pace.

The marker is a planning reference, not a forecast or plan recommendation. It
appears only for a live window with both a known duration and a future reset
time. DockDeck hides it for stale data, expired windows, missing reset times,
and Fable values whose duration is not supplied.

## Codex

Codex supplies `resetsAt` through its
[app-server rate-limit response](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt).
DockDeck displays whichever 5-hour and weekly windows the signed-in account
returns and uses their returned durations instead of guessing the account plan.
OpenAI documents a shared 5-hour window for local and cloud tasks and notes that
weekly limits may also apply in the
[Codex pricing guide](https://learn.chatgpt.com/docs/pricing).

DockDeck runs the locally installed official Codex CLI as a long-lived app-server
subprocess. Rate-limit notifications update the displayed values even when no
refresh request is pending. Unrelated notifications are ignored. It does not
read browser cookies or browser credential stores.

## Claude

Choose a source under **Settings → Usage → Claude Refresh**:

| Mode | Behavior |
| --- | --- |
| **Automatic `/usage`** (default) | Runs the installed official Claude Code CLI briefly at launch, after a manual refresh, when a Deck menu opens, after the display or login session wakes, and at a randomized 10–20 minute interval. |
| **Status line only** | Never starts Claude in the background. It reads only the optional bridge cache produced after normal responses in a local Claude Code session. |

Automatic mode asks Claude Code's built-in
[`/usage` command](https://code.claude.com/docs/en/commands) for the account
windows. It first uses a bounded direct invocation and falls back to an
off-screen pseudo-terminal when the installed version requires interactive
rendering. No Terminal window appears, no Claude process is kept alive, and
tools are disabled for the probe. The process exits after capture.

Automatic probes stop while the display sleeps or the macOS login session is
locked. An in-flight probe is cancelled and one fresh probe normally runs after
the system becomes active. If a returned 5-hour or weekly limit is exhausted,
background probes instead wait until the latest blocking reset plus a short
grace period. A missing reset time backs off to one probe per hour. An exhausted
Fable allowance does not pause checks for the other models.

Click the compact Usage panel or press `⌘R` to request a manual refresh. Codex
and the optional status-line cache are checked immediately. A Claude `/usage`
probe starts only when another probe is not running and the previous one began
at least 60 seconds ago. A running probe absorbs further requests; after it
finishes, requests inside the remaining cooldown share one probe scheduled for
the boundary. Rapid panel clicks within 0.75 seconds are ignored, so they cannot
fan out provider work. The manual request overrides the exhausted-limit delay
after the cooldown. DockDeck does not install a global keyboard or pointer idle
monitor.

Each command path has a fixed runtime limit, and the Usage store adds a 30-second
watchdog. Pipe capture is closed explicitly after the Claude process exits, so a
descendant process cannot leave refresh permanently waiting for end-of-file. If
a transient probe fails, the last valid values remain visible as stale data and
the hover detail reports the latest refresh error.

The command can return 5-hour, weekly, and plan-specific Fable windows. DockDeck
shows `FBL` only when Claude returns that value and never estimates it.
[Fable availability is plan-specific](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan).

The optional bridge receives the documented 5-hour and 7-day
[`rate_limits` fields](https://code.claude.com/docs/en/statusline#available-data)
after a normal Claude assistant response. A cache older than ten minutes is
stale. When both sources are present, the newer source wins matching windows;
an `/usage`-only Fable window is retained.

See [Configure Claude Code monitoring](../integrations/claude-code.md) for mode
selection, optional bridge setup, privacy details, and troubleshooting.

The detail window uses the same remaining-capacity warning colors as the compact
panel in both Remaining and Used modes. It also shows the last successful
observation, refresh errors alongside cached values, the approximate next check,
and a manual refresh button. Manual refresh retains the existing probe cooldown.

## Provider states and colors

Provider marks show data state without adding a detached status dot:

- Full-color mark: current data
- Muted mark: loading or cached data past its freshness window
- Muted mark with a diagonal slash: sign-in, setup, or connection required

Hover a provider mark for its exact status and source detail. VoiceOver labels
include the same status.

Capacity colors follow the remaining amount:

- More than 50% remaining: selected text color
- 20–50% remaining: orange
- Less than 20% remaining: red

## Local files and process boundaries

The optional Claude bridge stores only `rate_limits` and an observation
timestamp in:

```text
~/Library/Application Support/DockDeck/claude-rate-limits.json
```

The cache directory uses `0700` permissions and the file uses `0600`
permissions.

Automatic mode uses this private working directory:

```text
~/Library/Application Support/DockDeck/ClaudeProbe
```

The working directory uses `0700` permissions. DockDeck passes a unique session
ID, removes that exact probe transcript after the process exits, caps captured
output at 256 KiB, and does not persist or log the captured screen. It removes
`ANTHROPIC_*` and `CLAUDE_CODE_OAUTH_TOKEN*` overrides from the child
environment. Authentication remains owned by the installed Claude Code CLI;
DockDeck does not read token files, browser sessions, or undocumented account
endpoints.
