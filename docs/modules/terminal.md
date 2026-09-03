# Terminal

DockDeck embeds a persistent
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) login shell. It uses a
compact `% ` prompt without changing the user's normal shell startup files.

## Compact and focused modes

Click the compact terminal to focus and expand it. Click elsewhere to return it
to the Dock. Drag within 8 points of any expanded edge or corner to resize it;
DockDeck remembers those proportions for the next expansion.

While a Deck is compact, hover it and scroll up or down to cycle through its
enabled modules, including Terminal. Focused and large Terminal modes reserve
the wheel for normal terminal scrollback. Right-click a compact Deck to select a
module directly. Optional Automatic Slide can rotate checked modules, including
Terminal. Terminal rotates only while it is compact, visible,
unfocused, and not hovered. Clicking or enlarging it pauses automatic slides;
returning it to the Dock starts a complete interval before rotation resumes.
Automatic selection never takes keyboard focus.

`⌘E` selects Terminal and toggles a separate, fixed 75% large-terminal mode.
The menu action changes to **Return Terminal to Dock** while that mode is
active.

Running `exit` starts a fresh DockDeck login shell. Use `⌘Q` to quit the
application.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘E` | Toggle the manual large terminal mode |
| `⌘T` | Open the theme picker |
| `⌘,` | Open the shared settings panel |
| `⌘R` | Refresh active module data and Dock layout |
| `⌘W` | Close the Settings window or theme picker |
| `⌘Q` | Quit DockDeck |

DockDeck reserves those Command-key shortcuts plus the standard `⌘C`, `⌘V`,
and `⌘A` editing shortcuts. `Ctrl` combinations, Option/Meta, Esc, Tab, arrow
keys, Home/End, Delete, and F1–F12 continue through SwiftTerm's normal input
handling. Option acts as Meta by default. Page Up and Page Down follow terminal
scrolling behavior unless the running application requests cursor-key handling.

## Settings and local files

Use **Settings → Terminal** to configure the focused size, font, tint, and
corner radius. The theme picker provides 20 terminal themes.

DockDeck writes a small zsh startup hook to:

```text
~/Library/Caches/DockDeck/Shell/.zshenv
```

It preserves the user's normal zsh startup files and changes only the DockDeck
terminal prompt. The directory uses `0700` permissions and the hook uses `0600`
permissions.
