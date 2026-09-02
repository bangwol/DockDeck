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

DockDeck uses the space beside a bottom-aligned Dock for up to two compact module Decks. Assign Terminal, Usage, System Stats, Service Monitor, Weather, Schedule, World Clock, Battery, and Network to either side; each non-empty Deck shows one enabled module at a time. The terminal stays interactive whenever it is selected. Both Decks follow the Dock across displays, Spaces, and auto-hide transitions.

## Features

- Persistent [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) login shell with a compact `% ` prompt that does not change user shell files.
- Remaining or used Codex and Claude capacity from their supported local interfaces; either provider can be selected independently, with no browser cookies or private web endpoints.
- Two to four selectable local CPU, memory, disk, network-I/O, and temperature tiles with a configurable 1–10 second sampling interval.
- HTTPS service availability and latency checks for up to four user-configured endpoints.
- Current temperature, daily high and low, and conditions for a user-selected city.
- Current or next macOS Calendar event with a live elapsed-time bar.
- Local or selected-world-time display with system, 12-hour, and 24-hour formats.
- Internal battery level, power state, and the system-provided charge or discharge estimate.
- Local download and upload throughput for the current primary network interface.
- Dock-aware, symmetric placement across displays, Spaces, and auto-hide transitions.
- Independent manual module selection per Deck; right-click either Deck to select a module or open its settings.
- A shared sidebar-based Settings window with Deck cards, module detail pages, side placement, and independent module visibility controls.
- Disabled modules stop their background timers and subprocesses instead of merely hiding their panels.
- Click-to-focus terminal expansion, forgiving edge resizing, and remembered dimensions.
- Native Liquid Glass on macOS 26, with a translucent fallback and stronger terminal tint on earlier macOS.
- Manual large-terminal mode plus 20 themes with configurable fonts, tint, corner radius, and panel placement.

