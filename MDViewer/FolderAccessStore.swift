import AppKit
import Foundation

enum FolderAccessError: LocalizedError {
    case wrongFolder
    case accessDenied
    case symbolicLink

    var errorDescription: String? {
        switch self {
        case .wrongFolder:
            return "Choose the folder containing this Markdown document."
        case .accessDenied:
            return "macOS did not grant read access to the selected folder."
        case .symbolicLink:
            return "A symbolic link cannot be used as an authorized folder."
        }
    }
}

enum FolderAccessPurpose {
    case relativeImages
    case siblingNavigation
    case internalLinks
    case quickOpen
    case folderNavigator

    func title(for documentURL: URL) -> String {
        switch self {
        case .relativeImages:
            return "Grant Read-Only Folder Access"
        case .siblingNavigation:
            return "Enable Markdown File Navigation"
        case .internalLinks:
            return "Open Linked Markdown Files"
        case .quickOpen:
            return "Enable Current-Folder Quick Open"
        case .folderNavigator:
            return "Open Folder in Navigator"
        }
    }

    func message(for documentURL: URL) -> String {
        switch self {
        case .relativeImages:
            return "Choose the folder containing \(documentURL.lastPathComponent) to load its relative images."
        case .siblingNavigation:
            return "Choose the folder containing \(documentURL.lastPathComponent) to navigate between Markdown files."
        case .internalLinks:
            return "Choose the folder containing \(documentURL.lastPathComponent) to open its relative Markdown links."
        case .quickOpen:
            return "Choose the folder containing \(documentURL.lastPathComponent) to search its Markdown files."
        case .folderNavigator:
            return "Choose this document’s folder or an ancestor. MDViewer will receive read-only access."
        }
    }
}

final class FolderAccessLease {
    let rootURL: URL
    private let securityScopedURL: URL
    private let isAccessing: Bool

    init(securityScopedURL: URL, rootURL: URL) throws {
        self.securityScopedURL = securityScopedURL
        self.rootURL = rootURL
        isAccessing = securityScopedURL.startAccessingSecurityScopedResource()
        guard isAccessing else {
            throw FolderAccessError.accessDenied
        }
    }

    deinit {
        if isAccessing {
            securityScopedURL.stopAccessingSecurityScopedResource()
        }
    }
}

@MainActor
final class FolderAccessStore {
    static let shared = FolderAccessStore()

    private let defaults: UserDefaults
    private let bookmarksKey = "authorizedDocumentFolderBookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoredAccess(for documentURL: URL) throws -> FolderAccessLease? {
        let expectedRoot = canonicalFolder(for: documentURL)
        let savedBookmarks = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        var validBookmarks: [Data] = []
        var matchingAccess: FolderAccessLease?

        for bookmark in savedBookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
                var retainedBookmark = bookmark

                if canonicalURL == expectedRoot {
                    matchingAccess = try FolderAccessLease(
                        securityScopedURL: url,
                        rootURL: canonicalURL
                    )
                    if isStale {
                        retainedBookmark = try makeReadOnlyBookmark(for: url)
                    }
                }
                validBookmarks.append(retainedBookmark)
            } catch {
                continue
            }
        }

        if validBookmarks != savedBookmarks {
            defaults.set(validBookmarks, forKey: bookmarksKey)
        }
        return matchingAccess
    }

    /// Restores the narrowest saved folder that contains the document.
    ///
    /// Every returned lease is newly acquired for the destination window.
    func restoredNavigatorAccess(
        forDocumentContainedBy documentURL: URL,
        preferredRoot: URL? = nil
    ) throws -> FolderAccessLease? {
        let documentFolder = canonicalFolder(for: documentURL)
        let preferredCanonicalRoot = preferredRoot.map(FolderNavigatorPath.canonical)
        let savedBookmarks = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        var validBookmarks: [Data] = []
        var candidates: [(url: URL, canonical: URL, bookmark: Data)] = []

        for bookmark in savedBookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmark,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                try rejectSymbolicLink(url)
                let canonical = FolderNavigatorPath.canonical(url)
                let retained = isStale ? try makeReadOnlyBookmark(for: url) : bookmark
                validBookmarks.append(retained)
                if Self.isComponentAncestor(canonical, of: documentFolder),
                   preferredCanonicalRoot == nil || canonical == preferredCanonicalRoot {
                    candidates.append((url, canonical, retained))
                }
            } catch {
                continue
            }
        }
        if validBookmarks != savedBookmarks {
            defaults.set(validBookmarks, forKey: bookmarksKey)
        }

        for candidate in candidates.sorted(by: {
            $0.canonical.pathComponents.count > $1.canonical.pathComponents.count
        }) {
            if let lease = try? FolderAccessLease(
                securityScopedURL: candidate.url,
                rootURL: candidate.canonical
            ) {
                return lease
            }
        }
        return nil
    }

    func requestAccess(
        for documentURL: URL,
        attachedTo window: NSWindow?,
        purpose: FolderAccessPurpose = .relativeImages
    ) async throws -> FolderAccessLease? {
        let expectedRoot = canonicalFolder(for: documentURL)
        let panel = NSOpenPanel()
        panel.title = purpose.title(for: documentURL)
        panel.message = purpose.message(for: documentURL)
        panel.prompt = "Grant Access"
        panel.directoryURL = expectedRoot
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        let response = await panelResponse(panel, attachedTo: window)
        guard response == .OK, let selectedURL = panel.url else { return nil }

        let canonicalSelection = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        try rejectSymbolicLink(selectedURL)
        let isAllowed = purpose == .folderNavigator
            ? Self.isComponentAncestor(canonicalSelection, of: expectedRoot)
            : canonicalSelection == expectedRoot
        guard isAllowed else {
            throw FolderAccessError.wrongFolder
        }

        let access = try FolderAccessLease(
            securityScopedURL: selectedURL,
            rootURL: canonicalSelection
        )
        try save(
            bookmark: makeReadOnlyBookmark(for: selectedURL),
            for: canonicalSelection
        )
        return access
    }

    private func canonicalFolder(for documentURL: URL) -> URL {
        documentURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    nonisolated static func isComponentAncestor(_ ancestor: URL, of item: URL) -> Bool {
        let ancestorComponents = FolderNavigatorPath.canonical(ancestor).pathComponents
        let itemComponents = FolderNavigatorPath.canonical(item).pathComponents
        return itemComponents.count >= ancestorComponents.count
            && Array(itemComponents.prefix(ancestorComponents.count)) == ancestorComponents
    }

    nonisolated static func mostSpecificAncestor(
        of item: URL,
        among candidates: [URL]
    ) -> URL? {
        candidates
            .map(FolderNavigatorPath.canonical)
            .filter { isComponentAncestor($0, of: item) }
            .max { $0.pathComponents.count < $1.pathComponents.count }
    }

    private func rejectSymbolicLink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw FolderAccessError.symbolicLink
        }
    }

    private func makeReadOnlyBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private func panelResponse(
        _ panel: NSOpenPanel,
        attachedTo window: NSWindow?
    ) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window {
                panel.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            } else {
                continuation.resume(returning: panel.runModal())
            }
        }
    }

    private func save(bookmark: Data, for rootURL: URL) throws {
        let existing = defaults.array(forKey: bookmarksKey) as? [Data] ?? []
        var retained: [Data] = []

        for data in existing {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            if url.standardizedFileURL.resolvingSymlinksInPath() != rootURL {
                retained.append(data)
            }
        }

        retained.append(bookmark)
        defaults.set(retained, forKey: bookmarksKey)
    }
}
