# Shortcuts actions

The installed app exposes three App Intents in macOS Shortcuts:

- **Refresh DockDeck** refreshes enabled modules and the Dock layout.
- **Start DockDeck Focus** starts or resumes a focus period. Repeating it never
  pauses or resets a running focus period. Starting during a break skips to
  focus. Enable Focus Timer in Decks first.
- **Switch DockDeck Profile** applies a saved profile by name, ignoring case and
  surrounding spaces. Missing profiles return an error; a running Terminal
  session remains alive when the profile hides it.

Each action opens DockDeck and uses the same app handlers as its controls.
No action accepts a shell command, path, or arbitrary URL. These actions do not
add a scheduler or run unless invoked from Shortcuts.

Source installation extracts metadata when full Xcode is selected with
`xcode-select`. Command Line Tools alone can build and install the app, but
cannot extract App Intents metadata; the installer reports that limitation.
Universal preview packaging requires full Xcode and includes the metadata
before signing. After installation, launch DockDeck once, then search for
DockDeck in the Shortcuts action browser.
