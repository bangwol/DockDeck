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
subprocess. It does not read browser cookies or browser credential stores.

## Claude

Claude Code supplies `resets_at` through its
[status-line data](https://code.claude.com/docs/en/statusline#rate-limit-usage).
The bridge receives new account data after a normal Claude assistant response.
An idle session, `/status`, `/usage`, and `refreshInterval` callbacks do not
fetch new quota data for DockDeck. `⌘R` rereads the local cache but does not
contact Anthropic. A cache older than ten minutes is shown as stale.

Anthropic does not currently expose the Fable meter shown by Claude Code's
interactive `/usage` screen through the documented status-line payload. For
forward compatibility, DockDeck recognizes the experimental aliases
`seven_day_fable` and `fable`. It adds an `FBL` meter only when the payload
actually contains one of them and never estimates Fable usage.
[Fable availability is plan-specific](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan),
and Fable 5 requires Claude Code `2.1.170` or later.

See [Configure the Claude Code bridge](../integrations/claude-code.md) for setup,
normal update behavior, and troubleshooting.

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

## Local cache

The Claude bridge stores only `rate_limits` and an observation timestamp in:

```text
~/Library/Application Support/DockDeck/claude-rate-limits.json
```

The cache directory uses `0700` permissions and the file uses `0600`
permissions. DockDeck does not use OAuth tokens, browser sessions, or
undocumented account APIs to update Claude usage.
