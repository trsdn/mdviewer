import Foundation

enum SiblingNavigationDirection {
    case previous
    case next
}

struct SiblingNavigationTargets: Equatable {
    let previous: URL?
    let next: URL?

    static let none = SiblingNavigationTargets(previous: nil, next: nil)

    func target(for direction: SiblingNavigationDirection) -> URL? {
        switch direction {
        case .previous:
            return previous
        case .next:
            return next
        }
    }
}

enum SiblingMarkdownNavigation {
    static func markdownFiles(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try MarkdownFileCatalog.files(
            in: directoryURL,
            fileManager: fileManager
        )
    }

    static func targets(
        for documentURL: URL,
        fileManager: FileManager = .default
    ) throws -> SiblingNavigationTargets {
        let files = try markdownFiles(
            in: documentURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        let canonicalDocumentURL = MarkdownFileCatalog.canonical(documentURL)

        guard let index = files.firstIndex(where: {
            MarkdownFileCatalog.canonical($0) == canonicalDocumentURL
        }) else {
            return .none
        }

        return SiblingNavigationTargets(
            previous: index > files.startIndex ? files[index - 1] : nil,
            next: files.index(after: index) < files.endIndex ? files[index + 1] : nil
        )
    }

    static func refresh(
        _ currentTargets: inout SiblingNavigationTargets,
        for documentURL: URL,
        fileManager: FileManager = .default
    ) throws {
        do {
            currentTargets = try targets(
                for: documentURL,
                fileManager: fileManager
            )
        } catch {
            currentTargets = .none
            throw error
        }
    }

    @discardableResult
    static func refreshAfterReload(
        _ currentTargets: inout SiblingNavigationTargets,
        for documentURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        do {
            try refresh(
                &currentTargets,
                for: documentURL,
                fileManager: fileManager
            )
            return true
        } catch {
            currentTargets = .none
            return false
        }
    }
}
