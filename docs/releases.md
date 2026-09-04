# Releases and versioning

DockDeck is a pre-1.0 project. Public binaries are technical previews until a
Developer ID-signed and notarized build is available. The root `VERSION` file is
the single source of truth for the app's three-part version.

## Version policy

DockDeck uses patch-only preview increments for now. Feature work and release
versioning are separate:

| Change | Version action |
| --- | --- |
| Documentation, tests, or internal refactoring only | No version change |
| Feature or fix PR | No version change; merge it independently after review |
| Release integration PR | Increment the patch version exactly once (`0.1.0` → `0.1.1`) for all selected changes already on `main` |
| Another build of the same base version | Keep `VERSION`; increment only the preview sequence |

Keep one logical change in each feature or fix PR. If combined testing is
needed, use a temporary integration branch without replacing those focused
reviews with one oversized PR. When the selected work is ready to distribute,
create a release integration branch from the latest `main`; update `VERSION`
and release-facing documentation there, then run the release and package
checks. Do not reserve versions on unfinished feature branches.

Preview sequence numbers belong to Git tags, not `VERSION`. For example,
`VERSION` remains `0.1.1` for `v0.1.1-preview.1` and
`v0.1.1-preview.2`. Increment the preview number for another build of the same
base version. Do not move or reuse a published tag. Minor and major increments
remain reserved until this policy is explicitly revised.

Merging a PR does not automatically publish a binary. Create a preview tag only
when the accumulated `main` state is ready for a tested preview release.

`1.0.0` is reserved for a stable feature and settings contract plus a
Developer ID-signed, notarized distribution path.

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
