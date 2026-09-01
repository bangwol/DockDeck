<p align="center">
  <img src="assets/AppIcon.png" width="112" height="112" alt="DockDeck app icon" />
</p>

<h1 align="center">DockDeck</h1>

<p align="center">
  A terminal and an AI usage dashboard that live beside your macOS Dock.
</p>

<p align="center">
  <a href="assets/dockdeck-overview.png">
    <img src="assets/dockdeck-overview.png" alt="DockDeck terminal and remaining-usage panels beside the macOS Dock" />
  </a>
</p>

<p align="center">
  <sub>Compact terminal and configurable Codex and Claude usage beside the macOS Dock. Open the image for full resolution.</sub>
</p>

DockDeck uses the space beside a bottom-aligned Dock for two compact developer panels. The terminal stays interactive while the usage panel remains read-only; either panel can be hidden or placed on either side. Both follow the Dock across displays, Spaces, and auto-hide transitions.

## Features

- Persistent [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) login shell with a compact `% ` prompt that does not change user shell files.
- Remaining or used Codex and Claude capacity from their supported local interfaces; no browser cookies or private web endpoints.
- Dock-aware, symmetric placement across displays, Spaces, and auto-hide transitions.
- Read-only usage panel with configurable values, font, size, and color; right-click it for the shared settings menu.
- Independent Terminal and Usage visibility controls; at least one panel remains visible so settings stay accessible.
- Click-to-focus terminal expansion, native edge resizing, and remembered dimensions.
- Native Liquid Glass on macOS 26, with a translucent fallback and stronger terminal tint on earlier macOS.
- Manual large-terminal mode plus 20 themes with configurable fonts, tint, corner radius, and panel placement.

Keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘,` | Open the shared settings panel |
| `⌘R` | Refresh usage data and Dock layout |
| `⌘Q` | Quit DockDeck |

DockDeck reserves the Command-key shortcuts above plus the standard `⌘C`, `⌘V`, and `⌘A` editing shortcuts. `Ctrl` combinations, Option/Meta, Esc, Tab, arrow keys, Home/End, Delete, and F1–F12 continue through SwiftTerm's normal terminal input handling. Option acts as Meta by default. Page Up and Page Down follow SwiftTerm's terminal scrolling behavior unless the running terminal application requests cursor-key handling.

Click the terminal to expand it, then click elsewhere to return it to the Dock. Drag any edge to resize it; DockDeck restores those proportions the next time it expands. Open the shared **Settings…** panel from the terminal menu, app menu, or usage-panel context menu. `⌘E` toggles a separate, fixed 75% large-terminal mode; its menu action is labeled **Return Terminal to Dock** while active. Running `exit` starts a fresh DockDeck login shell; use `⌘Q` to quit the app.

## Requirements

- macOS 13 or later
- Accessibility permission for Dock geometry tracking
- [Codex CLI](https://github.com/openai/codex) signed in locally for Codex usage data
- A current Claude Code release with the optional bridge configured for Claude usage data (`rate_limits` was introduced in `2.1.80`)
- Swift 5.9 or later when building from source

Without Accessibility permission, DockDeck remains usable in fixed fallback positions. Only a bottom-aligned Dock is tracked precisely; side-aligned Docks use the fallback layout.

## Preview distribution

DockDeck does not yet publish a Developer ID-signed and notarized stable binary. Until that is available, installing from source with `./scripts/install.sh` is the recommended preview path.

Tagged GitHub preview releases may include an explicitly labeled `unsigned` ZIP for technical evaluation. Manually dispatched preview builds appear as GitHub Actions artifacts and expire after 14 days; they are not GitHub Releases. Both are ad-hoc signed, so macOS requires manual approval in **System Settings → Privacy & Security → Open Anyway**, and an update may require Accessibility approval again. Preview artifacts built by GitHub Actions include a SHA-256 file and build-provenance attestation:

```bash
gh attestation verify DockDeck-*-unsigned.zip -R bangwol/DockDeck
```

## Reading the usage panel

Percentages and bars show **remaining** capacity by default. Select **Used** under **Settings → Usage → Values** to invert both the number and filled bar. For example, the same quota appears as either 22% remaining or 78% used.

Codex displays whichever 5-hour and weekly windows the signed-in account returns. DockDeck uses the returned durations instead of guessing the plan. OpenAI documents a shared 5-hour window for local and cloud tasks and notes that weekly limits may also apply in the [Codex pricing guide](https://learn.chatgpt.com/docs/pricing).

Claude displays the officially documented 5-hour and weekly fields available in Claude Code's status-line payload. Anthropic does not currently document a separate Fable rate-limit field. For forward compatibility, DockDeck recognizes the experimental aliases `seven_day_fable` and `fable`; it adds an `FBL` meter only when the payload actually contains one of them and never estimates Fable usage. [Fable availability is plan-specific](https://support.claude.com/en/articles/15424964-claude-fable-5-on-your-plan), and Fable 5 requires Claude Code `2.1.170` or later.

- More than 50% remaining (less than 50% used): selected text color
- 20–50% remaining (50–80% used): orange
- Less than 20% remaining (more than 80% used): red

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
```

This produces a universal, ad-hoc signed `DockDeck.app`, a versioned ZIP such as `DockDeck-0.1.0-macos-universal-unsigned.zip`, and its SHA-256 file without changing login items or the Keychain. Use these artifacts for local QA. Test the ZIP in a fresh macOS account or another Mac so its ad-hoc Accessibility identity does not conflict with the source-installed app.

Public binary distribution requires [Developer ID signing](https://developer.apple.com/support/developer-id/) and [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). A signing identity can be selected for a release candidate, but the result must still be notarized before publication:

```bash
DOCKDECK_SIGNING_IDENTITY="Developer ID Application: Example" ./scripts/package.sh
```

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

Update to the current Claude Code release, then start it once and complete sign-in:

```bash
claude --version
claude
```

Claude Code added `rate_limits` to status-line input in `2.1.80`. DockDeck follows the documented `five_hour` and `seven_day` fields and recommends the current Claude Code release because the status-line schema and account availability can change. Each window can be absent, and the payload appears only after the first API response for supported accounts.

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

## Security

Report suspected vulnerabilities through [GitHub private vulnerability reporting](https://github.com/bangwol/DockDeck/security/advisories/new), not a public issue. See [SECURITY.md](SECURITY.md) for the supported channels and reporting details.

## Project lineage

DockDeck began as a derivative of [Starboard v0.17.1](https://github.com/palamim/starboard/tree/v0.17.1) by Leonardo Palamim Cardozo. It is independently maintained and is not affiliated with or endorsed by the original project.

Starboard's MIT copyright and permission notice remain in [LICENSE](LICENSE). Dependency notices are recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [ThirdPartyLicenses](ThirdPartyLicenses).

## License

DockDeck is distributed under the [MIT License](LICENSE).
