<p align="center">
  <img src="assets/AppIcon.png" width="112" height="112" alt="DockDeck app icon" />
</p>

<h1 align="center">DockDeck</h1>

<p align="center">
  A terminal and compact developer module deck that lives beside your macOS Dock.
</p>

<p align="center">
  <a href="assets/dockdeck-overview.png">
    <img src="assets/dockdeck-overview.png" alt="DockDeck terminal and remaining-usage panels beside the macOS Dock" />
  </a>
</p>

<p align="center">
  <sub>Compact terminal and configurable Codex and Claude usage beside the macOS Dock. Open the image for full resolution.</sub>
</p>

DockDeck uses the space beside a bottom-aligned Dock for two compact developer panels. The terminal stays interactive while a read-only Deck hosts Usage, System Stats, Service Monitor, Weather, and Schedule modules; either Deck can be hidden or placed on either side. Both follow the Dock across displays, Spaces, and auto-hide transitions.

## Features

- Persistent [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) login shell with a compact `% ` prompt that does not change user shell files.
- Remaining or used Codex and Claude capacity from their supported local interfaces; either provider can be selected independently, with no browser cookies or private web endpoints.
- Local CPU, memory, and disk utilization with a configurable 1–10 second sampling interval.
- HTTPS service availability and latency checks for up to four user-configured endpoints.
- Current temperature, daily high and low, and conditions for a user-selected city.
- Current or next macOS Calendar event with a live elapsed-time bar.
- Dock-aware, symmetric placement across displays, Spaces, and auto-hide transitions.
- Read-only module Deck with manual module switching; right-click it to select a module or open its settings.
- A shared sidebar-based Settings window with Deck cards, module detail pages, side placement, and independent module visibility controls.
- Disabled modules stop their background timers and subprocesses instead of merely hiding their panels.
- Click-to-focus terminal expansion, native edge resizing, and remembered dimensions.
- Native Liquid Glass on macOS 26, with a translucent fallback and stronger terminal tint on earlier macOS.
- Manual large-terminal mode plus 20 themes with configurable fonts, tint, corner radius, and panel placement.

Keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘,` | Open the shared settings panel |
| `⌘R` | Refresh active module data and Dock layout |
| `⌘Q` | Quit DockDeck |

DockDeck reserves the Command-key shortcuts above plus the standard `⌘C`, `⌘V`, and `⌘A` editing shortcuts. `Ctrl` combinations, Option/Meta, Esc, Tab, arrow keys, Home/End, Delete, and F1–F12 continue through SwiftTerm's normal terminal input handling. Option acts as Meta by default. Page Up and Page Down follow SwiftTerm's terminal scrolling behavior unless the running terminal application requests cursor-key handling.

Click the terminal to expand it, then click elsewhere to return it to the Dock. Drag any edge to resize it; DockDeck restores those proportions the next time it expands. Right-click the read-only Deck to switch between enabled modules. Open the shared **Settings…** panel from either panel. `⌘E` toggles a separate, fixed 75% large-terminal mode; its menu action is labeled **Return Terminal to Dock** while active. Running `exit` starts a fresh DockDeck login shell; use `⌘Q` to quit the app.

Settings are organized into **Decks**, module-specific pages, and **Appearance**. Decks show the modules assigned to each side of the Dock, enable or disable each module, and swap the complete left and right Decks. At least one module remains visible so Settings stays reachable. Disabled modules stop sampling and subprocesses. DockDeck remembers the last Settings section you opened.

## Reading System Stats

System Stats reports CPU utilization since the previous sample, physical memory in use, and startup-volume disk space in use. It uses local macOS host and file-system APIs, requires no additional permission, and performs no network requests. Enable it under **Settings → Decks**, then right-click the read-only Deck to switch modules.

## Monitoring services

Service Monitor sends a `HEAD` request every 15–120 seconds to up to four URLs. Public endpoints must use HTTPS. Plain HTTP is accepted only for local names and private or loopback addresses; the packaged app declares Apple's narrow `NSAllowsLocalNetworking` exception instead of disabling App Transport Security globally. See Apple's [App Transport Security guidance](https://developer.apple.com/documentation/security/preventing-insecure-network-connections) and [`NSAllowsLocalNetworking` reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Checks use an ephemeral `URLSession` with caches, cookies, and credential storage disabled. DockDeck stores service names and URLs in local preferences, rejects URL user-info and common secret query fields, and does not use response bodies. Do not place secrets in URL paths. Enable and configure the module under **Settings → Decks → Service Monitor**.

On macOS 15 or later, the first local-network check can show Apple's Local Network permission prompt. DockDeck includes a purpose string and waits for the decision; public HTTPS checks do not require this permission. The permission can be changed later under **System Settings → Privacy & Security → Local Network**. See Apple's [local network privacy technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Checking weather

Weather uses the [Open-Meteo Forecast API](https://open-meteo.com/en/docs) and [Geocoding API](https://open-meteo.com/en/docs/geocoding-api). Search for a city under **Settings → Weather**, select one result, and enable the module. DockDeck does not use IP geolocation or request macOS Location permission. It stores the selected city and coordinates in local preferences; search text and coordinates are sent over HTTPS only when searching or while the enabled module refreshes. Requests use an ephemeral session without persistent caches, cookies, or credential storage.

The built-in `api.open-meteo.com` service is keyless and limited to non-commercial use. Its weather and location data are [CC BY 4.0](https://open-meteo.com/en/license), so the compact panel and Settings include the required Open-Meteo attribution link. DockDeck rounds temperatures and maps weather codes to labels and SF Symbols for display. Review [Open-Meteo's terms and privacy details](https://open-meteo.com/en/terms) before enabling the module; commercial distributions need a suitable commercial API arrangement and are not supported by the current keyless provider.

## Reading your schedule

Schedule reads upcoming events through Apple's EventKit framework and shows the current event, elapsed progress, or the next event. Enable **Settings → Decks → Schedule**, then press **Request Access** under **Settings → Schedule**. DockDeck never triggers the system Calendar permission prompt merely by launching or enabling the module. On current macOS releases, Apple requires full Calendar access to fetch events even for a read-only app; DockDeck never calls EventKit's save, edit, or delete APIs. See Apple's [EventKit access guidance](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents%28completion%3A%29) and [calendar purpose-string reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription).

DockDeck retains only event title, start and end times, all-day state, and calendar name in memory. It persists only selected calendar identifiers and module settings, does not store or log events, and makes no calendar-related network request. Disabling Schedule stops its timer, removes its EventKit observer, releases the event store, and clears the in-memory event list. Google and other accounts appear only when their calendars are enabled for macOS under **System Settings → Internet Accounts**; signing into a provider in Safari alone does not connect it to EventKit.

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
| System Stats | macOS host and file-system APIs | Samples CPU, physical memory, and startup-volume capacity locally |
| Service Monitor | User-configured HTTPS or local HTTP URLs | Sends cookie-free `HEAD` requests; rejects common URL credential fields before local storage |
| Weather | Open-Meteo forecast and geocoding APIs | Sends submitted searches and selected coordinates over HTTPS only while used; stores the selected city locally |
| Schedule | Apple EventKit | Reads selected calendars into memory after explicit permission; never saves, edits, logs, or uploads events |

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
