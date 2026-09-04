# GitHub Inbox

GitHub Inbox summarizes unread account notifications through the locally
installed and authenticated GitHub CLI. It is separate from Project Pulse:
Project Pulse describes repository or contribution activity, while GitHub Inbox
answers what currently needs attention.

## Setup

1. Install [GitHub CLI](https://cli.github.com/) and run `gh auth login`.
2. Enable **GitHub Inbox** under **Settings → Decks**.
3. Open **Settings → GitHub Inbox** and choose a 5-, 10-, or 15-minute interval.
4. Optionally choose one repository for recent failed Actions runs.

Use **Settings → Diagnostics** to check that the CLI is installed and signed in.
DockDeck never starts a GitHub login flow.

## Panel values

| Label | Value |
| --- | --- |
| `NEW` | All unread notifications returned for the signed-in account |
| `@` | Direct and team mentions |
| `REV` | Pull-request review requests |
| `CI` | CI-activity notifications when no Actions repository is selected |
| `FAIL` | Failed, timed-out, startup-failed, or action-required runs during the previous seven days for the selected repository |

The optional Actions query examines at most 100 failed runs, so `FAIL` can be a
lower bound for unusually active repositories. The compact panel also shows one
bounded message preview, prioritizing review requests, mentions, assignments,
and CI activity before other notifications. Double-click the panel to see up to
five prioritized messages with their repository names. Supported notification
rows open their validated pull request, issue, commit, discussion, Actions run,
or release page on GitHub. Other rows fall back to the repository page. Hover
the panel or use VoiceOver for the expanded description.

## Data and polling

DockDeck first invokes `gh api --include` for GitHub's notifications endpoint.
It keeps the returned `ETag` or `Last-Modified` validator in memory and uses it
for the next request. A `304 Not Modified` response reuses the in-memory result;
responses with more than 50 notifications are fetched with a bounded paginated
request. DockDeck also respects GitHub's `X-Poll-Interval` response header when
it is longer than the selected interval. When a repository is selected, it
invokes `gh run list` and filters results to the rolling seven-day window. See
GitHub's
[Notifications REST API](https://docs.github.com/en/rest/activity/notifications)
and the [`gh api`](https://cli.github.com/manual/gh_api) and
[`gh run list`](https://cli.github.com/manual/gh_run_list) manuals.

GitHub CLI owns authentication and token storage. DockDeck stores only the
optional validated `owner/repository` name. Notification payloads, aggregate
counts, Actions results, and command output stay in memory and are discarded.
Titles, repository names, reasons, and timestamps are bounded before they enter
the panel model.

Project Pulse and GitHub Inbox share a serialized `gh` request broker. Brief
successful-result caching coalesces duplicate repository, activity, workflow,
and inbox requests when both modules refresh together; it does not add a second
credential store or background service. Conditional-request validators and the
last parsed notification page exist only for the lifetime of the app process.

Disabling the module stops its timer and subprocesses. Hidden polling is three
times slower than the selected interval; macOS Low Power Mode adds another
two-times multiplier. `⌘R` requests an immediate refresh when the module is
enabled. A failed refresh retains the last successful snapshot and exposes the
error in panel help.
