# Music

Music shows and controls playback from the built-in macOS Music app. It does
not control Spotify, browser players, or the system-wide Now Playing session.

## Enable and connect

1. Enable **Music** under **Settings → Decks**.
2. Open **Settings → Music** and press **Open & Connect** or **Connect**.
3. Approve the macOS Automation request for DockDeck to control Music.

Enabling the module alone never opens Music or shows a permission prompt. If
access was denied, enable DockDeck under **System Settings → Privacy & Security
→ Automation**, then refresh the module.

Music Automation requires the usage description and hardened-runtime
entitlement in the installed app. Use `./scripts/install.sh` for testing;
`swift run DockDeck` does not contain that packaged metadata.

## Display and controls

The compact panel shows the current song, artist, playback state, and progress.
Use its previous, play/pause, and next buttons. Double-click the panel for a
resizable detail view, or right-click it for the same transport controls and a
link to Music.

DockDeck samples every 5 seconds while the module is visible and every 30
seconds in the background. Low Power Mode or serious thermal pressure extends
those intervals to 15 and 90 seconds. Sampling stops while the module is
disabled or while the display or login session is inactive.

## Data and privacy

DockDeck uses the public Apple Event scripting interface exposed by Music.app.
It reads only bounded song title, artist, album, duration, player position, and
player state values. Those values remain in memory and are not logged, saved,
or sent over the network.

The module does not use MusicKit, Apple Music web APIs, an Apple developer
token, or Apple ID credentials. Music.app remains responsible for its own
library, account, streaming, and network activity.

## Troubleshooting

- **Music is not running:** press **Open & Connect**.
- **Music access denied:** verify DockDeck under macOS Automation settings.
- **Nothing playing:** start a playable item in Music, then press Refresh.
- **Music automation unavailable:** reinstall with `./scripts/install.sh` so
  the app has the required permission description and entitlement.
