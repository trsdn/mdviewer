# Contributing to MDViewer

Thanks for helping improve MDViewer. We appreciate well-scoped, maintainable changes and clear issue reports.

## Working with the repository

### Prerequisites

- macOS with Xcode 16 or newer
- `xcodegen` installed locally with `brew install xcodegen`
- The project’s vendored web assets and release tooling are kept under `vendor/` and `scripts/`

### Local setup

```bash
brew install xcodegen
xcodegen generate
```

For a clean verification pass before opening a pull request:

```bash
./scripts/vendor_web_assets.sh --check
xcodebuild -project MDViewer.xcodeproj -scheme "MDViewer-Lite" -configuration Debug -derivedDataPath "build/Lite" test CODE_SIGNING_ALLOWED=NO
xcodebuild -project MDViewer.xcodeproj -scheme "MDViewer-Full" -configuration Debug -derivedDataPath "build/Full" test CODE_SIGNING_ALLOWED=NO
ALLOW_UNSIGNED=1 ./scripts/build_release.sh
```

The release workflow and README are the canonical place for supported build and validation commands.

## Branch and pull-request workflow

- Start from the latest `main` branch.
- Create a short-lived feature branch for your work.
- Keep changes focused and avoid unrelated refactors.
- Open a pull request against `main` with a clear summary and linked issue when applicable.
- PRs should remain small enough to review quickly and should include validation evidence.

## Code and design expectations

- Prefer surgical, readable changes that match the surrounding Swift style.
- Preserve the app's read-only, sandboxed behavior and security-sensitive patterns.
- Update the README, release notes, or changelog when user-visible behavior changes.
- Do not commit generated output, local state, or secrets.

## Testing and validation

Every change should be checked with the most relevant local validation available. At minimum, validate:

- vendored asset integrity and project generation
- the affected unit or UI test coverage
- the relevant release or build path when product behavior changes

If you change release behavior, update the relevant documentation and ensure the release workflow still succeeds.

## Documentation and changelog expectations

- Update `README.md` when installation, behavior, security, or support instructions change.
- Add entries to `CHANGELOG.md` for user-facing or operational changes when appropriate.
- Keep release notes accurate and specific about user impact, migration concerns, or rollback notes.

## Review and maintenance expectations

Pull requests are reviewed by the maintainer(s) and must pass the repository's required CI checks before merge. Discussions should stay focused on the change, risks, and correctness. Maintainers may ask for follow-up work when a patch is incomplete or not aligned with the project goals.

## Questions and support

If you need help before starting work, open a discussion or issue using the project’s issue intake forms. For security-sensitive matters, do not use public issues; follow the instructions in `SECURITY.md`.
