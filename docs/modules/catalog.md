# Module catalog

This guide covers modules whose setup and behavior are currently compact enough
to share one page. Disabled modules stop their timers, observers, network
requests, and subprocesses instead of merely hiding their panels.

## Service Monitor

Service Monitor sends a `HEAD` request every 15–120 seconds to up to four URLs.
If a server rejects `HEAD` with 405 or 501, DockDeck retries with a `GET` request
containing `Range: bytes=0-0`. Probes finish when headers arrive and cancel body
transfer, including when a server ignores Range.
Public endpoints must use HTTPS. Plain HTTP is accepted only for local names and
private or loopback addresses. This also applies to IPv6 literals, IPv4-mapped
IPv6 addresses, and alternate numeric IPv4 spellings. The packaged app declares
Apple's narrow `NSAllowsLocalNetworking` exception instead of disabling App
Transport Security globally. See Apple's
[App Transport Security guidance](https://developer.apple.com/documentation/security/preventing-insecure-network-connections)
and [`NSAllowsLocalNetworking` reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).

Checks use an ephemeral `URLSession` with caches, cookies, and credential
storage disabled. DockDeck stores service names and URLs in local preferences,
rejects URL user-info and common secret query fields, and does not use response
bodies. Do not place secrets in URL paths. Enable the module under
**Settings → Decks**, then configure it under **Settings → Service Monitor**.
Successful response times form a 15-minute in-memory trend line. The history is
never written to disk and disappears when DockDeck exits. Panel help includes
recent p50 and p95 latency when enough history exists.

The first failed check is shown as `WARN`; a second consecutive failure is
required before the service becomes `DOWN`. This avoids alerting on one
transient timeout. When macOS reports that the Mac has no internet connection,
the check is shown separately as `OFF` and does not count as an endpoint outage
or send a service-down notification. A connection dropped by one endpoint still
follows the `WARN` → `DOWN` confirmation path.

On macOS 15 or later, the first local-network check can show Apple's Local
Network permission prompt. Public HTTPS checks do not require this permission.
Change the decision under **System Settings → Privacy & Security → Local
Network**. See Apple's
[local network privacy technote](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

The Service Monitor detail keeps each endpoint's most recent failure start,
observed recovery duration, and last successful check in memory. Timing begins
with the first transient failure; confirmed-down notifications still require
the existing repeated-failure threshold. Local network offline does not start a
server outage. A changed URL resets its history, and time while polling is
paused is unobserved; recovery time means when a successful check was seen.

## Weather

Weather uses the [Open-Meteo Forecast API](https://open-meteo.com/en/docs) and
[Geocoding API](https://open-meteo.com/en/docs/geocoding-api). Search for a city
under **Settings → Weather**, select one result, and enable the module. DockDeck
does not use IP geolocation or request macOS Location permission. Double-click
Weather for current conditions and up to 12 hourly temperature, condition, and
precipitation-probability forecasts, displayed in the selected city's time zone.
Hourly fields use the same forecast request and polling interval; missing values
are shown as unavailable. Failed refreshes retain the previous result with an error.

DockDeck stores the selected city and coordinates in local preferences. Search
text and coordinates are sent over HTTPS only when searching or while the
enabled module refreshes. Requests use an ephemeral session without persistent
caches, cookies, or credential storage.

The built-in `api.open-meteo.com` service is keyless and limited to
non-commercial use. Its weather and location data are
[CC BY 4.0](https://open-meteo.com/en/license); attribution and licence links
remain under **Settings → Weather** and in the packaged third-party notices.
Review [Open-Meteo's terms and privacy details](https://open-meteo.com/en/terms)
before enabling the module. Commercial distributions need a suitable commercial
API arrangement and are not supported by the current keyless provider.

## World Clock

World Clock uses the macOS time-zone database and makes no network request.
Select the system time zone or an IANA time-zone identifier, listed with its
current GMT offset, under **Settings → World Clock**. Choose the system,
12-hour, or 24-hour format. It refreshes at minute boundaries and stops its
timer while disabled. Save up to three favorite time zones in Settings, and click
a saved zone to use it in the compact panel. Detail shows favorite clocks, local
time differences, and daylight-saving state using each observation date.

## Battery

Battery reads the internal power source through macOS IOKit and shows charge
level, charging state, and the system-provided time estimate when available. It
requires no permission or network access.

Select a 30-second, 60-second, or 5-minute interval under
**Settings → Battery**. Sampling stops while the module is disabled. Macs
without an internal battery show a neutral unavailable state. Double-click for
power source, charge state, and the time-to-full or remaining-time estimate.
Missing estimates explicitly say that macOS has not supplied them.

## Network

Network I/O is integrated into [System Stats](system-stats.md#network-consolidation).
Existing deck positions and the selected interface migrate automatically. The
System Stats detail window retains download/upload charts and connection status.

## Docker

Docker uses the installed local Docker CLI to show running, stopped, and
unhealthy container counts plus aggregate live CPU and memory for running
containers. Select a 5-second, 10-second, or 30-second interval under
**Settings → Docker**. The detail window lists up to 50 running containers,
ordered by CPU, with names and individual CPU/memory values from the same stats
response. Totals still include every returned container. Missing stats are shown
as unavailable; no extra polling stream or command is started.

DockDeck runs read-only `docker ps -a` and `docker stats --no-stream` commands.
The Docker engine and CLI must already be installed and running; DockDeck does
not start the engine, authenticate to a registry, read Docker credentials, or
modify containers. Output is bounded, parsed in memory, and discarded. A CLI or
engine failure leaves the last successful snapshot visible with an unavailable
state. Polling stops while the module is disabled and slows while hidden or in
macOS Low Power Mode. See Docker's official
[`docker container stats` reference](https://docs.docker.com/reference/cli/docker/container/stats/).

## Focus Timer

Focus Timer alternates between configurable 15–60 minute focus periods and
5–15 minute breaks. Start, pause, reset, or skip from the compact panel or its
context menu. Detail shows the completed focus count (retained until explicitly
reset; skipped periods do not count). The count is saved with timer state, without
a dated session history. Optional automatic phase advance is off by default.
After sleep or restart, it counts one completed phase and starts the next from
the current time, without replaying missed cycles. A running timer uses an absolute deadline, so it continues while
another module is selected and resumes correctly after DockDeck restarts.

DockDeck writes the phase, deadline, and remaining duration only when timer
state changes, not every second. The visible countdown refreshes once per second;
while hidden it uses a coarser cadence plus a separate one-shot completion
timer. macOS Low Power Mode further reduces display refreshes without delaying
the completion transition. Optional completion alerts are controlled under
**Settings → Notifications**.

## Compact readability

**Appearance → Larger text and fewer details** keeps compact labels at 10 pt or
larger without reducing their scale to fit. Long text truncates; existing
VoiceOver summaries and detail windows retain the full information. Custom Tile
hides its detail line, GitHub Inbox hides its notification preview, Docker moves
the stopped count to its detail view, and Usage moves reset times to detail and
hover text. Increase Contrast also enables the readable layout. macOS Reduce
Transparency and Increase Contrast make panel backgrounds opaque; Reduce Motion
continues to disable deck transitions.

## Local Ports

Up to five configured TCP ports show Open, Closed, or Unavailable using only
IPv4/IPv6 loopback connections. See [Local Ports](local-ports.md) for polling,
error meanings, and the distinction between reachability and service health.

## Finding modules and settings

**Find Module…** in the app or a module's context menu searches enabled modules.
The picker shows their side and which are currently displayed. Use Up/Down,
Return, Escape, or **Open Detail**. Those keys are handled only while the picker
window is key; Terminal input keeps its own behavior. Settings also searches
category names and descriptions, including disabled modules. Detail headers
provide **Module Settings…** and **Diagnostics…** for setup and connection checks.
`⌘W` closes the active settings, picker, or detail window.

## Deck profiles

Save up to eight named layouts under **Decks → Saved Deck Profiles**, then switch
from the **Deck Profiles** app menu. Profiles contain left/right order, enabled
modules and auto-slide selections/interval. Missing newer modules are added as
disabled entries when applying an older profile. Module data sources, commands,
credentials, and other settings stay outside profiles.

A Terminal session already running when a profile hides Terminal is retained
until the module is enabled again or the app quits. Once re-enabled, manually
disabling Terminal stops it normally. Other disabled modules stop their runtime.

**Export…** writes a versioned JSON archive. **Import…** validates IDs, duplicates,
names and intervals before showing the replacement preview; importing replaces
the saved library only after confirmation and leaves the current deck unchanged.
Archives are limited to 64 KiB and eight profiles. The local library is written
atomically at `~/Library/Application Support/DockDeck/deck-profiles.json`.
An unreadable existing library is preserved until a valid import replaces it.
