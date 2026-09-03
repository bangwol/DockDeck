# Custom Tile

Custom Tile displays bounded output from one trusted executable or macOS
Shortcut. It is intended for small local summaries such as a build state,
queue length, or environment status—not an interactive terminal.

## Configure a source

Enable **Custom Tile** under **Settings → Decks**, then open
**Settings → Custom Tile**.

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

Choose a 1-, 5-, or 15-minute interval. Disabling the module stops its timer and
subprocesses. Hidden polling is three times slower, and macOS Low Power Mode
adds another two-times multiplier. `⌘R` requests an immediate run while the
module is enabled.
