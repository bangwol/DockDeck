# Getting started

DockDeck is currently a source-installed preview for macOS 13 or later. A
Developer ID-signed and notarized stable binary is not available yet.

## Requirements

| Requirement | Used for |
| --- | --- |
| Xcode Command Line Tools with Swift 5.9 or later | Building DockDeck |
| Accessibility permission | Precise Dock geometry and display tracking |
| [Codex CLI](https://github.com/openai/codex), signed in | Codex Usage values |
| [Claude Code](https://code.claude.com/docs/en/installation), signed in | Claude Usage values |
| [GitHub CLI](https://cli.github.com/), signed in | Project Pulse and GitHub Inbox |
| Docker CLI and a running local engine | Docker module |
| Built-in macOS Music app | Music module |

Only the build tools are required to launch DockDeck. Each optional integration
can remain disabled until its dependency is ready.

## Install and start at login

```bash
git clone https://github.com/bangwol/DockDeck.git
cd DockDeck
./scripts/install.sh
```

The installer builds and signs `~/Applications/DockDeck.app` and starts DockDeck
immediately. Fresh installs leave **Launch at Login** off. Change it in
**Settings → Startup** or the app menu; macOS may require approval in
**System Settings → General → Login Items**. Turning it off keeps the current
app running and removes the next-login registration. Reinstalling preserves
the choice, including a pending approval. Resetting DockDeck preferences does
not change this macOS setting.

An existing loaded DockDeck LaunchAgent is migrated to `SMAppService.mainApp`;
an unloaded legacy agent stays off. The old plist is backed up under
`~/Library/Application Support/DockDeck/legacy-login.*` and removed from
LaunchAgents after successful migration, preventing duplicate launches.
If registration fails, the installer retains the legacy configuration.

The installer prefers the sole Apple
Development identity in the login Keychain. A stable app path and signing
identity help macOS retain Accessibility approval across rebuilds.

If there is no single Apple Development identity, the installer creates a
self-signed local fallback. macOS can request Accessibility approval again after
a fallback-signed rebuild. To choose another installed identity:

```bash
DOCKDECK_SIGNING_IDENTITY="certificate name or SHA-1 hash" ./scripts/install.sh
```

Review the installer before running it. No certificate name or account data is
written to the repository.

## Permissions

Grant DockDeck access under **System Settings → Privacy & Security →
Accessibility**. Without it, DockDeck remains usable in fixed fallback
positions. A bottom-aligned Dock is tracked precisely; side-aligned Docks use
the fallback layout.

Schedule requests Calendar and Reminders separately and only when their buttons
are pressed. Service Monitor can prompt for Local Network access when checking a
private or local address. Music requests Automation access only after you enable
the module and press **Connect**. DockDeck does not require Full Disk Access,
Screen Recording, or Location access.

## Deck basics

Settings are divided into **General**, **Modules**, and **Interface**. Active
cards appear in the Left and Right Decks in cycle order; hidden cards stay in
the two-column **Inactive Modules** tray.

- Drag a card by its `≡` handle to reorder it, move it to the other Deck, or hide
  it in the tray.
- Drag an inactive card into a Deck to enable it there.
- Checking **Show** places a module in the Deck with fewer active cards, with a
  left-side tie break.
- Either Deck may be empty and therefore hidden. At least one module remains
  enabled so Settings stays reachable.
- DockDeck remembers the selected module in each Deck and the last Settings page.

## Manual and automatic navigation

Scroll over a compact Deck to cycle through every enabled module. Terminal uses
the wheel for module navigation while compact and for terminal scrollback while
focused or expanded.

Automatic Slide is off by default. Under **Settings → Decks**, mark at least two
modules in a Deck as **Auto** and choose a 5–300 second interval. Participating
Decks advance together on one shared timer. Selecting an unchecked module pauses
that Deck while the other can continue.

Auto Slide waits while a participating panel is hovered, a menu or detail view
is open, Settings is open, the display is off, or the Mac is locked. Terminal
participates only while compact, idle, and unfocused. Returning from interaction
starts a complete interval before the next transition. Reduce Motion is
respected.

## Panel controls

| Action | Result |
| --- | --- |
| Scroll over a compact Deck | Select the previous or next enabled module |
| Click Terminal | Focus and expand the terminal |
| Click outside focused Terminal | Return it to the Dock |
| Drag an expanded Terminal edge | Resize it; DockDeck remembers the result |
| Double-click a read-only module | Open a resizable detail view |
| Click Music transport buttons | Previous, play or pause, and next track |
| Right-click a Deck | Navigate, refresh, or open Settings |
| `⌘,` | Open Settings |
| `⌘R` | Refresh eligible visible data |
| `⌘T` | Open the terminal theme picker |
| `⌘E` | Toggle large-terminal mode |
| `⌘W` | Close the active DockDeck utility window |

Terminal-specific behavior is documented in the [Terminal guide](modules/terminal.md).

## Run without installing

```bash
swift test
swift run DockDeck
```

Enable Dock geometry diagnostics when investigating placement:

```bash
DOCKDECK_DEBUG=1 swift run DockDeck
```

Music Automation requires the packaged usage description and entitlement, so
test that module with `./scripts/install.sh`, not `swift run DockDeck`.

## Update or uninstall

Pull the desired source revision and run `./scripts/install.sh` again to rebuild
and restart the installed app.

```bash
./scripts/uninstall.sh
```

The uninstall script stops DockDeck and removes its login registration. It leaves the installed app, local
signing certificate, preferences, and build output in place. Remove those
separately only when you intend to discard them.

For local distributable bundles, checksums, preview tags, and notarization
requirements, see [Releases and versioning](releases.md).
