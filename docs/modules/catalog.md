# Module catalog

This guide covers modules whose setup and behavior are currently compact enough
to share one page. Disabled modules stop their timers, observers, network
requests, and subprocesses instead of merely hiding their panels.

## Service Monitor

Service Monitor sends a `HEAD` request every 15–120 seconds to up to four URLs.
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

## Schedule

Schedule reads upcoming events through Apple's EventKit framework and shows the
current event, elapsed progress, or the next event. Enable Schedule under
**Settings → Decks**, then press **Request Access** under
**Settings → Schedule**.

DockDeck never triggers the Calendar permission prompt merely by launching or
enabling the module. Current macOS releases require full Calendar access to
fetch events even for a read-only app; DockDeck never calls EventKit's save,
edit, or delete APIs. See Apple's
[EventKit access guidance](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents%28completion%3A%29)
and [calendar purpose-string reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nscalendarsfullaccessusagedescription).

DockDeck retains only event title, start and end times, all-day state, and
calendar name in memory. It persists only selected calendar identifiers and
module settings, does not store or log events, and makes no calendar-related
network request. Disabling Schedule stops its timer, removes its EventKit
observer, releases the event store, and clears the in-memory event list.

Google and other accounts appear only when their calendars are enabled for
macOS under **System Settings → Internet Accounts**. Signing into a provider in
Safari alone does not connect it to EventKit.

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
for the current primary interface. It does not open a connection or inspect
traffic, IP addresses, hostnames, or packet contents.

Select a 1-second, 2-second, or 5-second interval under
**Settings → Network**. Sampling and counter retention stop while the module is
disabled. The primary interface name remains available in panel help and
accessibility text.
