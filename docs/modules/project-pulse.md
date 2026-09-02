# Project Pulse

Project Pulse shows one local Git repository's branch, working-tree counts, and
ahead/behind state. Optionally, it adds the latest GitHub Actions run reported
by the locally installed GitHub CLI.

## Setup

1. Enable **Project Pulse** under **Settings → Decks**.
2. Open **Settings → Project Pulse** and choose a repository folder.
3. Optionally enable **GitHub Actions**. Install and sign in to
   [GitHub CLI](https://cli.github.com/) first.
4. Select a 30-second, 60-second, or 5-minute refresh interval.

The panel counts staged, modified, untracked, and conflicted entries without
displaying file names. It also shows local ahead/behind counts when the selected
branch has upstream information.

## Commands and boundaries

Local status uses the system `git` executable with:

```text
git -C <selected-folder> status --porcelain=v2 --branch -z --untracked-files=normal
```

When GitHub Actions is enabled, DockDeck runs this non-interactively in the
selected repository:

```text
gh run list --limit 1 --json status,conclusion,name,displayTitle
```

Commands have an eight-second timeout and a 1 MiB output cap. GitHub CLI prompts
and pagers are disabled. An unavailable CLI, signed-out account, repository
without a GitHub remote, or network failure produces a neutral **Actions
unavailable** state without affecting local Git status.

## Privacy and power

DockDeck stores only the standardized absolute repository path and module
settings. It discards Git file names after counting them and does not read,
copy, log, or store repository remote URLs, GitHub tokens, or command output.
Authentication remains owned by GitHub CLI.

Disabling the module stops its timer and subprocesses. When Project Pulse is
enabled but another module is selected, its polling interval is multiplied by
five; macOS Low Power Mode applies an additional two-times multiplier.
