import AppKit
import Foundation

enum FolderAccessError: LocalizedError {
    case wrongFolder
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .wrongFolder:
            return "Choose the folder that directly contains this Markdown document."
        case .accessDenied:
            return "macOS did not grant read access to the selected folder."
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

    func requestAccess(
        for documentURL: URL,
        attachedTo window: NSWindow?
    ) async throws -> FolderAccessLease? {
        let expectedRoot = canonicalFolder(for: documentURL)
        let panel = NSOpenPanel()
        panel.title = "Grant Read-Only Folder Access"
        panel.message = "Choose the folder containing \(documentURL.lastPathComponent) to load its relative images."
        panel.prompt = "Grant Access"
        panel.directoryURL = expectedRoot
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false

        let response = await panelResponse(panel, attachedTo: window)
        guard response == .OK, let selectedURL = panel.url else { return nil }

        let canonicalSelection = selectedURL.standardizedFileURL.resolvingSymlinksInPath()
        guard canonicalSelection == expectedRoot else {
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
