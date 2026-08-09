import Foundation

enum InternalMarkdownLinkError: LocalizedError, Equatable {
    case notRelative
    case unsupportedExtension
    case traversal
    case emptyPath
    case malformed
    case unsupportedQuery
    case outsideAuthorizedRoot
    case notARegularFile

    var errorDescription: String? {
        switch self {
        case .notRelative:
            return "Only relative links to Markdown files in the same folder can be opened."
        case .unsupportedExtension:
            return "MDViewer only opens .md, .markdown, .mdown, and .mkd links."
        case .traversal:
            return "The link tries to leave the authorized folder."
        case .emptyPath:
            return "The link does not name a file."
        case .malformed:
            return "The link could not be decoded."
        case .unsupportedQuery:
            return "Markdown links with a query string are not supported."
        case .outsideAuthorizedRoot:
            return "The link resolves outside the authorized folder."
        case .notARegularFile:
            return "The linked Markdown file is missing."
        }
    }
}

/// A relative Markdown link split into a file path and an optional fragment.
struct InternalMarkdownLink: Equatable {
    let fileURL: URL
    let fragment: String?
}

/// Resolves relative Markdown links that appear in a rendered document.
///
/// This is the single trusted decision point for issue #9. It never touches the
/// filesystem for a candidate that fails the syntactic checks, and never
/// returns a URL outside the authorized folder even when symlinks are involved.
enum InternalMarkdownLinkResolver {
    /// Maximum accepted raw link length. Long links are always malformed input.
    static let maximumRawLength = 2048

    /// Splits a raw link into its path and fragment without ever letting an
    /// encoded `#` become a fragment separator.
    static func split(rawLink: String) -> (path: String, fragment: String?)? {
        guard !rawLink.isEmpty, rawLink.utf16.count <= maximumRawLength else {
            return nil
        }
        guard let hashIndex = rawLink.firstIndex(of: "#") else {
            return (rawLink, nil)
        }
        let path = String(rawLink[rawLink.startIndex..<hashIndex])
        let fragment = String(rawLink[rawLink.index(after: hashIndex)...])
        return (path, fragment.isEmpty ? nil : fragment)
    }

    /// Resolves `rawLink` relative to `documentURL`, confined to
    /// `authorizedRoot`.
    ///
    /// - Parameters:
    ///   - rawLink: the `href` exactly as it appeared in the document.
    ///   - documentURL: the currently open document.
    ///   - authorizedRoot: the folder the user granted access to. When `nil`
    ///     the document's own folder is used, which is always readable through
    ///     the document's own sandbox grant.
    static func resolve(
        rawLink: String,
        documentURL: URL,
        authorizedRoot: URL?,
        fileManager: FileManager = .default
    ) throws -> InternalMarkdownLink {
        guard let parts = split(rawLink: rawLink) else {
            throw InternalMarkdownLinkError.malformed
        }

        let rawPath = parts.path
        guard !rawPath.isEmpty else { throw InternalMarkdownLinkError.emptyPath }
        guard !rawPath.contains("?") else {
            throw InternalMarkdownLinkError.unsupportedQuery
        }
        // Absolute, protocol-relative, UNC, drive-relative and scheme links are
        // never internal document links.
        guard !rawPath.hasPrefix("/"),
              !rawPath.hasPrefix("\\"),
              !rawPath.contains("\\"),
              !rawPath.contains(":") else {
            throw InternalMarkdownLinkError.notRelative
        }

        guard let decodedPath = rawPath.removingPercentEncoding,
              !decodedPath.isEmpty,
              !decodedPath.contains("\0"),
              !decodedPath.contains("\\"),
              !decodedPath.hasPrefix("/") else {
            throw InternalMarkdownLinkError.malformed
        }

        let components = decodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else {
            throw InternalMarkdownLinkError.emptyPath
        }
        // Reject traversal before and after decoding.
        guard !components.contains(".."), !rawPath.split(separator: "/").contains("..") else {
            throw InternalMarkdownLinkError.traversal
        }

        let meaningful = components.filter { $0 != "." }
        guard let filename = meaningful.last, !filename.isEmpty else {
            throw InternalMarkdownLinkError.emptyPath
        }
        guard MarkdownFileCatalog.isSupportedMarkdownFile(
            URL(fileURLWithPath: filename)
        ) else {
            throw InternalMarkdownLinkError.unsupportedExtension
        }

        let canonicalRoot = MarkdownFileCatalog.canonical(
            authorizedRoot ?? documentURL.deletingLastPathComponent()
        )
        let documentFolder = MarkdownFileCatalog.canonical(
            documentURL.deletingLastPathComponent()
        )
        guard isContained(documentFolder, within: canonicalRoot)
                || documentFolder == canonicalRoot else {
            throw InternalMarkdownLinkError.outsideAuthorizedRoot
        }

        var target = documentFolder
        for component in meaningful {
            target.appendPathComponent(component)
        }

        // Resolve symlinks last so a symlink that escapes the authorized root
        // is rejected rather than followed.
        let canonicalTarget = MarkdownFileCatalog.canonical(target)
        guard isContained(canonicalTarget, within: canonicalRoot) else {
            throw InternalMarkdownLinkError.outsideAuthorizedRoot
        }
        guard MarkdownFileCatalog.isSupportedMarkdownFile(canonicalTarget) else {
            throw InternalMarkdownLinkError.unsupportedExtension
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: canonicalTarget.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw InternalMarkdownLinkError.notARegularFile
        }
        guard let values = try? canonicalTarget.resourceValues(
            forKeys: [.isRegularFileKey]
        ), values.isRegularFile == true else {
            throw InternalMarkdownLinkError.notARegularFile
        }

        return InternalMarkdownLink(
            fileURL: canonicalTarget,
            fragment: parts.fragment
        )
    }

    /// True when `url` is a strict descendant of `root`.
    private static func isContained(_ url: URL, within root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let urlComponents = url.pathComponents
        guard urlComponents.count > rootComponents.count else { return false }
        return Array(urlComponents.prefix(rootComponents.count)) == rootComponents
    }
}
