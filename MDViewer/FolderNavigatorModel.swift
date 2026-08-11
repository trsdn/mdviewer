import Foundation

enum FolderNavigatorNodeKind: String, Codable {
    case directory
    case markdownFile
}

struct FolderNavigatorNode: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let relativePath: String
    let kind: FolderNavigatorNodeKind
    let depth: Int
    let isExpandable: Bool
    let isTruncated: Bool
}

struct FolderNavigatorChildren: Equatable {
    let nodes: [FolderNavigatorNode]
    let isTruncated: Bool
    let omittedCount: Int
}

struct FolderNavigatorLimits: Equatable {
    static let standard = FolderNavigatorLimits()

    let maximumDepth: Int
    let maximumDirectChildren: Int
    let maximumLoadedNodes: Int
    let maximumPayloadBytes: Int

    init(
        maximumDepth: Int = 12,
        maximumDirectChildren: Int = 500,
        maximumLoadedNodes: Int = 5_000,
        maximumPayloadBytes: Int = 1_048_576
    ) {
        self.maximumDepth = maximumDepth
        self.maximumDirectChildren = maximumDirectChildren
        self.maximumLoadedNodes = maximumLoadedNodes
        self.maximumPayloadBytes = maximumPayloadBytes
    }
}

enum FolderNavigatorLayout {
    static let defaultWidth = 240.0
    static let minimumWidth = 180.0
    static let maximumWidth = 420.0
    static let shortcut = "Cmd+Shift+B"
}

enum FolderNavigatorError: LocalizedError, Equatable {
    case invalidRelativePath
    case outsideAuthorizedRoot
    case symbolicLink
    case unsupportedFile
    case depthLimit
    case nodeLimit
    case accessDenied
    case movedRoot

    var errorDescription: String? {
        switch self {
        case .invalidRelativePath: return "The folder path is invalid."
        case .outsideAuthorizedRoot: return "The item is outside the authorized folder."
        case .symbolicLink: return "Symbolic links are not available in the folder navigator."
        case .unsupportedFile: return "The selected item is not a supported Markdown file."
        case .depthLimit: return "Folders deeper than 12 levels are not loaded."
        case .nodeLimit: return "The navigator reached its 5,000-item limit."
        case .accessDenied: return "The folder is no longer available. Choose it again to restore read-only access."
        case .movedRoot: return "The navigator folder was moved or removed."
        }
    }
}

enum FolderNavigatorPath {
    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func contains(root: URL, item: URL) -> Bool {
        let rootComponents = canonical(root).pathComponents
        let itemComponents = canonical(item).pathComponents
        return itemComponents.count >= rootComponents.count
            && Array(itemComponents.prefix(rootComponents.count)) == rootComponents
    }

    static func relativePath(of item: URL, in root: URL) -> String? {
        guard contains(root: root, item: item) else { return nil }
        let rootCount = canonical(root).pathComponents.count
        return canonical(item).pathComponents.dropFirst(rootCount).joined(separator: "/")
    }

    static func validatedComponents(_ relativePath: String) throws -> [String] {
        let folded = relativePath.lowercased()
        guard !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0"),
              !folded.contains("%2f"),
              !folded.contains("%5c") else {
            throw FolderNavigatorError.invalidRelativePath
        }
        if relativePath.isEmpty { return [] }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
        }) else {
            throw FolderNavigatorError.invalidRelativePath
        }
        return components
    }
}
