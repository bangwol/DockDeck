# Configure Claude Code

Claude quota data reaches DockDeck through Claude Code's supported `statusLine`
JSON input. See Anthropic's
[Claude Code installation guide](https://code.claude.com/docs/en/installation),
[status-line reference](https://code.claude.com/docs/en/statusline), and
[settings reference](https://code.claude.com/docs/en/settings).

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

Update to the current Claude Code release, then start it once and complete
sign-in:

```bash
claude --version
claude
```

Anthropic documents status-line `rate_limits` as requiring Claude Code
`2.1.251` or later. DockDeck follows the documented `five_hour` and `seven_day`
fields and recommends the current Claude Code release because the schema and
account availability can change.

The object is available to supported Claude.ai Pro and Max accounts only after
the first API response in a session. Each window can be absent independently or
disappear after its reset time.

## 2. Locate the DockDeck bridge

After running `./scripts/install.sh` from the repository root, the bridge is
inside the installed app bundle:

```bash
BRIDGE_PATH="$HOME/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge"
test -x "$BRIDGE_PATH" && printf '%s\n' "$BRIDGE_PATH"
```

For a system-wide copy, use
`/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge`
instead.

## 3. Add the status line

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

Use the absolute path printed in step 2. `~` and shell variables are avoided
inside the JSON command so paths containing spaces remain unambiguous.

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

## 4. Verify the bridge

Start a new `claude` session and send one normal request. Opening `/status` or
`/usage` alone does not update the bridge. The Usage panel updates within
60 seconds, or immediately after `⌘R` rereads the cache.

Verify that the privacy-filtered cache exists:

```bash
test -f "$HOME/Library/Application Support/DockDeck/claude-rate-limits.json" \
  && echo "Claude bridge ready"
```

If the cache is missing, confirm the Claude Code version and run `/status`
inside Claude Code to verify that user settings were loaded.

Do not add `refreshInterval` solely for DockDeck. Timed status-line callbacks
replay the last session payload without fetching account usage and do not
improve its freshness. DockDeck already watches the cache on its own timer. The
bridge derives freshness from the local transcript modification time but never
stores the transcript path or contents.

## 5. Understand day-to-day updates

DockDeck does not keep a hidden Claude process running and does not poll
Anthropic account endpoints. Claude Code invokes the bridge locally and supplies
the supported quota fields as part of its status-line JSON.

| Claude Code activity | DockDeck behavior |
| --- | --- |
| Start or resume a session | The status line runs, but a new session may not contain `rate_limits` until its first API response. |
| Receive a normal assistant response | Claude Code runs the status line with its latest supported 5-hour and 7-day fields. The bridge updates the local cache automatically. |
| Run `/usage` | Claude Code shows its interactive plan-usage view. Those screen values, including the separate Fable meter, are not copied into the documented status-line payload. |
| Run `/status`, change permission or Vim mode, or finish `/compact` | The status line may run again, but this is not a new account-usage request and can repeat the previous quota values. |
| Leave Claude Code idle or close it | No new payload arrives. DockDeck keeps the last cache and marks it stale after ten minutes. Keeping an unused session open does not improve freshness. |
| Use Claude Desktop, claude.ai, or another machine | Shared account usage can change without a local status-line event. DockDeck catches up after the next normal response in local Claude Code. |
| Press `⌘R` in DockDeck | DockDeck rereads the cache immediately. It does not start Claude Code or contact Anthropic. |

You do not need to type `/usage` or leave a terminal session open solely as a
monitor. Use Claude Code normally; each real local response updates the bridge.
If most Claude usage happens in Desktop, a browser, or another machine, use that
surface's usage view when exact current account usage is required.

DockDeck intentionally does not use OAuth tokens, browser sessions, or
undocumented account APIs to fill that gap.

Fable remains a known limitation. The interactive `/usage` screen can show a
Fable-specific weekly allowance, but the documented status-line schema currently
exposes only `five_hour`, `seven_day`, and gateway `spend_limit` windows.
DockDeck therefore does not estimate or scrape Fable usage.

## 6. Troubleshoot Claude data

1. Run `claude --version` and update if it is older than `2.1.251`.
2. Confirm `~/.claude/settings.json` still contains the DockDeck bridge under
   `statusLine.command`. A global `disableAllHooks: true` setting also disables
   the status line.
3. Confirm the installed bridge is executable:

   ```bash
   test -x "$HOME/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge" \
     && echo "DockDeck bridge ready"
   ```

4. Start or resume Claude Code and send one normal request. `/usage` or
   `/status` alone is not a bridge refresh test.
5. Confirm the privacy-filtered cache exists, then press `⌘R` in DockDeck:

   ```bash
   test -f "$HOME/Library/Application Support/DockDeck/claude-rate-limits.json" \
     && echo "Claude cache ready"
   ```

6. If the status line itself is missing, run Claude Code with `claude --debug`
   and inspect the first status-line invocation error. A muted mark means the
   cache is merely old; a muted mark with a diagonal slash means setup, sign-in,
   or connectivity needs attention.

See [Usage](../modules/usage.md) for meter layout, provider states, and cache
privacy details.
