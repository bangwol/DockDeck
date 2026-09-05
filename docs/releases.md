# Releases and versioning

DockDeck is a pre-1.0 project. Public binaries are technical previews until a
Developer ID-signed and notarized build is available. The root `VERSION` file is
the single source of truth for the app's three-part version.

## 0.1.3 integration

This patch combines the completed stability review and module/workflow updates.
Network is now part of [System Stats](modules/system-stats.md), with automatic
migration of existing decks and selectable GPU utilization. Existing modules
add detailed readings, hourly weather, container metrics, favorites, filters,
and clearer refresh/error states.

The release adds [Local Ports](modules/local-ports.md), saved deck profiles and
validated backups, explicit Quick Actions, three Custom Tiles, searchable
modules/settings, readable compact layouts, core Korean/English controls, and
[native Shortcuts actions](integrations/shortcuts.md). It also fixes packaged
resource lookup, input/output bounds, ambiguous profile names, and cancellation
and bounded app-exit cleanup of owned background commands.

[Launch at Login](getting-started.md#install-and-start-at-login) now uses the
native macOS registration and preserves the existing choice across updates.
The legacy LaunchAgent is backed up and removed after migration. New installs
leave login launch off; pending macOS approval remains visible to the user.

Apple silicon remains the primary target. The universal app retains native
Intel compatibility and includes localized resources and App Intents metadata.
Source installation rejects translated terminals to prevent an Intel-only
installation on Apple silicon. GPU readings remain driver-dependent.
Preview signing and notarization limitations below continue to apply; this
version integration does not itself create a tag or publish a GitHub Release.

## Version policy

DockDeck uses patch-only preview increments for now. Feature work and release
versioning are separate:

| Change | Version action |
| --- | --- |
| Documentation, tests, or internal refactoring only | No version change |
| Goal PR (features, fixes, UI, tests, and docs for one goal) | No version change; review and merge the accumulated goal together |
| Release integration PR | Increment the patch version exactly once (`0.1.0` → `0.1.1`) for all selected changes already on `main` |
| Another build of the same base version | Keep `VERSION`; increment only the preview sequence |

Use one branch and one PR per user-visible goal. Related features, module
updates, UI work, and fixes stay on that branch as separately tested local
commits. Do not create a branch or PR for every module or commit. Start a new
goal from synchronized `main`; use `codex/<goal>` for Codex-created branches.
Split only for a requested or independently deliverable scope.

Before pushing, review the accumulated diff and prepare a single Conventional
Commit PR title and description covering the final goal and validation. Once a
push is authorized, push the tested commits together and update that same PR
for review fixes. Do not push after every local commit. Feature work reaches
`main` through the goal PR, preferably by squash merge.

When the selected work is ready to distribute, create a release integration
branch from the latest `main`; update `VERSION` and release-facing documentation
there, then run the release and package checks. This is one release checkpoint,
not a reason to split the goal into feature-by-feature PRs. Do not reserve
versions on unfinished feature branches.

Preview sequence numbers belong to Git tags, not `VERSION`. For example,
`VERSION` remains `0.1.1` for `v0.1.1-preview.1` and
`v0.1.1-preview.2`. Increment the preview number for another build of the same
base version. Do not move or reuse a published tag. Minor and major increments
remain reserved until this policy is explicitly revised.

Merging a PR does not automatically publish a binary. Create a preview tag only
when the accumulated `main` state is ready for a tested preview release.

`1.0.0` is reserved for a stable feature and settings contract plus a
Developer ID-signed, notarized distribution path.

## Architecture support

Apple silicon is the primary development and runtime validation target. Keep
native Intel compatibility in the 0.1.3 universal preview: both DockDeck and its
bundled Claude bridge contain `arm64` and `x86_64` slices. The package check
rejects a missing slice. Source installation builds for the current Mac and
rejects a translated terminal to avoid installing an Intel-only app on Apple
silicon. Neither bundled executable needs Rosetta on Apple silicon.

Apple's [Rosetta transition notice](https://developer.apple.com/news/?id=w5ngl9k2)
states that macOS 27 is the last release with general Rosetta support and that
macOS 26.4 and later may warn when translated apps run. A universal binary runs
natively on either processor; carrying an Intel slice does not itself require
Rosetta. Forcing that slice to run on Apple silicon can trigger the warning.
Use the native app for normal installation and runtime checks.

Intel support currently shares the same implementation and needs no extra
dependencies. Retain it while the supported toolchain can build both slices;
reassess at a release checkpoint if that requires separate architecture-specific
maintenance. Intel cross-compilation is checked, but does not replace testing
on a physical Intel Mac. Hardware-dependent GPU readings remain optional on
both architectures. User-installed CLIs are separate integrations; choose their
native versions on Apple silicon.

## Preview artifacts

A tagged preview publishes:

- GitHub-generated source ZIP and TAR archives.
- `DockDeck-<version>-macos-universal-unsigned.zip`, containing an ad-hoc signed
  universal app for Apple silicon and Intel Macs.
- A matching `.sha256` checksum.
- GitHub build-provenance attestation for the app ZIP.

The app ZIP is not notarized. macOS may require **System Settings → Privacy &
Security → Open Anyway**, and an update may require Accessibility approval
again. Installing from source with `./scripts/install.sh` remains the preferred
preview path.

A DMG is intentionally deferred. It would improve presentation but would not
remove Gatekeeper warnings from an ad-hoc signed app. Add DMG packaging only
after Developer ID signing and notarization are available.

## Publishing a preview

1. Confirm `main` is clean and synchronized with `origin/main`.
2. Confirm `VERSION` matches the base version in the planned tag.
3. Run the release test and package checks:

   ```bash
   swift test -c release -Xswiftc -warnings-as-errors
   ./scripts/package.sh
   ```

4. Choose the next unused preview sequence, then create and push an annotated
   tag:

   ```bash
   version="$(tr -d '[:space:]' < VERSION)"
   preview=1
   tag="v${version}-preview.${preview}"
   git tag -a "$tag" -m "DockDeck ${version} Preview ${preview}"
   git push origin "$tag"
   ```

5. Wait for the Preview Release workflow. Confirm that the GitHub Release is
   marked as a prerelease and contains the ZIP and checksum.
6. Download the published assets and verify them:

   ```bash
   version="$(tr -d '[:space:]' < VERSION)"
   artifact="DockDeck-${version}-macos-universal-unsigned.zip"
   shasum -a 256 -c "${artifact}.sha256"
   gh attestation verify "$artifact" -R bangwol/DockDeck
   ```

If a published preview is defective, keep its tag immutable and publish the
fix with the next preview sequence or patch version.

## Future stable distribution

A stable public binary requires an Apple Developer Program membership,
`Developer ID Application` signing with hardened runtime and timestamping,
Apple notarization, ticket stapling, and Gatekeeper verification. Add that path
alongside the existing preview workflow rather than weakening preview labels or
publishing an unnotarized artifact as stable.
