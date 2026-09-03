# Configure Claude Code monitoring

DockDeck can read Claude account limits in two modes. **Automatic `/usage`** is
the default and needs only a signed-in Claude Code installation. **Status line
only** preserves the original bridge-only behavior and never launches Claude in
the background.

Anthropic documents `/usage` as a built-in command for viewing plan limits and
reset times. See the official [command reference](https://code.claude.com/docs/en/commands),
[cost and usage guide](https://code.claude.com/docs/en/costs), and
[status-line reference](https://code.claude.com/docs/en/statusline).

## 1. Install or update Claude Code

On macOS with Homebrew:

```bash
brew install --cask claude-code
```

For an existing Homebrew installation:

```bash
brew upgrade --cask claude-code
```

Native installations can update themselves:

```bash
claude update
```

Confirm the version, then start Claude Code once and complete sign-in:

```bash
claude --version
claude
```

Use a current release. Command output and account-specific windows can change,
and each 5-hour, weekly, or Fable window can be absent independently.

## 2. Choose a refresh mode

Open **DockDeck Settings → Usage → Claude Refresh**.

### Automatic `/usage`

DockDeck briefly runs the installed official CLI:

- when the Usage module starts;
- after `⌘R`;
- when a Deck menu opens, unless the previous probe began less than one minute
  ago;
- once after the display or macOS login session wakes; and
- every 10–20 minutes, with a new randomized delay after each completion.

The probe pauses while the display sleeps or the login session is locked. It is
cancelled immediately if Claude is disabled or **Status line only** is selected.

DockDeck first passes `/usage` directly to Claude Code. If that version requires
interactive rendering, it falls back to a hidden pseudo-terminal backed by the
same SwiftTerm library as DockDeck's visible terminal. It never opens
Terminal.app, keeps no idle Claude process, and exits after parsing the screen.
The separate Fable allowance appears as `FBL` when Claude returns it.

The probe uses Claude safe mode, exposes no tools, runs in a private app-owned
directory, caps output and runtime, and does not accept workspace trust prompts.
It strips `ANTHROPIC_*` and `CLAUDE_CODE_OAUTH_TOKEN*` overrides from the child
environment. Claude Code still uses its own existing local sign-in and may
contact Anthropic to render `/usage`; DockDeck never reads that credential or
calls a private account endpoint itself.

Direct capture, hidden-PTY capture, and the store watchdog are independently
bounded. DockDeck also closes its pipe readers after the child exits rather than
waiting indefinitely for inherited file descriptors. On a transient failure it
keeps the last successful limits visible as stale data and includes the current
error in the provider hover text.

The hidden-PTY fallback is not unique to DockDeck. Community implementations
such as [claude-code-usage-overlay](https://github.com/MattPears1/claude-code-usage-overlay)
and [Agents Deck](https://github.com/vulonviing/agents-deck) use the same general
Claude `/usage` capture pattern.

### Status line only

This mode never starts a background Claude process. DockDeck rereads only its
local cache. The cache changes after a normal assistant response in a configured
local Claude Code session. Usage from Claude Desktop, claude.ai, another Mac, or
an idle local session is not reflected until another local response supplies a
new status-line payload.

The documented status-line payload contains 5-hour and 7-day `rate_limits`.
Fable is shown only if Claude later adds a recognized Fable field to that
payload; DockDeck never estimates it.

## 3. Optionally configure the status-line bridge

The bridge is optional in Automatic mode and required in Status Line Only mode.
It adds immediate 5-hour and 7-day updates after local Claude responses.

After running `./scripts/install.sh` from the repository root, locate the
installed bridge:

```bash
BRIDGE_PATH="$HOME/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge"
test -x "$BRIDGE_PATH" && printf '%s\n' "$BRIDGE_PATH"
```

For a system-wide copy, use
`/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge`.

DockDeck never edits `~/.claude/settings.json` automatically. Preserve its
existing keys and check for an existing `statusLine` before adding this entry:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Users/your-name/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge\""
  }
}
```

Replace `your-name` with the macOS account folder name. Use the absolute path
printed above; `~` and shell variables are avoided inside the JSON command so
paths containing spaces remain unambiguous.

To preserve an existing executable status-line script, pass the same JSON input
through it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/dockdeck-claude-bridge\" -- /absolute/path/to/existing-statusline"
  }
}
```

For an existing inline shell command, use `--passthrough-shell`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/dockdeck-claude-bridge\" --passthrough-shell 'YOUR EXISTING COMMAND'"
  }
}
```

Claude Code runs the status-line command locally after relevant session events;
the status-line command itself does not consume API tokens. A periodic
`refreshInterval` only replays the last session payload, so adding one solely
for DockDeck does not fetch fresher account data.

## 4. Verify each mode

For Automatic `/usage`:

1. Enable Claude under **Settings → Usage** and select **Automatic `/usage`**.
2. Press `⌘R` in DockDeck.
3. Hover the Claude mark. Its source detail should begin with `Claude /usage`.
4. If the account exposes Fable, confirm an `FBL` meter appears.

For Status Line Only:

1. Send one normal request in a new or existing local Claude Code session.
   Opening `/status` or `/usage` alone does not create a new status-line quota
   payload.
2. Confirm the privacy-filtered cache exists:

   ```bash
   test -f "$HOME/Library/Application Support/DockDeck/claude-rate-limits.json" \
     && echo "Claude bridge ready"
   ```

3. Press `⌘R` in DockDeck. Hover detail should begin with `Status line`.

When both sources are enabled, DockDeck uses the newer observation for matching
5-hour and 7-day windows while retaining an `/usage`-only Fable window.

## 5. Local files and cleanup

The bridge cache contains only `rate_limits` and an observation timestamp:

```text
~/Library/Application Support/DockDeck/claude-rate-limits.json
```

Automatic probes use:

```text
~/Library/Application Support/DockDeck/ClaudeProbe
```

Both directories use `0700` permissions; the bridge cache uses `0600`.
Automatic mode creates a unique Claude session ID and removes only that exact
probe transcript from Claude Code's local session directory after exit. Captured
output is limited to 256 KiB, kept in memory, and never logged or saved by
DockDeck.

## 6. Troubleshoot Claude data

1. Run `claude --version` and update to the current release.
2. Run `claude`, then `/usage`, to confirm the signed-in account itself returns
   plan limits.
3. In Automatic mode, press `⌘R`, wait up to 20 seconds, and hover the Claude
   mark. `SIGN IN` means the local CLI needs authentication. `OFFLINE` indicates
   a command, timeout, or parsing failure.
4. If only Automatic mode fails, select **Status line only** and configure the
   bridge as a fallback. DockDeck does not bypass a Claude workspace trust
   screen.
5. For bridge failures, confirm `~/.claude/settings.json` still contains the
   bridge under `statusLine.command`. A global `disableAllHooks: true` also
   disables the status line.
6. Confirm the installed bridge is executable:

   ```bash
   test -x "$HOME/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge" \
     && echo "DockDeck bridge ready"
   ```

A muted mark means cached data is old. A muted mark with a diagonal slash means
setup, sign-in, or connectivity needs attention. See [Usage](../modules/usage.md)
for meter layout and provider-state details.
