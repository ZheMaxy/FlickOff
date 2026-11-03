# Contributing

FlickOff is a macOS menu bar utility for Apple silicon MacBook Pros
with a Touch Bar. The build target is macOS 13+; private API compatibility is
checked at runtime.

## Repository conventions

- Source and documentation only: no credentials, personal reports or build
  artifacts. Distribute binaries through Releases.
- Update README and relevant documentation when changing behaviour or support,
  and note user-visible changes in CHANGELOG.md.
- Commit verified changes with a message explaining their purpose. Push only
  when the owner requests or authorizes it for the task.
- Enable the repository hooks with `git config core.hooksPath .githooks`.
  Keep hooks enabled; bypassing them requires explicit owner permission.
- Do not add assistant attribution, assistant product names, co-author trailers
  or session links to files, commit messages, pull requests or release notes.

## Development

- Swift 6.0+ is required. Run `./build.sh test` for ordinary tests and `./build.sh`
  for an arm64 release bundle, signature verification and read-only smoke checks.
- To try a change in CI, workflows included, before it reaches `main`, push it to a
  `ci-check/` branch.
- Tests that change brightness are opt-in: quit all app copies before running
  `TB_HARDWARE_TESTS=1 ./build.sh test` on supported hardware. Never enable these
  tests in hosted CI. `TB_API_TESTS=1` enables a read-only live selector check.
- Add regression coverage for meaningful controller or diagnostic changes. Keep
  writes out of compatibility reports and command-line diagnostics.
- Keep mutable control logic on the main actor. Validate private API types and
  ranges, and document hardware/OS evidence instead of assuming compatibility.
- Keep diagnostics narrow. Avoid collecting arbitrary registry values or raw
  system status. Review reports before publishing them.
- Public source is licensed under PolyForm Noncommercial 1.0.0; commercial rights
  require a separate paid agreement with the owner. See COMMERCIAL.md.
- For contributions, state that you have the right to submit the work and grant
  ZheMaxy permission to distribute that contribution under the project's current
  noncommercial license and separate commercial licenses. Do not include code
  whose existing license prevents that permission. Unclear rights must be resolved
  before merging a contribution.

## Updating dependencies and releases

Sparkle is pinned exactly, including its SwiftPM checksum and Package.resolved.
Preserve its third-party license notices and vendor code signatures when
embedding the framework. Every helper must support the build architecture.
Changes to the updater must pass the signed-feed/tampered-archive/installation
checks described in docs/UPDATES.md. CI builds and attests release files, and their
signing happens on the owner's Mac through Keychain; private signing keys must never
enter the repository or CI. See docs/RELEASING.md.
