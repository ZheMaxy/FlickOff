# Changelog

User-visible changes. The build number is what the menu shows after the version.

## 1.2.0-beta.1 (build 5), 2026-11-04

### Added

- **When idle** setting: let macOS dim the panel, keep it lit, or turn it off after
  1, 5 or 15 minutes without input. Turning off skips the dim range that can
  flicker and spares the OLED. New installations default to 5 minutes; existing
  installations keep their behaviour until you choose.
- Opening FlickOff while it runs shows its controls in a window, which helps when
  the menu bar icon is hidden.
- An update found in the background shows on the menu bar icon and in the menu,
  instead of an alert that could open unnoticed behind other windows.
- **Include beta versions** setting, for when stable releases exist.
- Installing with Homebrew from this repository: no first-launch steps and no
  administrator password.
- Release files are built in CI, which records where they came from.
- The menu and reports show the build number. Reports also name the mode, level
  and idle setting.

### Changed

- Far less energy while idle: about 0.1% CPU instead of about 2.2%, measured in
  the same conditions on an M1 MacBook Pro.
- The brightness slider moves in whole percents.

### Fixed

- A failed check right after login lasted until the next launch and blamed the
  macOS version. FlickOff now keeps trying for about a minute, and again after
  waking or unlocking.
- A moment without an answer from the brightness service could make quitting
  restore the minimum brightness.
- Quitting during a diagnostics test could leave the panel off or scaled down.
- Off could silently stop working when macOS refused it. The menu now warns.
- During fast user switching FlickOff kept changing the other user's Touch Bar.
- A second running copy fought the first over the panel. It now quits.
- A refused automatic login item registration wasn't tried again.
- The diagnostics window opened behind the menu, kept showing an old snapshot, and
  reported "no visible change" for tests started in Off mode.
- VoiceOver read the menu bar icon as "Brightness Higher".

## 1.1.0-beta.2 (build 4), 2026-11-03

- Native installer with an inline license and Agree and Install action.
- Automatic launch after installation, under the logged-in user's account.
- Launch at login and automatic update checks enabled by default for new
  installations. User opt-outs remain respected.
- Safe upgrade and reinstall, downgrade protection, and shutting down matching app
  copies before replacing them.
- English documentation, clearer installation instructions and a Touch Bar FAQ.

## 1.1.0-beta.1 (build 3), 2026-11-03

- Manual brightness, Auto and display Off from the menu bar.
- Optional idle dimming prevention, remembered settings and launch at login.
- Brightness restoration on normal quit and SIGTERM, with sleep, lock and lid guards.
- In-app updates through Sparkle, with signed feeds and archives.
