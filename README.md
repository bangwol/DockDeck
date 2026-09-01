<p align="center">
  <img src="assets/AppIcon.png" width="112" height="112" alt="DockDeck app icon" />
</p>

<h1 align="center">DockDeck</h1>

<p align="center">
  A terminal and AI usage dashboard that live beside your macOS Dock.
</p>

DockDeck turns the space around a bottom-aligned Dock into two compact developer panels:

```text
┌──────────────────┐  ┌──────────── macOS Dock ────────────┐  ┌──────────────────┐
│ Terminal         │  │                                    │  │ Codex / Claude   │
└──────────────────┘  └────────────────────────────────────┘  └──────────────────┘
```

The terminal stays interactive on the left. The read-only usage panel stays on the right. Both follow the Dock across displays, Spaces, and auto-hide transitions without becoming ordinary app windows.

> DockDeck is in early development. The current version is `0.1.0`.

## Features

- A persistent login shell powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
- Remaining Codex quota through the official `codex app-server` protocol.
- Remaining Claude quota from Claude Code's official status-line payload.
- Dock-aware positioning, multi-display tracking, and auto-hide behavior.
- Matching left and right panel widths derived from the smaller side of the Dock.
- A non-interactive usage panel that cannot steal keyboard focus.
- A compact `% ` prompt inside DockDeck without changing the user's shell files.
- Automatic terminal expansion when clicked, with remembered size controls.
- Native edge resizing while click-expanded; the last width and height are restored next time.
- Native Liquid Glass on macOS 26, with a translucent visual-effect fallback on earlier macOS.
- Stronger terminal tint while expanded for readable text over any desktop.
- Manual large terminal mode and built-in appearance controls.
- Twenty terminal themes with configurable font, tint, and corner radius.

Keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘R` | Refresh usage data |
| `⌘Q` | Quit DockDeck |

Click the terminal to enter its focused size. Drag any window edge to resize it; DockDeck stores the resulting width and height ratios and restores them on the next click. The terminal menu's **Settings…** panel provides the same width and height controls. `⌘E` remains a separate, fixed 75% large-terminal mode.

## Requirements

- macOS 13 or later
- Swift 5.9 or later
- Accessibility permission for precise Dock tracking
- [Codex CLI](https://github.com/openai/codex) signed in locally for Codex usage data
- Claude Code `2.1.251` or later with the optional bridge configured for Claude usage data

Without Accessibility permission, DockDeck remains usable in fixed fallback positions. Only a bottom-aligned Dock is tracked precisely; side-aligned Docks use the fallback layout.

## Reading the usage panel

`CODEX` and `CLAUDE` are always written in full. Every percentage and filled bar represents capacity **remaining**, not capacity used. For example, `22%` means 22% remains and 78% has been used.

Codex displays whichever 5-hour and weekly windows the signed-in plan currently returns. A Plus response with both windows shows both; a Pro-or-higher response with only the weekly window shows only `7d`. DockDeck uses the returned window durations instead of hard-coding plan names. See OpenAI's [Codex plan guide](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan/).

Claude displays its 5-hour and weekly windows. `FBL` is added when Claude Code supplies a separate Fable window as `seven_day_fable` or `fable`. Anthropic documents [Fable's plan-specific allowance](https://support.claude.com/en/articles/15424964-claude-fable-5-on-your-plan), but its current status-line reference guarantees only the 5-hour and weekly fields. DockDeck therefore hides unavailable Fable data instead of estimating it.

- More than 50% remaining: normal theme color
- 20–50% remaining: orange
- Less than 20% remaining: red

## Build from source

From the repository root:

```bash
swift test
swift run DockDeck
```

Enable Dock geometry diagnostics when needed:

```bash
DOCKDECK_DEBUG=1 swift run DockDeck
```

### Build a local app bundle

```bash
./scripts/package.sh
open .build/release-dist/DockDeck.app
```

This produces a universal, ad-hoc signed `DockDeck.app` and `DockDeck.zip`. It does not modify login items or the Keychain. Public distribution still requires Developer ID signing and notarization.

### Start at login for local development

```bash
./scripts/install.sh
```

The installer registers a per-user LaunchAgent and prefers the sole Apple Development identity in the login Keychain. Its Apple-anchored designated requirement keeps Accessibility approval stable across local rebuilds. No certificate name or account information is written to the repository.

If there is no single Apple Development identity, the installer creates a self-signed local fallback. Current macOS releases may require Accessibility approval again after rebuilding with that fallback. Select a different installed identity explicitly when needed:

```bash
DOCKDECK_SIGNING_IDENTITY="certificate name or SHA-1 hash" ./scripts/install.sh
```

Review the script before running it.

To remove the LaunchAgent:

```bash
./scripts/uninstall.sh
```

The uninstall script removes the login item only. It does not remove the local signing certificate or build output.

## Usage data and privacy

DockDeck does not read browser cookies, browser credential stores, or private web endpoints.
It observes only mouse-down occurrence to collapse the focused terminal; it does not record
global keystrokes, pointer coordinates, or clicked content.

| Provider | Source | Local behavior |
| --- | --- | --- |
| Codex | `codex app-server` using `account/rateLimits/read` | Runs the locally installed official Codex CLI as a long-lived subprocess |
| Claude | Claude Code status-line JSON | Stores only `rate_limits` and an observation timestamp in a local cache |

The Claude cache is written atomically to:

```text
~/Library/Application Support/DockDeck/claude-rate-limits.json
```

The cache directory uses `0700` permissions and the file uses `0600` permissions.

DockDeck also writes a small zsh startup hook to
`~/Library/Caches/DockDeck/Shell/.zshenv`. It preserves the user's normal zsh startup files and
changes only the DockDeck terminal prompt. The directory uses `0700` permissions and the hook
uses `0600` permissions.

## Configure Claude Code

Claude quota data reaches DockDeck through Claude Code's supported `statusLine` JSON input. See Anthropic's [Claude Code installation guide](https://code.claude.com/docs/en/installation), [status-line reference](https://code.claude.com/docs/en/statusline), and [settings reference](https://code.claude.com/docs/en/settings).

### 1. Install or update Claude Code

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

Confirm that the installed version is `2.1.251` or later, then start Claude Code once and complete sign-in:

```bash
claude --version
claude
```

Claude Code added `rate_limits` to status-line input in `2.1.251`. The field appears only for supported Claude.ai subscriptions and only after the first API response in a session.

### 2. Locate the DockDeck bridge

After running `./scripts/install.sh` from the repository, the bridge is inside the generated app bundle:

```bash
cd /path/to/DockDeck
BRIDGE_PATH="$(pwd)/.build/release/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge"
test -x "$BRIDGE_PATH" && printf '%s\n' "$BRIDGE_PATH"
```

If DockDeck is copied to `/Applications`, use `/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge` instead.

### 3. Add the status line

DockDeck never edits `~/.claude/settings.json` automatically. Preserve its existing keys and check for an existing `statusLine` before adding this entry:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/DockDeck/.build/release/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge\"",
    "refreshInterval": 60
  }
}
```

Use the absolute path printed in step 2. `~` and shell variables are intentionally avoided inside the JSON command so paths containing spaces remain unambiguous.

To preserve an existing executable status-line script, pass the same JSON input through it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/dockdeck-claude-bridge\" -- /absolute/path/to/existing-statusline",
    "refreshInterval": 60
  }
}
```

For an existing inline shell command, use `--passthrough-shell`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/absolute/path/to/dockdeck-claude-bridge\" --passthrough-shell 'YOUR EXISTING COMMAND'",
    "refreshInterval": 60
  }
}
```

### 4. Verify the bridge

Start a new `claude` session and send one request. The right panel updates within 60 seconds, or immediately after `⌘R`. Verify that the privacy-filtered cache exists:

```bash
test -f "$HOME/Library/Application Support/DockDeck/claude-rate-limits.json" \
  && echo "Claude bridge ready"
```

If the cache is missing, confirm the Claude Code version and run `/status` inside Claude Code to verify that user settings were loaded.

## Project lineage

DockDeck began as a derivative of [Starboard v0.17.1](https://github.com/palamim/starboard/tree/v0.17.1) by Leonardo Palamim Cardozo. It is independently maintained and is not affiliated with or endorsed by the original project.

Starboard's MIT copyright and permission notice remain in [LICENSE](LICENSE). Dependency notices are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [ThirdPartyLicenses](ThirdPartyLicenses).

## License

DockDeck is distributed under the [MIT License](LICENSE).
