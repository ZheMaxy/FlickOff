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

## Build, sign and publish

Hosted CI builds the files and records where they came from, this Mac runs what needs
a Touch Bar and signs them, and publishing the feed is a separate last step. No
signing key reaches CI. See [update publishing](UPDATES.md) for the key itself.

1. Add the changes to `CHANGELOG.md` and raise `CFBundleVersion` and, if it changes,
   `CFBundleShortVersionString` in `Resources/Info.plist`. Remove notes in README and
   INSTALL about what the current release lacks. Push to `main`.

2. Build the release files in CI:

   ```sh
   gh workflow run release.yml --ref main
   gh run list --workflow release.yml --limit 1   # note the run ID, wait for it to pass
   ```

3. Run what CI can't, against the app CI built:

   ```sh
   gh run download <run ID> --name release-files --dir build/ci
   ditto -x -k build/ci/FlickOff-*.zip build/ci
   python3 scripts/preflight.py --app build/ci/FlickOff.app
   ```

   Add `--root-owned` when the updater or the installer changed. It asks for an
   administrator several times. `make_release.py` refuses a commit without a pass.

4. Write what changed for users in a plain-text file, which the update alert shows,
   and the release page in Markdown. Then check, sign and upload:

   ```sh
   python3 scripts/publish.py upload --run <run ID> --tag v1.2.0-beta.1 \
       --title "FlickOff 1.2.0 — Public Beta 1" \
       --notes notes.txt --body release.md --output build/release-1.2.0-beta.1
   ```

   This verifies the attestation, refuses a tag that doesn't match the app version or
   a build no newer than the one in `appcast.xml`, signs the files CI built, uploads
   them as a prerelease and checks what can now be downloaded. Add `--stable` for a
   stable release. Nobody is offered the release yet.

5. Try the update on a real installation with the feed that will be published:

   ```sh
   defaults write io.github.ZheMaxy.FlickOff SUFeedURL \
       https://github.com/ZheMaxy/FlickOff/releases/download/v1.2.0-beta.1/appcast.xml
   ```

   Choose **Check for Updates…** in the installed app and install it. Check the version,
   your settings and the login item, then remove the override:

   ```sh
   defaults delete io.github.ZheMaxy.FlickOff SUFeedURL
   ```

6. Offer it to users:

   ```sh
   python3 scripts/publish.py feed --output build/release-1.2.0-beta.1
   ```

   This commits the feed unchanged, with the updated download links and Homebrew cask,
   pushes `main` and waits until the feed URL serves it. The **Update feed** workflow
   then checks it again with only the public key, and repeats that daily.

Do not add loose files alongside the app inside the updater ZIP. It preserves
framework symlinks and includes license notices inside the app's Resources.

### Who gets a release

A release without `--channel` goes to everyone. `--channel beta` on the upload step
offers it only to build 5 and later with **Include beta versions** on, and the feed
keeps the newest item of the other channel so nobody is left behind. Until a stable
release exists there's no reason to split them.

`--phased-rollout-hours 24` on the upload step offers it to one of seven groups of
users per interval, which leaves time to stop a bad release: publish a new feed
without it before the groups run out.

Release notes should give the exact tested model/OS pairs, private API
limitations, signing status and limits of flicker mitigation. Use a prerelease
while the documented manual or compatibility checks remain incomplete.
Commercial rights are granted separately: do not label the project MIT or
unrestricted open source.
