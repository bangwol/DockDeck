# Schedule and Reminders

Schedule combines read-only macOS Calendar events with optional incomplete
Reminders. Enable the module under **Settings → Decks**, then configure each
source independently under **Settings → Schedule**.

## What the panel shows

The compact panel chooses one relevant item in this order:

1. A timed event happening now
2. The most recently overdue Reminder
3. An all-day event happening now
4. The next event or due Reminder, whichever comes first

Current events include an elapsed-time bar. Reminder rows show their due state,
date or time, and list name. DockDeck reads incomplete Reminders due within the
last seven days or next 48 hours; items without a due date are not shown. The
same 48-hour horizon applies to upcoming Calendar events.

## Permissions

Calendar and Reminders have separate macOS permissions and separate **Request
Access** buttons. DockDeck does not trigger either prompt at launch, when the
module is enabled, or when **Include due reminders** is switched on. A prompt
appears only after its matching button is pressed.

Current macOS EventKit APIs require full access to fetch either data set even
for a read-only app. DockDeck never calls EventKit save, edit, completion, or
delete APIs. If access was denied, change it under **System Settings → Privacy &
Security → Calendars** or **Reminders**, then use **Check Again**.

Google and other accounts appear only when they expose their Calendar or
Reminder data to macOS under **System Settings → Internet Accounts**. Signing
into a provider in Safari alone does not connect it to EventKit.

## Selection and privacy

Calendar and Reminder-list selectors are independent. DockDeck retains item
titles, times, all-day state, and source names only in memory. Local preferences
contain the selected source identifiers, the all-day and Reminders switches,
and refresh interval; event and Reminder contents are never persisted, logged,
or sent over the network.

Disabling Schedule stops its timer, removes its EventKit observer, releases the
event store, and clears both in-memory item lists. Hidden Schedule panels keep
the selected polling interval so EventKit changes remain timely; macOS Low Power
Mode doubles that interval.
