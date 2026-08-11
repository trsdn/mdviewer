---
goal: Optional Cross-Platform Folder Navigator for MDViewer
version: 1.0
date_created: 2026-08-11
last_updated: 2026-08-11
owner: trsdn
status: 'Planned'
tags: [feature, navigation, macos, windows, lite, full, security]
---

# Introduction

![Status: Planned](https://img.shields.io/badge/status-Planned-blue)

Implement an optional, collapsible, read-only folder navigator for MDViewer,
MDViewer+, and MDViewer+ for Windows. The navigator must remain hidden by
default, load folders lazily, preserve the existing Lite/Full physical
separation, and avoid a database, global index, or new third-party dependency.
The target release is v2.1.0 in all three repositories.

## 1. Requirements & Constraints

- **REQ-001**: Add a folder navigator to MDViewer, MDViewer+, and MDViewer+ for Windows in both Lite and Full editions.
- **REQ-002**: Keep the navigator hidden by default and expose it through `View > Folder Navigator`, a toolbar button, and `Cmd/Ctrl+Shift+B`.
- **REQ-003**: Persist navigator visibility and width per application. Use a default width of 240 points/pixels, a minimum of 180, and a maximum of 420.
- **REQ-004**: Implement lazy one-directory-at-a-time loading. Expanding a directory is the only operation that may enumerate its direct children.
- **REQ-005**: Display directories and Markdown files using `MarkdownFileCatalog.supportedExtensions` as the navigator authority in both macOS applications and the existing `is_markdown_file_name` function as the navigator authority on Windows. The effective set must remain `md`, `markdown`, `mdown`, and `mkd`. The pre-existing duplicate extension set in `MarkdownSiblingNavigator` is outside this feature's refactoring scope. Sort directories before files, then sort names case-insensitively with a POSIX-stable tie-breaker.
- **REQ-006**: Exclude hidden entries, package descendants, symbolic links, non-regular files, and unsupported file types.
- **REQ-007**: Enforce a maximum depth of 12, a maximum of 500 direct children per directory, and a maximum of 5,000 loaded nodes per navigator instance.
- **REQ-008**: Keep v2.1.0 read-only. Do not add create, rename, move, duplicate, delete, drag-and-drop mutation, or filesystem context-menu operations.
- **REQ-009**: Preserve Quick Open, sibling previous/next navigation, document outline, internal Markdown links, and existing shortcuts without changing their semantics.
- **REQ-010**: Opening a file from the navigator must use the existing document-open pipeline. MDViewer+ macOS must keep an edited source window open; MDViewer+ Windows must use the existing discard-confirmation policy.
- **REQ-011**: Use an explicitly authorized navigator root. The root may be the current document folder or any ancestor selected through `Open Folder…`.
- **REQ-012**: If a document opens outside the current root, use its containing folder only when an existing security-scoped bookmark already authorizes that folder or an ancestor. Otherwise show the unavailable-root state and require explicit authorization through `Open Folder…`. Never enumerate a macOS folder without an active lease and never silently broaden access.
- **REQ-013**: Preserve expanded relative directory paths and scroll position while refreshing the same root. Do not persist expanded paths across app launches.
- **REQ-014**: Highlight and reveal the current document when it is contained by the active root. Do not auto-expand more than 12 levels.
- **REQ-015**: Refresh the tree after native filesystem events with a 250-millisecond debounce and reject stale refresh completions by generation identifier.
- **REQ-016**: Show explicit loading, empty-folder, truncation, access-denied, moved-root, and unavailable-root states.
- **REQ-017**: Add release notes, README documentation, GitHub Pages documentation, in-app Help coverage, and About/version updates for v2.1.0.
- **SEC-001**: Canonicalize every root, directory, and file before enumeration or opening, and reject any resolved path outside the canonical root.
- **SEC-002**: Never follow symbolic links during enumeration, refresh, reveal, or file opening.
- **SEC-003**: On Windows, expose only relative node paths to JavaScript and resolve them in Rust against the canonical root before returning children or opening a file.
- **SEC-004**: Keep current Tauri capabilities unchanged; do not grant broad filesystem or shell permissions.
- **SEC-005**: Bound every native-to-web tree response by depth, child count, node count, and serialized payload size of 1 MiB.
- **CON-001**: Do not add third-party UI, tree, indexing, database, or watcher packages.
- **CON-002**: Lite and Full must compile the same navigator source and must not gain opposite-edition renderer assets.
- **CON-003**: Installing Lite or Full must continue to replace the other edition under the existing product identity.
- **CON-004**: MDViewer and MDViewer+ remain macOS 13.0 or later; Windows remains on the existing Tauri/Rust/Node toolchain.
- **GUD-001**: Use immutable node identity composed from the root generation and normalized relative path.
- **GUD-002**: Keep tree enumeration, authorization, watcher logic, and UI state in separate types.
- **GUD-003**: Report errors through each repository's existing alert/dialog mechanism; do not silently clear a failed tree.
- **PAT-001**: Reuse existing folder-access leases, open-document policies, path canonicalization, native watcher generation guards, and menu command patterns.

## 2. Implementation Steps

### Implementation Phase 1

- **GOAL-001**: Define identical behavior and data contracts before platform-specific UI work.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add shared behavior contract assertions to each repository's existing architecture tests: assert `MarkdownFileCatalog.supportedExtensions` in each macOS repository and `is_markdown_file_name` on Windows accept exactly `md`, `markdown`, `mdown`, and `mkd`; assert depth `12`, children `500`, loaded nodes `5000`, debounce `250 ms`, payload `1 MiB`, default width `240`, minimum `180`, maximum `420`, and shortcut `Cmd/Ctrl+Shift+B`. Record compressed v2.0.1 Lite artifact sizes before implementation for the Phase 7 size comparison. Do not create a runtime cross-repository package. | | |
| TASK-002 | Define the macOS value types `FolderNavigatorNodeKind`, `FolderNavigatorNode`, `FolderNavigatorChildren`, `FolderNavigatorLimits`, and `FolderNavigatorError` in new `FolderNavigatorModel.swift` files. Node fields must be `id`, `name`, `relativePath`, `kind`, `depth`, `isExpandable`, and `isTruncated`; do not store security-scoped leases in nodes. | | |
| TASK-003 | Define the Windows serializable Rust types `FolderTreeNodeKind`, `FolderTreeNode`, and `FolderTreeChildren` in `src-tauri/src/folder_tree.rs` with camelCase serde output matching the macOS conceptual contract. | | |

### Implementation Phase 2

- **GOAL-002**: Implement the secure lazy tree service and authorization model for MDViewer macOS.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-004 | Add `MDViewer/Services/FolderNavigatorTreeBuilder.swift`. Implement `children(rootURL:relativeDirectory:depth:limits:fileManager:)` using direct `contentsOfDirectory`, requested resource keys, canonical component-prefix confinement, hidden/package/symlink rejection, Markdown extension filtering, directory-first stable sorting, and truncation metadata. | | |
| TASK-005 | Extend `MDViewer/FolderAccessStore.swift` with `FolderAccessPurpose.folderNavigator`. Reject a selected root whose own resource metadata identifies it as a symbolic link. Permit an explicitly selected canonical root only when it equals or is a path-component-wise ancestor of the current document; never use string-prefix comparison. Persist the security-scoped bookmark using the existing bookmark store without replacing bookmarks used by other purposes. Add `restoredNavigatorAccess(forDocumentContainedBy:)`, which resolves every valid saved bookmark and returns a new `FolderAccessLease` for the most specific canonical bookmarked root that equals or is a path-component-wise ancestor of the destination document folder, explicitly rejecting shared-string-prefix cases such as `docs` and `docs-private`; do not use the existing exact-parent equality check for this method. | | |
| TASK-006 | Add `MDViewer/Services/FolderNavigatorContextStore.swift`. Store pending navigator root identity, visibility, expanded relative paths, and selected relative path keyed by the destination document URL; never transfer a live `FolderAccessLease`. Consume the context once in the destination `ContentView`, call `restoredNavigatorAccess(forDocumentContainedBy:)` to acquire a new lease, and only then enumerate or start the watcher. Clear the pending context on success, authorization failure, or document-open failure. | | |
| TASK-007 | Add `MDViewer/Services/RecursiveFolderNavigatorWatcher.swift` using the macOS system `FSEventStream` API with file events, 250-millisecond latency, one canonical root, generation rejection, and explicit stop on root delete/rename/revoke. Event handling may identify affected paths but must re-enumerate only directories already loaded in navigator state. Do not replace `MarkdownFolderWatcher`, which remains responsible for sibling navigation. | | |

### Implementation Phase 3

- **GOAL-003**: Add the optional MDViewer macOS navigator UI and command integration.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-008 | Add `MDViewer/FolderNavigatorState.swift` as a `@MainActor ObservableObject`. Own a newly acquired root lease, loaded children by relative directory, expanded paths, selected/current relative path, loading/error/truncation state, visibility, width, refresh generation, and watcher lifetime. Enforce the 5,000-node loaded limit before merging responses. On filesystem events, refresh only affected directories that are already loaded; never recursively enumerate unopened branches. | | |
| TASK-009 | Add `MDViewer/FolderNavigatorSidebar.swift` using SwiftUI `List` with `OutlineGroup` or an equivalent flattened visible-row projection. Provide explicit disclosure buttons, selected/current styling, loading/error rows, VoiceOver labels, and keyboard handling for Up, Down, Left, Right, Home, End, Return, and Space. | | |
| TASK-010 | Refactor `MDViewer/ContentView.swift` to wrap the existing `MarkdownWebView` in `NavigationSplitView`. Bind column visibility to `FolderNavigatorState`, preserve the existing preview state, reveal the current file, and route file activation through the existing `openDocumentAndCloseCurrent(_:)` pipeline after storing pending navigator context. Retain the active navigator-root `FolderAccessLease` with `SecurityScopedLeaseLifetime.retaining` for the complete asynchronous `openDocument(at:)` operation because a target in a sibling subfolder may not be covered by the current document-folder lease. | | |
| TASK-011 | Extend `MDViewer/DocumentCommands.swift` and `MDViewer/MDViewerApp.swift` with `canToggleFolderNavigator`, `toggleFolderNavigator`, and `chooseFolderNavigatorRoot`. Add `View > Folder Navigator`, `File > Open Folder…`, the `Cmd+Shift+B` shortcut, and a toolbar toggle without changing existing shortcuts. | | |
| TASK-012 | Extend `MDViewer/MDViewerHelpView`, `README.md`, and `docs/index.html` with folder navigator behavior, authorization scope, limits, shortcut, and read-only status. | | |

### Implementation Phase 4

- **GOAL-004**: Implement the same navigator for MDViewer+ macOS while preserving edited-document safety.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-013 | Add MDViewer+ equivalents of `FolderNavigatorModel.swift`, `FolderNavigatorTreeBuilder.swift`, `FolderNavigatorContextStore.swift`, `RecursiveFolderNavigatorWatcher.swift`, `FolderNavigatorState.swift`, and `FolderNavigatorSidebar.swift` under `MDViewerPlus/`, using the exact limits and ordering from Phase 1. The context store must transfer root identity and UI state, never a live lease; the destination state must refresh only already-loaded directories after FSEvents. | | |
| TASK-014 | Extend `MDViewerPlus/FolderAccessStore.swift` with navigator-root authorization that rejects a root whose own resource metadata identifies it as a symbolic link, accepts only a path-component-wise ancestor of the current document, rejects shared-string-prefix false ancestors, and keeps the existing `relativeResources`, `siblingNavigation`, and `navigationTools` behavior unchanged. Add `restoredNavigatorAccess(forDocumentContainedBy:)` with the same most-specific component-wise ancestor-bookmark lookup as MDViewer so every destination window acquires its own lease before enumeration or watcher startup. | | |
| TASK-015 | Refactor `MDViewerPlus/ContentView.swift` so `NavigationSplitView` contains the optional navigator and the existing view/split/edit content. The navigator must remain visible across all three `ViewMode` values and must not alter editor/preview split sizing. | | |
| TASK-016 | Route navigator file activation through `openNativeDocument(at:fragment:)`. Before opening, store pending navigator context. Extend the open path so navigator activation retains the navigator-root lease for the complete asynchronous `openDocument(at:)` operation instead of relying only on the current document-folder `folderAccess`; preserve the existing lease behavior for non-navigator opens. Preserve `DocumentOpeningPolicy`: close a clean source after successful open, keep an edited source window open, and keep the source on open failure. | | |
| TASK-017 | Extend `MDViewerPlus/DocumentCommands.swift` and the app toolbar with `View > Folder Navigator`, `File > Open Folder…`, `Cmd+Shift+B`, and `Reveal Current Document in Folder Navigator`. Keep `Cmd+E`, `Cmd+K`, and `Cmd+Shift+O` unchanged. | | |
| TASK-018 | Extend MDViewer+ Help, `README.md`, `docs/index.html`, and `CHANGELOG.md` with the navigator behavior and dirty-document rule. | | |

### Implementation Phase 5

- **GOAL-005**: Add a confined lazy tree API and recursive watcher support to MDViewer+ for Windows.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-019 | Create `src-tauri/src/folder_tree.rs`. Implement `list_folder_children(root_path, relative_directory, depth)` and `resolve_folder_markdown(root_path, relative_file)` using existing confinement helpers from `commands.rs`. Reuse the existing `is_markdown_file_name` behavior from `commands.rs`; move it to a shared crate-visible helper module only if Rust visibility prevents direct reuse, and do not introduce a second extension list. Call `symlink_metadata` and reject `file_type().is_symlink()` for the selected root and every root-relative entry before canonicalizing; do not rely on `canonicalize()` for symlink rejection. Return only normalized relative paths and reject hidden entries, packages where detectable, unsupported files, traversal, absolute paths, and root escapes. | | |
| TASK-020 | Register the new commands in `src-tauri/src/lib.rs` and expose no new Tauri capability. Reuse the already-authorized `tauri-plugin-dialog` open dialog in directory-selection mode from JavaScript to establish an explicit root path; do not add a custom native folder-picker or filesystem command. | | |
| TASK-021 | Extend the watcher implementation in `src-tauri/src/commands.rs` or move it to `src-tauri/src/folder_watcher.rs`. Add a recursive navigator watcher mode using `notify::RecursiveMode::Recursive`, one active root, 250-millisecond debounce, generation rejection, and a distinct `folder-tree-changed` event. Keep the existing document-folder watcher behavior unchanged. | | |
| TASK-022 | Add Rust unit tests covering direct child enumeration, directory-first ordering, every extension, hidden entries, symlinks, traversal, encoded separators, root escape, depth limit, child truncation, payload limit, root deletion, and recursive watcher events. | | |

### Implementation Phase 6

- **GOAL-006**: Add the accessible Windows navigator UI without weakening the hardened frontend.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-023 | Add `src/js/folder-navigator.js`. Implement state, lazy loading, stale request rejection, expansion persistence for the active root, loaded-node accounting, current-file reveal, refresh reconciliation, and file activation through the injected existing `openFile` callback. A `folder-tree-changed` event may refresh only affected directories already present in the loaded-node map; it must not trigger recursive enumeration of unopened branches. | | |
| TASK-024 | Update `src/web/index.html` to insert `#folder-navigator` before the editor/preview workspace. Use `role="tree"`, `role="treeitem"`, `role="group"`, `aria-expanded`, `aria-selected`, a live status region, an explicit root button, a close button, and a navigator splitter. | | |
| TASK-025 | Update `src/web/styles/app.css` so `#app` supports hidden and visible navigator states, persisted width between 180 and 420 pixels, high-contrast focus, nested indentation, selected/current distinction, overflow containment, and unchanged editor/preview splitter behavior. | | |
| TASK-026 | Update `src/js/main.js` to initialize and dispose the navigator, propagate successful document opens, subscribe to `folder-tree-changed`, and use `performOpenFile` so navigator selection receives the existing dirty confirmation and revision-race protection. | | |
| TASK-027 | Update `src-tauri/src/menu.rs` and `src/js/shortcuts.js` with `toggle_folder_navigator`, `open_folder_navigator_root`, `reveal_in_folder_navigator`, and `CmdOrCtrl+Shift+B`. Route menu events through the existing `menu-event` channel. | | |
| TASK-028 | Add frontend tests for rendering, expansion, keyboard navigation, root changes, loading/error/truncation states, stale-response rejection, refresh reconciliation, dirty-confirmation cancellation, and support-link coexistence. Extend security tests to assert that JavaScript never receives or constructs an out-of-root absolute child path. | | |

### Implementation Phase 7

- **GOAL-007**: Complete cross-platform integration, documentation, packaging, and release validation.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-029 | Add UI tests for each platform that toggle the navigator, expand a directory, open a clean document, verify current-file selection, and close/reopen the navigator. Add an MDViewer+ macOS test proving an edited source remains open and a Windows test proving discard cancellation preserves the current document and navigator selection. | | |
| TASK-030 | Run Lite and Full unit tests and isolated builds in both macOS repositories. Run Node tests, Rust formatting, Full/Lite Rust tests, clippy, NSIS/MSI builds, mutual replacement verification, artifact audits, and WinGet validation in Windows. | | |
| TASK-031 | Update bundle audits to assert that the navigator adds no opposite-edition renderer modules, no network entitlement changes, no broad Tauri capability, and no new runtime dependency. Compare compressed Lite artifacts against the v2.0.1 baselines recorded by TASK-001 and fail only when the increase exceeds both 512 KiB and 2 percent for the same platform/package format. | | |
| TASK-032 | Update `README.md`, GitHub Pages, in-app Help, About/version metadata, release notes, and screenshots in all repositories. Document that the navigator is optional, read-only, bounded, local-only, and available in both editions. | | |
| TASK-033 | Bump all products to v2.1.0, publish signed/notarized macOS Lite/Full DMGs and unsigned Windows Lite/Full NSIS/MSI installers, verify checksums independently, and prepare but do not submit updated WinGet manifests. | | |

## 3. Alternatives

- **ALT-001**: Keep only Quick Open. Rejected because flat filename filtering does not communicate directory structure for documentation trees and Markdown vaults.
- **ALT-002**: Add a permanently visible sidebar. Rejected because it changes the lightweight default and reduces document space for users who do not need folder navigation.
- **ALT-003**: Implement the navigator only in Full. Rejected because the feature is native, small, and independent of Mermaid, highlighting, YAML, and other Full-only modules.
- **ALT-004**: Build a complete recursive index at root selection time. Rejected because it creates avoidable latency, memory use, and denial-of-service risk on large folders.
- **ALT-005**: Add file mutation operations in v2.1.0. Rejected to keep the first release read-only and avoid destructive-operation, undo, collision, and dirty-editor complexity.
- **ALT-006**: Use a third-party tree-view library. Rejected to preserve physical size, accessibility control, dependency provenance, and shared Lite/Full behavior.

## 4. Dependencies

- **DEP-001**: Existing SwiftUI `NavigationSplitView`, `List`, and AppKit security-scoped bookmarks, plus newly adopted macOS system `FSEventStream` APIs from CoreServices; no third-party macOS dependency is introduced.
- **DEP-002**: Existing `FolderAccessStore`, document-opening policies, Quick Open catalog, internal-link resolver, and folder watcher implementations in both macOS repositories.
- **DEP-003**: Existing Tauri invoke/event bridge, Rust `notify` crate, dialog plugin, path-confinement helpers, document policy, and menu event routing in the Windows repository.
- **DEP-004**: Existing Lite/Full build, audit, release, notarization, installer replacement, checksum, GitHub Pages, and WinGet validation workflows.

## 5. Files

- **FILE-001**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/ContentView.swift` — integrate navigator state and `NavigationSplitView`.
- **FILE-002**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/DocumentCommands.swift` — add navigator commands and shortcut.
- **FILE-003**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/FolderAccessStore.swift` — authorize and restore navigator roots.
- **FILE-004**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/Services/MarkdownFolderWatcher.swift` — remain unchanged except shared lifecycle hooks if required.
- **FILE-005**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/FolderNavigatorModel.swift` — new tree contract and limits.
- **FILE-006**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/FolderNavigatorState.swift` — new per-window state.
- **FILE-007**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/FolderNavigatorSidebar.swift` — new accessible UI.
- **FILE-008**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/Services/FolderNavigatorTreeBuilder.swift` — new confined lazy enumerator.
- **FILE-009**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/Services/FolderNavigatorContextStore.swift` — new cross-window context transfer.
- **FILE-010**: `/Users/torstenmahr/dev/GitHub/mdviewer/MDViewer/Services/RecursiveFolderNavigatorWatcher.swift` — new recursive native watcher.
- **FILE-011**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/ContentView.swift` — integrate navigator without changing view/edit/split semantics.
- **FILE-012**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/DocumentCommands.swift` — add navigator commands.
- **FILE-013**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/FolderAccessStore.swift` — authorize ancestor roots.
- **FILE-014**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/FolderNavigatorModel.swift` — new tree contract.
- **FILE-015**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/FolderNavigatorState.swift` — new dirty-safe per-window state.
- **FILE-016**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/FolderNavigatorSidebar.swift` — new accessible UI.
- **FILE-017**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/FolderNavigatorTreeBuilder.swift` — new confined lazy enumerator.
- **FILE-018**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/FolderNavigatorContextStore.swift` — new clean/edited window context transfer.
- **FILE-019**: `/Users/torstenmahr/dev/GitHub/mdviewerplus/MDViewerPlus/RecursiveFolderNavigatorWatcher.swift` — new recursive native watcher.
- **FILE-020**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src-tauri/src/folder_tree.rs` — new confined Rust tree API.
- **FILE-021**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src-tauri/src/commands.rs` — watcher and command integration.
- **FILE-022**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src-tauri/src/lib.rs` — register new commands and state.
- **FILE-023**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src-tauri/src/menu.rs` — add navigator menu commands.
- **FILE-024**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src/js/folder-navigator.js` — new frontend tree controller.
- **FILE-025**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src/js/main.js` — integrate tree with document lifecycle.
- **FILE-026**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src/js/shortcuts.js` — add shortcut fallback.
- **FILE-027**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src/web/index.html` — add tree and splitter markup.
- **FILE-028**: `/Users/torstenmahr/dev/GitHub/mdviewerplus-windows/src/web/styles/app.css` — add bounded responsive layout.
- **FILE-029**: All three repositories' `README.md`, `docs/index.html`, Help views/dialogs, version manifests, architecture tests, bundle audits, release workflows, and changelogs — document and release v2.1.0.

## 6. Testing

- **TEST-001**: Unit-test direct child enumeration, extension filtering, hidden/package/symlink rejection, stable ordering, and empty directories on macOS and Windows.
- **TEST-002**: Unit-test canonical root confinement against `..`, absolute paths, encoded separators, case differences, Unicode normalization, symlink escapes, and shared-string-prefix false ancestors such as `docs` versus `docs-private`.
- **TEST-003**: Unit-test depth, direct-child, loaded-node, and payload truncation with explicit user-visible truncation metadata.
- **TEST-004**: Unit-test state reconciliation so expanded paths survive refresh while removed nodes, invalid selection, and stale responses are discarded.
- **TEST-005**: Unit-test watcher generation handling, debounce, nested create/remove/rename events, root move/delete, and stop/restart behavior.
- **TEST-006**: Unit-test most-specific component-wise ancestor-bookmark selection, creation of a distinct destination-window lease, retention of the source navigator-root lease until an asynchronous sibling-subfolder open completes, navigator-context transfer when a macOS clean source closes, an edited MDViewer+ source stays open, missing authorization, stale bookmarks, and document-open failure.
- **TEST-007**: Unit-test Windows dirty confirmation, revision changes during target read, cancellation, failed read, and successful replacement from a tree selection.
- **TEST-008**: Accessibility-test tree roles, names, expanded/selected/current state, focus order, keyboard navigation, live status, and toolbar/menu commands.
- **TEST-009**: Integration-test current-file reveal, folder expansion, tree refresh, Quick Open coexistence, sibling navigation coexistence, internal-link coexistence, and root reset for an outside document.
- **TEST-010**: Build/audit-test Lite and Full physical exclusions, shared app identity, installer replacement, unchanged capabilities/entitlements, compressed size thresholds, checksums, notarization, Gatekeeper, and WinGet manifest validation.

## 7. Risks & Assumptions

- **RISK-001**: Large or adversarial folder trees can cause UI stalls or memory growth. Lazy enumeration and hard limits are mandatory release gates.
- **RISK-002**: macOS document-based navigation opens a destination window before closing a clean source. The source window's security-scoped lease ends when that window closes, so pending context must be consumed atomically and the destination must acquire a new lease from the most-specific saved ancestor bookmark before tree enumeration or watcher startup.
- **RISK-003**: MDViewer+ edited documents must not be closed after navigation. The existing `DocumentOpeningPolicy` must remain the sole source-disposition authority.
- **RISK-004**: Recursive filesystem events can arrive in bursts or after a root changes. Generation identifiers and debounce must reject stale work.
- **RISK-005**: A sidebar can reduce editor/preview usability on small windows. Enforce the width bounds and allow one-command hiding.
- **RISK-006**: Windows JavaScript receiving absolute child paths would weaken the current native confinement boundary. Only normalized relative node paths may cross IPC.
- **ASSUMPTION-001**: Users need structural navigation, not full IDE project management, in v2.1.0.
- **ASSUMPTION-002**: A selected root containing up to 5,000 loaded visible nodes is sufficient for the intended documentation and Markdown-vault workflows.
- **ASSUMPTION-003**: Existing security-scoped bookmark storage can be extended to ancestor roots without changing the app sandbox entitlement set.
- **ASSUMPTION-004**: The existing Rust `notify` dependency supports recursive watching on supported Windows versions.

## 8. Related Specifications / Further Reading

[MDViewer repository](https://github.com/trsdn/mdviewer)

[MDViewer+ repository](https://github.com/trsdn/mdviewerplus)

[MDViewer+ for Windows repository](https://github.com/trsdn/mdviewerplus-windows)

[SwiftUI NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)

[Apple File System Events Programming Guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/)

[WAI-ARIA Tree View Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/treeview/)
