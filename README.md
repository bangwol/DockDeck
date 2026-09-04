<p align="center">
  <img src="assets/AppIcon.png" width="112" height="112" alt="DockDeck app icon" />
</p>

<h1 align="center">DockDeck</h1>

<p align="center">
  Compact developer tools that live beside your macOS Dock.
</p>

<p align="center">
  <a href="assets/dockdeck-overview.png">
    <img src="assets/dockdeck-overview.png" alt="DockDeck panels beside the macOS Dock" />
  </a>
</p>

DockDeck turns the free space beside a bottom-aligned Dock into two configurable
module decks. It follows the Dock across displays, Spaces, and auto-hide changes
without taking over the menu bar or desktop.

## Highlights

- Keep a persistent interactive terminal beside the Dock.
- See Codex and Claude limits, remaining capacity, and reset times.
- Arrange 15 modules between left and right decks with drag and drop.
- Scroll manually or auto-slide selected modules on a shared timer.
- Open resizable detail views without losing the compact deck layout.
- Stop disabled work and reduce sampling in Low Power Mode, while inactive, and
  under thermal pressure.

## Modules

| Group | Modules |
| --- | --- |
| Core | Terminal, Usage |
| System | System Stats, Battery, Network, Weather, World Clock |
| Media | Music |
| Work | Schedule, Focus Timer, Project Pulse, GitHub Inbox |
| Operations | Service Monitor, Docker, Custom Tile |

See the [module guide index](docs/README.md#module-guides) for setup, data
sources, refresh behavior, and privacy details.

## Install

DockDeck currently ships as a source-installed preview for macOS 13 or later.
Install Xcode Command Line Tools, then run:

```bash
git clone https://github.com/bangwol/DockDeck.git
cd DockDeck
./scripts/install.sh
```

The script builds `~/Applications/DockDeck.app`, starts it, and registers it for
future logins. Grant Accessibility access when macOS asks so DockDeck can follow
the Dock precisely. Without that permission, the panels use fixed fallback
positions.

For a one-time development run instead:

```bash
swift run DockDeck
```

See [Getting started](docs/getting-started.md) for permissions, optional CLI
integrations, controls, updating, and uninstalling.

## Use

| Action | Result |
| --- | --- |
| Scroll over a compact deck | Move between enabled modules |
| Click Terminal | Focus and expand the terminal |
| Double-click a read-only module | Open its resizable detail view |
| Right-click a deck | Navigate modules, refresh, or open Settings |
| Drag cards in **Settings → Decks** | Reorder, move, enable, or hide modules |

<p align="center">
  <a href="assets/dockdeck-decks-settings.png">
    <img src="assets/dockdeck-decks-settings.png" width="620" alt="DockDeck Decks settings" />
  </a>
</p>

## Documentation

- [Getting started and Deck controls](docs/getting-started.md)
- [Module guides](docs/README.md#module-guides)
- [Claude Code monitoring](docs/integrations/claude-code.md)
- [Data sources, storage, and privacy](docs/privacy.md)
- [Diagnostics](docs/diagnostics.md)
- [Preview releases and versioning](docs/releases.md)
- [Contributing](CONTRIBUTING.md) and [security policy](SECURITY.md)

## Privacy

DockDeck is local-first. It does not read browser cookies, browser credential
stores, or private web endpoints. Optional integrations use macOS frameworks or
locally installed official CLIs, and their bounded results remain in memory
unless a guide explicitly describes a saved setting. See [Privacy and data
sources](docs/privacy.md) for the complete per-module table.

## Preview status

There is no Developer ID-signed and notarized stable binary yet. Source install
is the recommended path; GitHub preview artifacts are ad-hoc signed,
unnotarized technical builds. See the [release policy](docs/releases.md) before
distributing a package.

## Lineage and license

DockDeck began as a derivative of
[Starboard v0.17.1](https://github.com/palamim/starboard/tree/v0.17.1) and is now
independently maintained. It is not affiliated with the original project,
OpenAI, or Anthropic. Provider marks identify integrations only.

DockDeck is distributed under the [MIT License](LICENSE). Starboard's notice is
preserved there; dependency and asset notices are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
