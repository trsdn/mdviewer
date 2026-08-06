# MDViewer

A minimal macOS Markdown viewer. No editor, no bloat — just clean rendering with automatic Dark Mode support.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Size](https://img.shields.io/badge/App_Size-~1.1_MB-2ea44f)
![Memory](https://img.shields.io/badge/Memory-<100MB-2ea44f)

## Features

- **Secure GitHub-flavored rendering** via [marked.js](https://marked.js.org) and [DOMPurify](https://github.com/cure53/DOMPurify)
- **Private local images** — optional read-only folder access for relative PNG, JPEG, GIF, and WebP images
- **Dark Mode** — automatic (system), light, or dark via View > Appearance
- **Window-scoped zoom** — Cmd+/Cmd- affects only the active window and becomes the default for new windows
- **Reload** — Cmd+R to refresh after external edits
- **Native file handling** — Open, Recent Files, drag & drop
- **About 1.1 MB total** — no Electron, package manager, or external runtime

## Performance

| Metric | Value |
|--------|-------|
| App size | ~1.1 MB |
| Download (DMG) | ~610 KB |
| Cold start | < 50 ms |
| Memory | < 100 MB |

## Install

Download the latest signed and notarized `.dmg` from [Releases](https://github.com/trsdn/mdviewer/releases) or build from source:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme MDViewer -configuration Release build
```

## Need editing too?

[MDViewer+](https://github.com/trsdn/mdviewerplus) adds a native Markdown editor, live split preview, scroll sync, syntax highlighting, formatting shortcuts, and printing while keeping the same lightweight macOS approach. See the [MDViewer+ website](https://trsdn.github.io/mdviewerplus/).

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Reload | `Cmd R` |
| Zoom In | `Cmd +` |
| Zoom Out | `Cmd -` |
| Actual Size | `Cmd 0` |
| System Appearance | `Cmd Shift 0` |
| Light Mode | `Cmd Shift 1` |
| Dark Mode | `Cmd Shift 2` |

## Dependencies

| Library | Version | License | Purpose |
|---------|---------|---------|---------|
| [marked](https://github.com/markedjs/marked) | 18.0.9 | MIT | Markdown → HTML parsing |
| [DOMPurify](https://github.com/cure53/DOMPurify) | 3.4.12 | Apache-2.0 OR MPL-2.0 | HTML sanitization |

No Swift package dependencies or third-party native frameworks. Official browser distributions and their license notices are bundled with the app; no package manager is used at runtime.

## Security and local images

MDViewer is a read-only App Sandbox application. Markdown HTML is sanitized, renderer networking is blocked by Content Security Policy, remote images are not loaded, and only `http`, `https`, and `mailto` links open externally. Same-page fragment links remain in the preview; relative file links are intentionally not opened.

When a document contains a supported relative raster image, MDViewer asks for read-only access to the document’s folder. The app stores an app-scoped security bookmark so access can be restored. Its custom WebKit resource loader rejects traversal, symlink escapes, SVG, unsupported or mismatched file types, and anything outside the authorized folder.

## License

[MIT](LICENSE)
