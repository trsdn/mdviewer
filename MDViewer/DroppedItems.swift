import Foundation

/// Classification of a Finder drop into the items MDViewer can act on.
enum DroppedItems {
    struct Classification: Equatable {
        var markdownFiles: [URL] = []
        var folders: [URL] = []
        var unsupported: [URL] = []
    }

    /// Splits dropped URLs into Markdown files, folders, and everything else.
    ///
    /// `isDirectory` returns `nil` when the item does not exist, which counts
    /// as unsupported. Duplicates are removed and the drop order is preserved.
    static func classify(
        _ urls: [URL],
        isDirectory: (URL) -> Bool?
    ) -> Classification {
        var result = Classification()
        var seen: Set<URL> = []

        for url in urls {
            let canonical = MarkdownFileCatalog.canonical(url)
            guard seen.insert(canonical).inserted else { continue }

            switch isDirectory(url) {
            case .some(true):
                result.folders.append(url)
            case .some(false):
                if MarkdownFileCatalog.isSupportedMarkdownFile(url) {
                    result.markdownFiles.append(url)
                } else {
                    result.unsupported.append(url)
                }
            case .none:
                result.unsupported.append(url)
            }
        }

        return result
    }

    /// Explains why a drop was rejected.
    static func rejectionMessage(for unsupported: [URL]) -> String {
        let extensions = MarkdownFileCatalog.supportedExtensions
            .sorted()
            .map { ".\($0)" }
            .joined(separator: ", ")

        guard let first = unsupported.first else {
            return "Drop a Markdown file (\(extensions)) or a folder."
        }

        if unsupported.count == 1 {
            return "“\(first.lastPathComponent)” is not a Markdown file. "
                + "Drop a Markdown file (\(extensions)) or a folder."
        }

        return "None of the \(unsupported.count) dropped items is a Markdown "
            + "file. Drop a Markdown file (\(extensions)) or a folder."
    }
}
