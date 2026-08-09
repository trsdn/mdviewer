import Foundation

/// Deterministic Markdown file catalog for a single authorized folder.
///
/// Sibling navigation, Quick Open and internal-link resolution all read
/// through this one type so extension handling, hidden-file rules and ordering
/// can never diverge between features.
enum MarkdownFileCatalog {
    /// The only extensions MDViewer opens as documents.
    static let supportedExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd"
    ]

    static func isSupportedMarkdownFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Canonical form used for every identity comparison in the app.
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Enumerates the Markdown files directly inside `directoryURL`.
    ///
    /// Never recurses, never follows package contents and never returns hidden
    /// files. Results are canonicalized and ordered deterministically.
    static func files(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isHiddenKey, .isRegularFileKey]
        let entries = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        )

        return try entries.filter { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  isSupportedMarkdownFile(url) else {
                return false
            }

            let values = try url.resourceValues(forKeys: resourceKeys)
            return values.isHidden != true && values.isRegularFile == true
        }
        .map(canonical)
        .sorted(by: filenamePrecedes)
    }

    /// Case-insensitive filename ordering with a stable case-sensitive
    /// tiebreaker, so two files differing only in case never swap positions.
    static func filenamePrecedes(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent
        let rhsName = rhs.lastPathComponent
        let lhsFolded = Array(lhsName.lowercased().utf8)
        let rhsFolded = Array(rhsName.lowercased().utf8)

        if lhsFolded == rhsFolded {
            return lhsName.utf8.lexicographicallyPrecedes(rhsName.utf8)
        }
        return lhsFolded.lexicographicallyPrecedes(rhsFolded)
    }
}
