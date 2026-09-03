# Module catalog

This guide covers modules whose setup and behavior are currently compact enough
to share one page. Disabled modules stop their timers, observers, network
requests, and subprocesses instead of merely hiding their panels.

## Service Monitor

Service Monitor sends a `HEAD` request every 15–120 seconds to up to four URLs.
If a server rejects `HEAD` with 405 or 501, DockDeck retries with a `GET` request
containing `Range: bytes=0-0`; it still discards the body.
Public endpoints must use HTTPS. Plain HTTP is accepted only for local names and
private or loopback addresses. The packaged app declares Apple's narrow
`NSAllowsLocalNetworking` exception instead of disabling App Transport Security
globally. See Apple's
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

## Weather

Weather uses the [Open-Meteo Forecast API](https://open-meteo.com/en/docs) and
[Geocoding API](https://open-meteo.com/en/docs/geocoding-api). Search for a city
under **Settings → Weather**, select one result, and enable the module. DockDeck
does not use IP geolocation or request macOS Location permission.

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
timer while disabled.

## Battery

Battery reads the internal power source through macOS IOKit and shows charge
level, charging state, and the system-provided time estimate when available. It
requires no permission or network access.

Select a 30-second, 60-second, or 5-minute interval under
**Settings → Battery**. Sampling stops while the module is disabled. Macs
without an internal battery show a neutral unavailable state.

## Network

Network calculates download and upload rates from macOS's 64-bit byte counters
for the current primary interface. A native `NWPathMonitor` supplies offline,
Wi-Fi, wired, cellular, metered, and Low Data status without contacting a probe
server. DockDeck does not inspect traffic, IP addresses, hostnames, or packet
contents.

Select a 1-second, 2-second, or 5-second interval under
**Settings → Network**. Sampling and counter retention stop while the module is
disabled. The primary interface name remains available in panel help and
accessibility text. Download and upload trend lines retain at most 15 minutes or
900 samples in memory and are never written to disk. Low Data Mode applies the
same reduced sampling cadence as Low Power Mode.

## Docker

Docker uses the installed local Docker CLI to show running, stopped, and
unhealthy container counts plus aggregate live CPU and memory for running
containers. Select a 5-second, 10-second, or 30-second interval under
**Settings → Docker**.

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
context menu. A running timer uses an absolute deadline, so it continues while
another module is selected and resumes correctly after DockDeck restarts.

DockDeck writes the phase, deadline, and remaining duration only when timer
state changes, not every second. The visible countdown refreshes once per second;
while hidden it uses a coarser cadence plus a separate one-shot completion
timer. macOS Low Power Mode further reduces display refreshes without delaying
the completion transition. Optional completion alerts are controlled under
**Settings → Notifications**.
