# Local Ports

Enable **Local Ports** under Decks and enter up to five unique TCP ports in
Settings. Defaults are `3000`, `5173`, and `8080`. Refresh options are 15, 30,
and 60 seconds; hidden panels and constrained power states poll less often.

The module connects only to `127.0.0.1` and `::1`. **Open** means either TCP
connection succeeded. **Closed** requires both connections to be refused.
Permission errors, timeouts, and other system errors are **Unavailable** and
appear with an explanation in the detail window. This tests TCP reachability,
not HTTP health; no application payload is sent and no process is stopped.
Process ownership is not collected in this version.

Each nonblocking connection waits at most 250 ms. Sockets close after every
probe. Disabling a module stops scheduled checks and rejects late results; a
check already in progress finishes within its bounded probe loop. No external
CLI, elevated privilege, local network host discovery, or remote host setting
is involved.
