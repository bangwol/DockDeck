<p align="center">
  <img src="assets/AppIcon.png" width="112" height="112" alt="DockDeck app icon" />
</p>

<h1 align="center">DockDeck</h1>

<p align="center">
  A terminal and an AI usage dashboard that live beside your macOS Dock.
</p>

<p align="center">
  <img src="assets/dockdeck-overview.png" alt="DockDeck terminal and remaining-usage panels beside the macOS Dock" />
</p>

<p align="center">
  <sub>Compact terminal on the left; remaining Codex and Claude capacity on the right.</sub>
</p>

DockDeck uses the space beside a bottom-aligned Dock for two compact developer panels. The terminal stays interactive on the left, while the read-only usage panel stays on the right. Both follow the Dock across displays, Spaces, and auto-hide transitions.

## Features

- Persistent [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) login shell with a compact `% ` prompt that does not change user shell files.
- Remaining Codex and Claude capacity from their supported local interfaces; no browser cookies or private web endpoints.
- Dock-aware, symmetric placement across displays, Spaces, and auto-hide transitions.
- Read-only usage panel that never takes keyboard focus.
- Click-to-focus terminal expansion, native edge resizing, and remembered dimensions.
- Native Liquid Glass on macOS 26, with a translucent fallback and stronger terminal tint on earlier macOS.
- Manual large-terminal mode plus 20 themes with configurable font, tint, and corner radius.

Keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘R` | Refresh usage data |
| `⌘Q` | Quit DockDeck |

Click the terminal to expand it. Drag any edge to resize it; DockDeck restores those proportions the next time it expands. The terminal menu's **Settings…** panel provides the same controls. `⌘E` toggles a separate, fixed 75% large-terminal mode.

## Requirements

- macOS 13 or later
- Accessibility permission for Dock geometry tracking
- [Codex CLI](https://github.com/openai/codex) signed in locally for Codex usage data
- Claude Code `2.1.80` or later with the optional bridge configured for Claude usage data
- Swift 5.9 or later when building from source

Without Accessibility permission, DockDeck remains usable in fixed fallback positions. Only a bottom-aligned Dock is tracked precisely; side-aligned Docks use the fallback layout.

## Reading the usage panel

Every percentage and filled bar represents capacity **remaining**, not capacity used. For example, `22%` means 22% remains and 78% has been used.

Codex displays whichever 5-hour and weekly windows the signed-in account returns. DockDeck uses the returned durations instead of guessing the plan. OpenAI documents a shared 5-hour window for local and cloud tasks and notes that weekly limits may also apply in the [Codex pricing guide](https://learn.chatgpt.com/docs/pricing).

Claude displays the 5-hour and weekly fields available in Claude Code's status-line payload. The current official schema exposes only `five_hour` and `seven_day`, so DockDeck cannot currently show a separate Fable meter. It does not estimate missing data or call undocumented account endpoints. Anthropic documents [Fable's plan-specific availability](https://support.claude.com/en/articles/15424964-claude-fable-5-on-your-plan).

- More than 50% remaining: normal theme color
- 20–50% remaining: orange
- Less than 20% remaining: red

## Run from source

```bash
git clone https://github.com/bangwol/DockDeck.git
cd DockDeck
swift test
swift run DockDeck
```

Enable Dock geometry diagnostics when needed:

```bash
DOCKDECK_DEBUG=1 swift run DockDeck
```

## Start at login

```bash
./scripts/install.sh
```

The installer builds and signs `~/Applications/DockDeck.app`, registers a per-user LaunchAgent, starts DockDeck immediately, and starts it at future logins. The stable app path and signing identity allow Accessibility approval to survive rebuilds. It prefers the sole Apple Development identity in the login Keychain. No certificate name or account information is written to the repository.

If there is no single Apple Development identity, the installer creates a self-signed local fallback. macOS may request Accessibility approval again after rebuilding with that fallback. Select a different installed identity when needed:

```bash
DOCKDECK_SIGNING_IDENTITY="certificate name or SHA-1 hash" ./scripts/install.sh
```

Review the script before running it. To remove the LaunchAgent:

```bash
./scripts/uninstall.sh
```

The uninstall script removes the login item only. It leaves the installed app, local signing certificate, and build output in place.

## Build a distributable local bundle

```bash
./scripts/package.sh
open .build/release-dist/DockDeck.app
```

This produces a universal, ad-hoc signed `DockDeck.app` and `DockDeck.zip` without changing login items or the Keychain. Public distribution requires Developer ID signing and notarization.

## Usage data and privacy

DockDeck does not read browser cookies, browser credential stores, or private web endpoints. It observes only mouse-down occurrence to collapse the focused terminal; it does not record global keystrokes, pointer coordinates, or clicked content.

| Provider | Source | Local behavior |
| --- | --- | --- |
| Codex | `codex app-server` using `account/rateLimits/read` | Runs the locally installed official Codex CLI as a long-lived subprocess |
| Claude | Claude Code status-line JSON | Stores only `rate_limits` and an observation timestamp in a local cache |

The Claude cache is written atomically to:

```text
~/Library/Application Support/DockDeck/claude-rate-limits.json
```

The cache directory uses `0700` permissions and the file uses `0600` permissions.

DockDeck also writes a small zsh startup hook to `~/Library/Caches/DockDeck/Shell/.zshenv`. It preserves the user's normal zsh startup files and changes only the DockDeck terminal prompt. The directory uses `0700` permissions and the hook uses `0600` permissions.

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

Confirm that the installed version is `2.1.80` or later, then start Claude Code once and complete sign-in:

```bash
claude --version
claude
```

Claude Code added `rate_limits` to status-line input in `2.1.80`. Each 5-hour or weekly window can be absent, and the payload appears only after the first API response for supported accounts.

### 2. Locate the DockDeck bridge

After running `./scripts/install.sh`, the bridge is inside the installed app bundle:

```bash
BRIDGE_PATH="$HOME/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge"
test -x "$BRIDGE_PATH" && printf '%s\n' "$BRIDGE_PATH"
```

For a system-wide copy, use `/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge` instead.

### 3. Add the status line

DockDeck never edits `~/.claude/settings.json` automatically. Preserve its existing keys and check for an existing `statusLine` before adding this entry:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Users/your-name/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge\"",
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
