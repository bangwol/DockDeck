# Custom Tile

Each Custom Tile displays bounded output from one trusted executable or macOS
Shortcut. Three independent slots are available: Custom Tile, Custom Tile 2, and
Custom Tile 3. Existing configurations remain in the first slot. It is intended for small local summaries such as a build state,
queue length, or environment status—not an interactive terminal.

## Configure a source

Open **Settings → Custom Tile** (or slot 2 or 3) to prepare a source, even while
the slot is disabled. **Text example** and **JSON example** fill a small local
`/usr/bin/printf` example. **Test once** explicitly runs the current configuration
and shows the parsed value or error. Editing an inactive slot does not execute it.

Enable the slot under **Settings → Decks** for automatic updates. Each slot has
its own title, source, interval, and last result. Double-click a tile to see its
full result, last successful update, and **Run again**. If a later run fails, the
last successful value remains visible with a warning and the failure reason.

### Executable

Enter an absolute executable path and up to 16 arguments, one per line. DockDeck
passes the arguments directly to `Process`; it does not invoke a shell. Pipes,
redirection, globbing, command substitution, and shell variables are therefore
not interpreted. If shell behavior is required, create and review a script,
make it executable, and select that script explicitly.

### macOS Shortcut

Enter the exact Shortcut name. DockDeck invokes the built-in command-line form:

```text
/usr/bin/shortcuts run <name>
```

The Shortcut and any permissions or side effects it contains remain under the
user's control. See Apple's
[Shortcuts command-line guide](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac).

## Output formats

Plain UTF-8 output uses the first line as the value and the optional second line
as detail:

```text
42%
Ready
```

JSON provides optional title and SF Symbol fields. `value` is required and all
fields must be strings:

```json
{
  "title": "Build",
  "value": "Passing",
  "detail": "main",
  "symbol": "checkmark.circle"
}
```

Text is flattened to one line per field and bounded for the compact panel. An
invalid or unknown SF Symbol falls back to the command icon. Malformed JSON,
non-UTF-8 data, empty output, or a nonzero exit status produces an unavailable
state rather than displaying untrusted raw data.

## Runtime and security boundaries

- No shell is used by DockDeck.
- The executable path must be absolute and executable.
- At most 16 arguments of 1,024 characters each are stored.
- A run is stopped after 5 seconds.
- Combined stdout and stderr are limited to 32 KiB; only stdout is parsed.
- Output remains in memory and is not logged or saved.
- The configured title, source, executable path, arguments, Shortcut name, and
  interval are stored in local preferences.

Do not place passwords, tokens, or other secrets in arguments. A selected
program or Shortcut runs with the macOS user's file, network, and environment
access, so configure only software you trust. Runtime and output limits reduce
accidental resource use; they are not a security sandbox.

Choose a 1-, 5-, or 15-minute interval. Disabling the module stops scheduled runs and discards late results; an already
running command remains subject to the 5-second limit. Hidden polling is three times slower, and macOS Low Power Mode
adds another two-times multiplier. `⌘R` requests an immediate run for every enabled Custom Tile slot.
