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
    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd"
    ]

    static func markdownFiles(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isHiddenKey, .isRegularFileKey]
        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        return try entries.filter { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  markdownExtensions.contains(url.pathExtension.lowercased())
            else {
                return false
            }

            let values = try url.resourceValues(forKeys: resourceKeys)
            return values.isHidden != true && values.isRegularFile == true
        }
        .map(canonical)
        .sorted(by: filenamePrecedes)
    }

    static func targets(
        for documentURL: URL,
        fileManager: FileManager = .default
    ) throws -> SiblingNavigationTargets {
        let files = try markdownFiles(
            in: documentURL.deletingLastPathComponent(),
            fileManager: fileManager
        )
        let canonicalDocumentURL = canonical(documentURL)

        guard let index = files.firstIndex(where: {
            canonical($0) == canonicalDocumentURL
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

    private static func filenamePrecedes(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent
        let rhsName = rhs.lastPathComponent
        let lhsFolded = Array(lhsName.lowercased().utf8)
        let rhsFolded = Array(rhsName.lowercased().utf8)

        if lhsFolded == rhsFolded {
            return lhsName.utf8.lexicographicallyPrecedes(rhsName.utf8)
        }
        return lhsFolded.lexicographicallyPrecedes(rhsFolded)
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
