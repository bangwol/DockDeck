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
- Live Codex quota data through the official `codex app-server` protocol.
- Claude quota data from Claude Code's official status-line payload.
- Dock-aware positioning, multi-display tracking, and auto-hide behavior.
- Matching left and right panel widths derived from the smaller side of the Dock.
- A non-interactive usage panel that cannot steal keyboard focus.
- A compact `% ` prompt inside DockDeck without changing the user's shell files.
- Automatic 2× width / 4× height terminal expansion when the terminal is clicked.
- Manual large terminal mode and built-in appearance controls.
- Twenty terminal themes with configurable font, tint, and corner radius.

Keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘R` | Refresh usage data |
| `⌘Q` | Quit DockDeck |

## Requirements

- macOS 13 or later
- Swift 5.9 or later
- Accessibility permission for precise Dock tracking
- [Codex CLI](https://github.com/openai/codex) signed in locally for Codex usage data
- Claude Code with the optional bridge configured for Claude usage data

Without Accessibility permission, DockDeck remains usable in fixed fallback positions. Only a bottom-aligned Dock is tracked precisely; side-aligned Docks use the fallback layout.

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

The installer creates a self-signed local code-signing certificate in the login Keychain and registers a per-user LaunchAgent. This keeps the app's Accessibility identity stable across local rebuilds. Review the script before running it.

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

## Configure the Claude bridge

DockDeck never edits `~/.claude/settings.json` automatically. Check for an existing `statusLine` entry before changing it.

If DockDeck is installed at `/Applications/DockDeck.app`, a minimal configuration is:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge\"",
    "refreshInterval": 60
  }
}
```

To preserve an existing status-line command, pass its output through the bridge:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Applications/DockDeck.app/Contents/Resources/bin/dockdeck-claude-bridge\" --passthrough-shell 'YOUR EXISTING COMMAND'",
    "refreshInterval": 60
  }
}
```

Use the actual absolute path if the app is installed elsewhere.

## Project lineage

DockDeck began as a derivative of [Starboard v0.17.1](https://github.com/palamim/starboard/tree/v0.17.1) by Leonardo Palamim Cardozo. It is independently maintained and is not affiliated with or endorsed by the original project.

Starboard's MIT copyright and permission notice remain in [LICENSE](LICENSE). Dependency notices are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [ThirdPartyLicenses](ThirdPartyLicenses).

## License

DockDeck is distributed under the [MIT License](LICENSE).
