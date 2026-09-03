# System Stats

System Stats fits two to four equal-width tiles in the compact panel. Select the
metrics and a 1–10 second sampling interval under
**Settings → System Stats**. Only selected metrics are sampled, and disabling
the module stops all sampling.

| Metric | Reading |
| --- | --- |
| CPU | Processor utilization calculated from consecutive macOS host tick counters |
| Memory | Activity Monitor-style physical memory in use |
| Disk | Used capacity on the startup volume |
| Network I/O | Download and upload rates on the current primary interface |
| Temperature | Numeric sensor value when the validated optional reader is available, plus macOS thermal pressure |

Percentage metrics use progress bars until enough samples exist, then CPU and
memory use compact trend lines. Network I/O uses compact down/up rates and a
combined-transfer trend. Temperature combines a numeric value with a
color-coded thermal-pressure bar.

CPU, memory, and network histories cover only the latest 15 minutes and at most
900 samples. They stay in memory, reset when DockDeck exits, and are discarded
if the system clock moves backwards. The separate Network module keeps distinct
download and upload histories under the same limits.

## Memory semantics on macOS

DockDeck follows the **Memory Used** value in macOS Activity Monitor:

```text
used pages = internal_page_count + wire_count + compressor_page_count
used bytes = used pages × vm_page_size
```

This excludes file-backed cache by using the kernel's anonymous
`internal_page_count`, but it includes purgeable anonymous memory. That choice
matches Activity Monitor's headline value. It can read higher than utilities
that treat purgeable memory as immediately available.

For example, Stats 3.0.11 subtracts both `purgeable_count` and
`external_page_count` in its
[RAM calculation](https://github.com/exelban/stats/blob/v3.0.11/Modules/RAM/readers.swift).
The two percentages therefore answer slightly different questions:

- DockDeck and Activity Monitor: physical memory currently classified as used
- Utilities that subtract purgeable memory: memory that is not readily reclaimable

Use Activity Monitor's memory-pressure graph, rather than the percentage alone,
to judge whether macOS is actually constrained. Cached and purgeable memory can
be reclaimed when another workload needs it. See Apple's
[Activity Monitor memory guide](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac).

## Temperature and GPU limitations

Apple exposes nominal, fair, serious, and critical thermal pressure to ordinary
apps, not sensor degrees. When the separately installed
[Stats](https://github.com/exelban/stats) app has its expected Apple-signed
identity, DockDeck can run Stats's bundled read-only `smc list -t` command at
most once every 15 seconds. It displays the hottest available CPU-core value
for the detected Apple-chip generation.

DockDeck neither bundles nor modifies Stats, never invokes its fan-control
commands, and shows `--°` when the validated tool is unavailable. This optional
adapter relies on Stats's undocumented SMC source and may need adjustment after
a macOS or Stats update.

DockDeck does not report system-wide GPU utilization because macOS does not
provide a supported public source suitable for this module.

## Data and permissions

The built-in readings use local macOS host, file-system, routing, and
`ProcessInfo` APIs. They require no additional permission and make no network
requests. The optional temperature adapter launches only the validated local
Stats SMC reader.
