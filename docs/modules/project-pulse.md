# Project Pulse

Project Pulse monitors a local Git folder, one GitHub repository that does not
need a local clone, or the signed-in user's recent GitHub contribution activity.
Repository views can optionally show the latest GitHub Actions result through
the locally installed GitHub CLI.

## Setup

1. Enable **Project Pulse** under **Settings → Decks**.
2. Open **Settings → Project Pulse** and select **Local** or **GitHub**.
3. For **Local**, choose a Git repository folder.
4. For **GitHub**, install [GitHub CLI](https://cli.github.com/), run
   `gh auth login`, then select **Repository** or **My Activity**. Repository
   mode lists the 100 most recently pushed repositories accessible to the
   account.
5. Repository views can optionally enable **Latest Actions run** and use a
   30-second, 60-second, or 5-minute refresh interval. My Activity uses five
   minutes because contribution totals do not require near-real-time polling.

Switching sources preserves both selections, so returning to the previous source
does not require choosing it again.

## Panel values

The local source shows the current branch, staged, modified, untracked, and
conflicted entry counts. It also shows ahead/behind counts when the branch has
upstream information. File names are never displayed or retained.

The GitHub source uses a compact two-row layout:

- `7D` is the number of commits added to the default branch during the previous
  seven days.
- `PR` and `ISS` are open pull request and open issue counts.
- The repository name, default branch, and optional latest Actions state remain
  visible in the panel.
- Hovering the panel reveals the full `owner/repository`, visibility, stars,
  forks, last push, short head commit, and unabridged counts. VoiceOver receives
  the same details.

**My Activity** summarizes the previous seven days across repositories:

- `7D` is GitHub's total contribution count for the signed-in viewer.
- `COM`, `PR`, `REV`, and `ISS` are commit, opened pull request, pull request
  review, and opened issue contributions.
- A lock beside `7D` shows GitHub's aggregate restricted contribution count.
  Repository names and contribution types for those restricted values are not
  requested or inferred.
- Hovering reveals the full counts and number of repositories with contributed
  commits. VoiceOver receives the same summary.

These values follow GitHub profile contribution rules. For example, commit
credit normally applies to a repository's default or `gh-pages` branch and an
email associated with the account. Private and internal contribution inclusion
depends on the authenticated token scope and GitHub contribution-visibility
settings. See GitHub's
[profile contributions reference](https://docs.github.com/en/account-and-profile/reference/profile-contributions-reference).

## Commands and boundaries

Local status uses the system `git` executable with:

```text
git -C <selected-folder> status --porcelain=v2 --branch -z --untracked-files=normal
```

For the GitHub Repository view, DockDeck asks the authenticated CLI for accessible
repositories through GitHub's `user/repos` REST endpoint, then reads the selected
repository with one GraphQL query. My Activity uses one GraphQL
`viewer.contributionsCollection` query for a rolling seven-day interval. See
the official
[REST repository API](https://docs.github.com/en/rest/repos/repos),
[GraphQL repository fields](https://docs.github.com/en/graphql/reference/repos),
[commit history fields](https://docs.github.com/en/graphql/reference/commits),
and [ContributionsCollection fields](https://docs.github.com/en/graphql/reference/users#contributionscollection).

When Actions is enabled, DockDeck runs this non-interactively. The remote source
adds `--repo owner/repository`:

```text
gh run list [--repo owner/repository] --limit 1 --json status,conclusion,name,displayTitle
```

Commands have an eight-second timeout and a 1 MiB output cap. GitHub CLI prompts
and pagers are disabled. DockDeck never starts an authentication flow; use
`gh auth login` or `gh auth status` in Terminal. See the official
[`gh api` manual](https://cli.github.com/manual/gh_api) for how the CLI supplies
authentication to REST and GraphQL requests.

An unavailable CLI or local remote produces a neutral **Actions unavailable**
state without affecting local Git status. A signed-out account, inaccessible
remote repository, or network failure leaves the last remote snapshot visible
with an error state until a later refresh succeeds.

## Privacy and power

DockDeck stores the standardized local path, selected GitHub view, or selected
public/private `owner/repository` name, plus module settings. My Activity counts
and login remain in memory only. DockDeck discards Git file names after counting
them and does not copy, log, or store repository remote URLs, GitHub tokens, or
command output. Authentication and token storage remain owned by GitHub CLI.

Disabling the module stops its timer and subprocesses. When Project Pulse is
enabled but another module is selected, its polling interval is multiplied by
five; macOS Low Power Mode applies an additional two-times multiplier. This
makes My Activity refresh every 25 minutes in the background, 10 minutes while
visible in Low Power Mode, or 50 minutes when both conditions apply. `⌘R`
always requests an immediate refresh.

Save up to three configured projects under **Saved Projects**. Choose one there
or from the detail window to restore its source, repository and polling options.
Only the selected project is refreshed. Switching discards late responses from
the previous selection and reuses the existing GitHub request broker/cache.
Saved local paths and GitHub repository names remain in local preferences;
removing a favorite does not remove a repository or alter the current selection.
