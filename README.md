# MDViewer 2.2

A native, read-only macOS Markdown viewer with two editions built from one
shared Swift and renderer codebase.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

## Editions

| Edition | Recommended for | Release app | Compressed DMG |
| --- | --- | ---: | ---: |
| **Full** (recommended) | Broad highlighting, YAML metadata, and complete offline Mermaid support | 7.0 MB | 2.3 MB |
| **Lite** | Minimum footprint with compact Prism highlighting | 2.7 MB | 1.1 MB |

Sizes were measured from unsigned universal Release builds produced by the
release scripts. Both editions use bundle identifier `com.torstenmahr.MDViewer`, so
installing one replaces the other rather than registering competing Markdown
handlers. Settings shows the installed edition, version, and build.

## Help and support

The app includes **MDViewer Help** (`Cmd ?`) with navigation, reading, and
edition-specific guidance. **About MDViewer** shows the installed edition,
version, copyright, the [project website](https://trsdn.github.io/mdviewer/),
the [GitHub repository](https://github.com/trsdn/mdviewer), and a direct
[Report an Issue](https://github.com/trsdn/mdviewer/issues/new) link.

## Shared features

- GitHub-flavored Markdown through pinned marked.js and DOMPurify
- Footnotes, GitHub alerts, accessible read-only task lists, and heading anchors
- Native window-scoped Find, current-folder Quick Open, and outline popover
- Optional, collapsed-by-default read-only folder navigator (`Cmd Shift B`)
- Secure relative links to authorized Markdown files
- Drag and drop from Finder: each Markdown file opens in its own window and a
  dropped folder becomes the Folder Navigator root
- Native debounced folder events for sibling navigation; no polling
- Local PNG, JPEG, GIF, and WebP images through a confined custom resource loader
- Dependency-free image inspection with fit, zoom, pan, and original size
- Code language labels plus Copy, wrap, and line-number controls
- GitHub, Solarized, Sepia, Dracula, Monokai, and Nord reading palettes
- Window-scoped zoom, reload, Recent Files, and printing

Lite includes a 10,060-byte custom Prism build for Swift, JavaScript,
TypeScript, JSON, Bash, Python, Rust, HTML, and CSS.

Full replaces Prism with lazily imported highlight.js and adds:

- Complete official modular Mermaid ESM distribution, loaded only for Mermaid fences
- Strict Mermaid SVG sanitization and lazy svg-pan-zoom controls
- Safe, bounded YAML frontmatter cards loaded only for frontmatter documents
- Broad highlight.js language coverage loaded only when code blocks exist

## Install and build

Download one of the DMGs from
[Releases](https://github.com/trsdn/mdviewer/releases):

- `MDViewer-Full-macos.dmg` — recommended
- `MDViewer-Lite-macos.dmg` — minimum footprint

Each DMG has a matching `.sha256` file. To build both editions locally:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme MDViewer-Lite -configuration Release build
xcodebuild -scheme MDViewer-Full -configuration Release build
```

Release engineering:

```bash
./scripts/vendor_web_assets.sh --check
ALLOW_UNSIGNED=1 ./scripts/build_release.sh  # local/CI verification
./scripts/release_macos.sh                   # signed + notarized Lite and Full DMGs
```

The release workflow produces clearly named DMGs and SHA-256 files, notarizes
and staples both, runs Gatekeeper checks, and attaches the verified artifacts
to the matching GitHub release.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Find / next / previous | `Cmd F` / `Cmd G` / `Cmd Shift G` |
| Quick Open current folder | `Cmd K` |
| Document outline | `Cmd Shift O` |
| Folder Navigator | `Cmd Shift B` |
| Reload | `Cmd R` |
| Previous / next Markdown file | `Cmd Option Left` / `Cmd Option Right` |
| Zoom in / out / actual size | `Cmd +` / `Cmd -` / `Cmd 0` |
| System / light / dark appearance | `Cmd Shift 0` / `Cmd Shift 1` / `Cmd Shift 2` |

## Folder Navigator

Choose **View > Folder Navigator** or use its toolbar button to show the
sidebar. **File > Open Folder…** authorizes the current document’s folder or an
ancestor with read-only access. The current file is revealed automatically,
and selecting another Markdown file uses MDViewer’s normal document-open path.

The navigator is local-only and intentionally has no file-management actions.
It loads only a directory that is expanded, ignores hidden items, packages,
symlinks, and unsupported files, and refreshes only directories already
loaded. To stay responsive on large or hostile trees it is limited to 12
levels, 500 direct children per folder, and 5,000 loaded items.

## Security

MDViewer is an App Sandbox application with read-only user-selected file access
and app-scoped security bookmarks. The render page cannot reach the network:
its Content Security Policy sets `connect-src`, `worker-src`, `frame-src`,
`object-src`, and `form-action` to `none`. The sandboxed WebKit process itself
still requires the network-client entitlement to launch at all (a WebKit/macOS
requirement independent of whether any request is ever made); it is not usable
by rendered content.

- CSP blocks networking, workers, frames, objects, forms, media, and remote code.
- Markdown HTML is sanitized before any enhancement runs.
- External navigation is limited to `http`, `https`, and `mailto`.
- Internal links are resolved natively and reject traversal and symlink escapes.
- Local images reject traversal, SVG, mismatched types, oversized files, and
  anything outside the authorized folder.
- Full modules are served only from a generated bundle allowlist.
- Mermaid uses strict mode, disables HTML labels, and sanitizes generated SVG
  with a separate SVG policy.
- YAML rejects custom tags, aliases, prototype keys, deep/large structures, and
  executable schemas.
- Lite physically contains no Full modules; Full contains no Prism engine.

## Dependencies

| Library | Version | License | Edition | Purpose |
| --- | --- | --- | --- | --- |
| marked | 18.0.9 | MIT | Both | Markdown parser |
| DOMPurify | 3.4.12 | Apache-2.0 OR MPL-2.0 | Both | HTML/SVG sanitization |
| marked-footnote | 1.4.0 | MIT | Both | Footnotes |
| Prism core | 1.30.0 | MIT | Lite | Compact selected-language highlighting |
| highlight.js | 11.11.1 | BSD-3-Clause | Full | Broad lazy highlighting |
| js-yaml | 5.2.3 | MIT | Full | Restricted frontmatter parsing |
| Mermaid | 11.16.0 | MIT | Full | Complete offline diagrams |
| svg-pan-zoom | 3.6.2 | BSD-2-Clause | Full | Diagram pan and zoom |

Exact asset checksums, provenance, bytes, and edition membership are recorded in
[`third-party/manifest.json`](third-party/manifest.json) and
[`docs/THIRD-PARTY-NOTICES.md`](docs/THIRD-PARTY-NOTICES.md).

As of 2026-08-09, `npm audit` reports two moderate upstream advisories without
a published fixed release. MDViewer never enables DOMPurify `IN_PLACE`; Mermaid
uses trusted configuration, bounded/concurrent/timed rendering, and separately
sanitized SVG. There are no high or critical audit findings.

## Need editing too?

[MDViewer+](https://github.com/trsdn/mdviewerplus) adds a native editor and
split preview while retaining the lightweight macOS approach.

## License

[MIT](LICENSE)
