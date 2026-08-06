# MDViewer

A minimal macOS Markdown viewer. No editor, no bloat — just clean rendering with curated reading themes.

![macOS](https://img.shields.io/badge/macOS-13.0+-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Size](https://img.shields.io/badge/App_Size-~1.1_MB-2ea44f)
![Memory](https://img.shields.io/badge/Memory-<100MB-2ea44f)

## Features

- **Secure GitHub-flavored rendering** via [marked.js](https://marked.js.org) and [DOMPurify](https://github.com/cure53/DOMPurify)
- **Private local images** — optional read-only folder access for relative PNG, JPEG, GIF, and WebP images
- **Curated themes** — GitHub, Solarized, Sepia, Dracula, Monokai, and Nord palettes
- **Automatic appearance** — System, Light, or Dark mode with separate preferred light and dark themes
- **Window-scoped zoom** — Cmd+/Cmd- affects only the active window and becomes the default for new windows
- **Reload** — Cmd+R to refresh after external edits
- **Sibling navigation** — move through Markdown files in the same folder by filename
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

Choose preferred palettes in **MDViewer > Settings**. System mode follows the current macOS appearance and switches between those preferences. Sepia is a light palette selected in Settings; the existing mode shortcuts remain unchanged.

Choose **View > Refresh Sibling Navigation…** to discover files added to the folder. If macOS restricts folder enumeration, the same command requests read-only folder access. Opening a document never prompts solely for navigation, and Reload also refreshes sibling availability.

| Action | Shortcut |
|--------|----------|
| Reload | `Cmd R` |
| Previous Markdown File | `Cmd Option Left Arrow` |
| Next Markdown File | `Cmd Option Right Arrow` |
| Zoom In | `Cmd +` |
| Zoom Out | `Cmd -` |
| Actual Size | `Cmd 0` |
| System Appearance | `Cmd Shift 0` |
| Light Mode | `Cmd Shift 1` |
| Dark Mode | `Cmd Shift 2` |

## Reading Themes

| Light themes | Dark themes |
|--------------|-------------|
| GitHub Light | GitHub Dark |
| Solarized Light | Solarized Dark |
| Sepia | Dracula |
|  | Monokai |
|  | Nord |

Themes use built-in trusted palettes and apply without reloading the document or changing its scroll position or zoom.

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
