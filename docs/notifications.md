# Local notifications

DockDeck can send native macOS alerts for selected state changes:

- A live Codex or Claude quota window crosses 10%, 20%, or 30% remaining
- A configured service becomes unavailable or recovers
- A discharging internal battery crosses 10%, 20%, or 30% remaining
- macOS thermal pressure enters the serious or critical state
- A Focus Timer focus or break phase completes

Notifications are off by default. macOS permission is requested only when you
turn on **Allow local notifications** under **Settings → Notifications**; the
app never prompts at launch. If access is denied, enable DockDeck under **System
Settings → Notifications**.

## Transition behavior

Threshold and health alerts are transition-based rather than repeated on every
poll. A usage window can alert again after its provider supplies a new reset
window. A service recovery can alert only after the same endpoint was observed
down, and a battery alert can occur again after charge rises above the selected
threshold and later crosses it while discharging. A thermal alert can occur
again only after pressure first returns below serious.

DockDeck evaluates rules from the module values already in memory. It does not
create a second network request or upload notification content. Pending events
observed while macOS authorization is still being resolved are de-duplicated;
they are discarded if permission is denied or notifications are switched off.

Notification previews can contain provider names, quota values and reset times,
configured service names, or battery percentage. Control preview visibility in
macOS notification settings if that information should not appear on the lock
screen.
