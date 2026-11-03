# Release preparation

Pushes and release publication are separate from local builds. The update feed
users read is `appcast.xml` on `main`: other pushes reach nobody until it changes.

## Validate

1. Run `./build.sh` on a clean checkout with Swift 6.0+. Keep Git hooks enabled.
2. Check `--self-test`, `--setup-info`, and `--diagnose`. Review collected data
   before sharing. Ordinary builds/tests must not change brightness or login items.
3. On a supported Mac, quit other copies and deliberately run
   `TB_API_TESTS=1 ./build.sh test` and `TB_HARDWARE_TESTS=1 ./build.sh test`.
4. Manually check Manual/Auto/Off, slider limits, every **When idle** choice
   including what touching a dark panel does, sleep/wake, closed lid/external
   screen, lock/unlock, quitting and launch at login after a real logout.
   Test low-brightness flicker only if comfortable. Record model/OS results.
5. Check that incompatible systems show a report without enabling hardware probes.
6. Review installation/recovery instructions, README, license and
   commercial contact. Do not claim support for untested model/OS combinations.
   For a locally signed release, put the Open Anyway steps directly beside the
   download instructions in README and release notes, link the complete guide,
   and attach a plain-text first-launch guide to the release. State that users
   do not need an Apple Developer subscription. Update signing statements when
   the actual signing or notarization status changes.
7. Scan the tracked tree and history for credentials, personal diagnostics and
   build products. Hooks are an initial check, not a complete history audit.

## Package and publish

Local builds are arm64, ad-hoc signed and not notarized. The initial public beta
states this limitation in its download instructions and release notes. A stable
downloadable release should use Developer ID signing and notarization, with
credentials kept outside the repository, and complete the manual validation
above. Check current Apple distribution requirements before changing signing.

Remove notes in README and INSTALL about what the current beta lacks once the
release includes it. Add the changes to `CHANGELOG.md`, raise `CFBundleVersion` in `Resources/Info.plist`,
and write what changed for users in a plain-text file. The update alert shows it.
Then build the disk image for direct downloads and the ZIP for in-app updates:

```sh
python3 scripts/make_release.py --tag v1.2.0-beta.1 --notes notes.txt --output build/release-1.2.0-beta.1
```

The script refuses a tag that doesn't match the app version, a build no newer than
the one in `appcast.xml`, and missing notes. The output directory must not already
contain an archive. The DMG with the
native installer app is the primary download; validate its license screen,
administrator authorization and upgrade behaviour before release.
The app-only ZIP
preserves framework symlinks and includes license notices inside the app's
Resources. The script verifies the native architecture and code signature,
signs the archive and appcast with the owner's Keychain key, verifies both
signatures, and writes SHA256SUMS. See [update publishing](UPDATES.md).

Upload the DMG, ZIP and SHA256SUMS as assets of the matching GitHub Release. Publish
the generated appcast.xml unchanged at the repository root once its download
URL works. Do not add loose files alongside the app inside the updater ZIP.
Download the published archive/feed and verify their checksum and signatures.

Before publishing a feed for a change to the updater or the installer, run
`python3 Tests/Integration/update_test.py --root-owned`: the installer leaves the
app owned by root, which the ordinary update checks don't cover.

Release notes should give the exact tested model/OS pairs, private API
limitations, signing status and limits of flicker mitigation. Use a prerelease
while the documented manual or compatibility checks remain incomplete.
Commercial rights are granted separately: do not label the project MIT or
unrestricted open source.