Keyboard shortcuts:

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘,` | Open the shared settings panel |
| `⌘R` | Refresh active module data and Dock layout |
| `⌘W` | Close the Settings window or theme picker |
| `⌘Q` | Quit DockDeck |

DockDeck reserves the Command-key shortcuts above plus the standard `⌘C`, `⌘V`, and `⌘A` editing shortcuts. `Ctrl` combinations, Option/Meta, Esc, Tab, arrow keys, Home/End, Delete, and F1–F12 continue through SwiftTerm's normal terminal input handling. Option acts as Meta by default. Page Up and Page Down follow SwiftTerm's terminal scrolling behavior unless the running terminal application requests cursor-key handling.

Click the terminal to expand it, then click elsewhere to return it to the Dock. Drag within 8 points of any expanded edge or corner to resize it; DockDeck restores those proportions the next time it expands. While a Deck is compact, hover it and scroll up or down to cycle through its enabled modules, including Terminal. Focused and large Terminal modes keep the wheel for normal terminal scrollback. Right-click either compact Deck to select a module directly. Modules never rotate automatically. Open the shared **Settings…** panel from either panel. `⌘E` selects Terminal and toggles a separate, fixed 75% large-terminal mode; its menu action is labeled **Return Terminal to Dock** while active. Running `exit` starts a fresh DockDeck login shell; use `⌘Q` to quit the app.

Settings are organized into **Decks**, module-specific pages, and **Appearance**. Drag a card from its `≡` handle within a Deck to set its cycle order or into the other Deck to change sides. Enabled modules stay above disabled modules; the same moves are available from each card's context menu. Move every card to one Deck if you want the other side completely empty and hidden. You can also swap the complete left and right Decks. At least one module remains enabled so Settings stays reachable. Disabled modules stop sampling and subprocesses. DockDeck remembers each Deck's selected module and the last Settings section you opened.

<p align="center">
  <a href="assets/dockdeck-decks-settings.png">
    <img src="assets/dockdeck-decks-settings.png" width="620" alt="DockDeck Decks settings with an empty left Deck and every module arranged on the right" />
  </a>
</p>

<p align="center">
  <sub>An empty Deck remains a drop target in Settings and is hidden beside the Dock.</sub>
</p>

## Reading System Stats

System Stats fits two to four equal-width tiles in the compact panel. Choose CPU utilization, Activity Monitor-style physical memory in use, startup-volume disk space in use, primary-interface download and upload rates, or temperature under **Settings → System Stats**. Percentage metrics use progress bars, Network I/O uses compact down/up rates, and Temperature combines a numeric value with a color-coded macOS thermal-pressure bar. Only selected metrics are sampled, and disabling the module stops all of its sampling.

Memory excludes inactive file cache and uses the VM internal, wired, and compressed page counts so its percentage follows Activity Monitor more closely. The other built-in readings use local macOS host, file-system, routing, and `ProcessInfo` APIs, require no additional permission, and perform no network requests.

Apple exposes only nominal/fair/serious/critical thermal pressure to ordinary apps, not sensor degrees. When the separately installed [Stats](https://github.com/exelban/stats) app has its expected Apple-signed identity, DockDeck can run Stats's bundled read-only `smc list -t` command at most once every 15 seconds and display the hottest available CPU-core value for the detected Apple-chip generation. DockDeck neither bundles nor modifies Stats, never invokes its fan-control commands, and shows `--°` when the validated tool is unavailable. This optional adapter relies on Stats's undocumented SMC source and may need adjustment after a macOS or Stats update. DockDeck does not report system-wide GPU utilization because no supported public source is available.

## Monitoring services

Service Monitor sends a `HEAD` request every 15–120 seconds to up to four URLs. Public endpoints must use HTTPS. Plain HTTP is accepted only for local names and private or loopback addresses; the packaged app declares Apple's narrow `NSAllowsLocalNetworking` exception instead of disabling App Transport Security globally. See Apple's [App Transport Security guidance](https://developer.apple.com/documentation/security/preventing-insecure-network-connections) and [`NSAllowsLocalNetworking` reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Checks use an ephemeral `URLSession` with caches, cookies, and credential storage disabled. DockDeck stores service names and URLs in local preferences, rejects URL user-info and common secret query fields, and does not use response bodies. Do not place secrets in URL paths. Enable and configure the module under **Settings → Decks → Service Monitor**.

On macOS 15 or later, the first local-network check can show Apple's Local Network permission prompt. DockDeck includes a purpose string and waits for the decision; public HTTPS checks do not require this permission. The permission can be changed later under **System Settings → Privacy & Security → Local Network**. See Apple's [local network privacy technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

## Checking weather

Weather uses the [Open-Meteo Forecast API](https://open-meteo.com/en/docs) and [Geocoding API](https://open-meteo.com/en/docs/geocoding-api). Search for a city under **Settings → Weather**, select one result, and enable the module. DockDeck does not use IP geolocation or request macOS Location permission. It stores the selected city and coordinates in local preferences; search text and coordinates are sent over HTTPS only when searching or while the enabled module refreshes. Requests use an ephemeral session without persistent caches, cookies, or credential storage.

The built-in `api.open-meteo.com` service is keyless and limited to non-commercial use. Its weather and location data are [CC BY 4.0](https://open-meteo.com/en/license); attribution and licence links remain under **Settings → Weather** and in the packaged third-party notices. DockDeck rounds temperatures and maps weather codes to labels and SF Symbols for display. Review [Open-Meteo's terms and privacy details](https://open-meteo.com/en/terms) before enabling the module; commercial distributions need a suitable commercial API arrangement and are not supported by the current keyless provider.

## Reading your schedule

Schedule reads upcoming events through Apple's EventKit framework and shows the current event, elapsed progress, or the next event. Enable **Settings → Decks → Schedule**, then press **Request Access** under **Settings → Schedule**. DockDeck never triggers the system Calendar permission prompt merely by launching or enabling the module. On current macOS releases, Apple requires full Calendar access to fetch events even for a read-only app; DockDeck never calls EventKit's save, edit, or delete APIs. See Apple's [EventKit access guidance](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents%28completion%3A%29) and [calendar purpose-string reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription).

DockDeck retains only event title, start and end times, all-day state, and calendar name in memory. It persists only selected calendar identifiers and module settings, does not store or log events, and makes no calendar-related network request. Disabling Schedule stops its timer, removes its EventKit observer, releases the event store, and clears the in-memory event list. Google and other accounts appear only when their calendars are enabled for macOS under **System Settings → Internet Accounts**; signing into a provider in Safari alone does not connect it to EventKit.

## Showing another time zone

World Clock uses the macOS time-zone database and makes no network request. Select the system time zone or an IANA time-zone identifier, listed with its current GMT offset, under **Settings → World Clock**, then choose the system, 12-hour, or 24-hour format. It refreshes at minute boundaries and stops its timer while disabled.

## Checking battery status

Battery reads the internal power source through macOS IOKit and shows charge level, charging state, and the system-provided time estimate when available. It requires no permission or network access. Select a 30-second, 60-second, or 5-minute interval under **Settings → Battery**; sampling stops while the module is disabled. Macs without an internal battery show a neutral unavailable state.

## Watching network throughput

Network calculates download and upload rates from macOS's 64-bit byte counters for the current primary interface. It does not open a connection or inspect traffic, IP addresses, hostnames, or packet contents. Select a 1-second, 2-second, or 5-second interval under **Settings → Network**; sampling and counter retention stop while the module is disabled. The primary interface name remains available in the panel help and accessibility text.

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

Each meter shows the provider-supplied reset time in the Mac's local time zone. A provider with one returned window uses a two-column header: usage is centered in the first column and its reset time in the second. Providers with two or three windows place each reset below its matching bar. Codex supplies `resetsAt` through its [app-server rate-limit response](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt), while Claude Code supplies `resets_at` through its [status-line data](https://code.claude.com/docs/en/statusline#rate-limit-usage). Resets later today use `HH:mm`; a different day uses `M/D HH:mm`. `--` means that the provider did not supply a timestamp. The full localized date and time remain available by hovering the meter.

Codex displays whichever 5-hour and weekly windows the signed-in account returns. DockDeck uses the returned durations instead of guessing the plan. OpenAI documents a shared 5-hour window for local and cloud tasks and notes that weekly limits may also apply in the [Codex pricing guide](https://learn.chatgpt.com/docs/pricing).

Claude displays the officially documented 5-hour and weekly fields available in Claude Code's status-line payload. Anthropic does not currently document a separate Fable rate-limit field. For forward compatibility, DockDeck recognizes the experimental aliases `seven_day_fable` and `fable`; it adds an `FBL` meter only when the payload actually contains one of them and never estimates Fable usage. [Fable availability is plan-specific](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan), and Fable 5 requires Claude Code `2.1.170` or later.

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
| System Stats | macOS host, file-system, routing, and `ProcessInfo` APIs; optional validated local Stats SMC tool | Samples only selected CPU, memory, disk, network-counter, and temperature values locally; makes no network request |
| Service Monitor | User-configured HTTPS or local HTTP URLs | Sends cookie-free `HEAD` requests; rejects common URL credential fields before local storage |
| Weather | Open-Meteo forecast and geocoding APIs | Sends submitted searches and selected coordinates over HTTPS only while used; stores the selected city locally |
| Schedule | Apple EventKit | Reads selected calendars into memory after explicit permission; never saves, edits, logs, or uploads events |
| World Clock | macOS time-zone database | Formats time locally and stops its minute timer while disabled |
| Battery | macOS IOKit | Reads the internal power source locally; does not read battery identifiers or serial numbers |
| Network | macOS routing and configuration APIs | Reads only primary-interface byte counters; does not inspect network traffic or destinations |

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

OpenAI and Claude marks identify their respective usage providers only. DockDeck is not affiliated with or endorsed by OpenAI or Anthropic. The marks remain the property of their respective owners and are not covered by DockDeck's MIT license; provenance is recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

DockDeck is distributed under the [MIT License](LICENSE).
