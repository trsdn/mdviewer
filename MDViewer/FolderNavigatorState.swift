import Combine
import Foundation

struct FolderNavigatorRequestToken: Equatable, Sendable {
    let rootGeneration: Int
    let directoryGeneration: Int
    let relativeDirectory: String
}

struct FolderNavigatorRequestTracker {
    private(set) var rootGeneration = 0
    private var directoryGenerations: [String: Int] = [:]

    mutating func begin(_ relativeDirectory: String) -> FolderNavigatorRequestToken {
        let next = (directoryGenerations[relativeDirectory] ?? 0) &+ 1
        directoryGenerations[relativeDirectory] = next
        return FolderNavigatorRequestToken(
            rootGeneration: rootGeneration,
            directoryGeneration: next,
            relativeDirectory: relativeDirectory
        )
    }

    mutating func invalidate(_ directories: Set<String>) {
        for directory in directories {
            directoryGenerations[directory] = (
                directoryGenerations[directory] ?? 0
            ) &+ 1
        }
    }

    mutating func invalidateAll() {
        rootGeneration &+= 1
        directoryGenerations.removeAll()
    }

    func isCurrent(_ token: FolderNavigatorRequestToken) -> Bool {
        token.rootGeneration == rootGeneration
            && token.directoryGeneration
                == directoryGenerations[token.relativeDirectory]
    }
}

@MainActor
final class FolderNavigatorState: ObservableObject {
    enum RefreshFailureDisposition: Equatable {
        case removeSubtree
        case invalidateRoot
    }

    enum RootStatus: Equatable {
        case unavailable
        case ready
        case moved
        case accessDenied(String)
    }

    @Published var isVisible: Bool {
        didSet { defaults.set(isVisible, forKey: Self.visibilityKey) }
    }
    @Published var width: Double {
        didSet {
            let clamped = min(max(width, FolderNavigatorLayout.minimumWidth),
                              FolderNavigatorLayout.maximumWidth)
            if clamped != width {
                width = clamped
            } else {
                defaults.set(width, forKey: Self.widthKey)
            }
        }
    }
    @Published private(set) var rootURL: URL?
    @Published private(set) var rootStatus: RootStatus = .unavailable
    @Published private(set) var childrenByDirectory: [String: FolderNavigatorChildren] = [:]
    @Published private(set) var loadingDirectories = Set<String>()
    @Published var expandedRelativePaths = Set<String>()
    @Published var selectedRelativePath: String?
    @Published private(set) var currentRelativePath: String?

    private static let visibilityKey = "folderNavigatorVisible"
    private static let widthKey = "folderNavigatorWidth"
    private let defaults: UserDefaults
    private let limits: FolderNavigatorLimits
    private let watcher: RecursiveFolderNavigatorWatcher
    private var lease: FolderAccessLease?
    private var documentURL: URL?
    private var requestTracker = FolderNavigatorRequestTracker()

    init(
        defaults: UserDefaults = .standard,
        limits: FolderNavigatorLimits = .standard,
        watcher: RecursiveFolderNavigatorWatcher? = nil
    ) {
        self.defaults = defaults
        self.limits = limits
        self.watcher = watcher ?? RecursiveFolderNavigatorWatcher()
        self.isVisible = defaults.bool(forKey: Self.visibilityKey)
        let savedWidth = defaults.object(forKey: Self.widthKey) == nil
            ? FolderNavigatorLayout.defaultWidth : defaults.double(forKey: Self.widthKey)
        self.width = min(max(savedWidth, FolderNavigatorLayout.minimumWidth),
                         FolderNavigatorLayout.maximumWidth)
    }

    var rootName: String {
        rootURL?.lastPathComponent ?? "Folder Navigator"
    }

    var loadedNodeCount: Int {
        childrenByDirectory.values.reduce(0) { $0 + $1.nodes.count }
    }

    var canRevealCurrentDocument: Bool { currentRelativePath != nil }
    var activeLease: FolderAccessLease? { lease }

    func prepare(for documentURL: URL?) async {
        watcher.stop()
        requestTracker.invalidateAll()
        childrenByDirectory.removeAll()
        loadingDirectories.removeAll()
        lease = nil
        rootURL = nil
        rootStatus = .unavailable
        currentRelativePath = nil
        self.documentURL = documentURL
        guard let documentURL else { return }

        let pending = FolderNavigatorContextStore.shared.consume(for: documentURL)
        do {
            guard let restored = try FolderAccessStore.shared
                .restoredNavigatorAccess(
                    forDocumentContainedBy: documentURL,
                    preferredRoot: pending?.rootURL
                ) else {
                if let pending {
                    isVisible = pending.isVisible
                    width = pending.width
                }
                return
            }
            install(restored, pending: pending)
            if isVisible {
                await revealCurrentDocument()
            }
        } catch {
            rootStatus = .accessDenied(error.localizedDescription)
        }
    }

    func install(_ lease: FolderAccessLease, pending: PendingFolderNavigatorContext? = nil) {
        watcher.stop()
        requestTracker.invalidateAll()
        self.lease = lease
        rootURL = lease.rootURL
        rootStatus = .ready
        childrenByDirectory.removeAll()
        loadingDirectories.removeAll()
        expandedRelativePaths = pending?.expandedRelativePaths ?? []
        selectedRelativePath = pending?.selectedRelativePath
        if let pending {
            isVisible = pending.isVisible
            width = pending.width
        }
        updateCurrentRelativePath()
        startWatcher()
    }

    func toggleVisibility() {
        isVisible.toggle()
        if isVisible, rootURL != nil {
            Task { await revealCurrentDocument() }
        }
    }

    func updateWidth(_ value: Double) {
        width = value
    }

    func toggleDirectory(_ relativePath: String) {
        if expandedRelativePaths.contains(relativePath) {
            expandedRelativePaths.remove(relativePath)
            return
        }
        expandedRelativePaths.insert(relativePath)
        Task { await loadChildren(of: relativePath) }
    }

    func select(_ relativePath: String) {
        selectedRelativePath = relativePath
    }

    func fileURL(for node: FolderNavigatorNode) throws -> URL {
        guard node.kind == .markdownFile, let rootURL else {
            throw FolderNavigatorError.unsupportedFile
        }
        return try FolderNavigatorTreeBuilder.markdownFile(
            rootURL: rootURL,
            relativePath: node.relativePath
        )
    }

    func pendingContext() -> PendingFolderNavigatorContext? {
        guard let rootURL else { return nil }
        return PendingFolderNavigatorContext(
            rootURL: rootURL,
            isVisible: isVisible,
            expandedRelativePaths: expandedRelativePaths,
            selectedRelativePath: selectedRelativePath,
            width: width
        )
    }

    func revealCurrentDocument() async {
        guard let relative = currentRelativePath else { return }
        let components = relative.split(separator: "/").map(String.init)
        guard components.count <= limits.maximumDepth else {
            rootStatus = .accessDenied(FolderNavigatorError.depthLimit.localizedDescription)
            return
        }
        var directory = ""
        expandedRelativePaths.insert("")
        await loadChildren(of: "")
        for component in components.dropLast() {
            directory = directory.isEmpty ? component : "\(directory)/\(component)"
            expandedRelativePaths.insert(directory)
            await loadChildren(of: directory)
        }
        selectedRelativePath = relative
    }

    func loadChildren(
        of relativeDirectory: String,
        refreshing: Bool = false
    ) async {
        guard let rootURL, rootStatus == .ready,
              !loadingDirectories.contains(relativeDirectory) else { return }
        let depth = relativeDirectory.isEmpty
            ? 0 : relativeDirectory.split(separator: "/").count
        guard depth < limits.maximumDepth else { return }
        loadingDirectories.insert(relativeDirectory)
        let requestToken = requestTracker.begin(relativeDirectory)
        defer {
            if requestTracker.isCurrent(requestToken) {
                loadingDirectories.remove(relativeDirectory)
            }
        }
        let limits = self.limits
        do {
            let children = try await Task.detached(priority: .userInitiated) {
                try FolderNavigatorTreeBuilder.children(
                    rootURL: rootURL,
                    relativeDirectory: relativeDirectory,
                    depth: depth,
                    limits: limits
                )
            }.value
            guard requestTracker.isCurrent(requestToken),
                  self.rootURL == rootURL else { return }
            if !relativeDirectory.isEmpty,
               !Self.isLoadedDirectory(
                   relativeDirectory,
                   in: childrenByDirectory
               ) {
                removeSubtree(relativeDirectory)
                return
            }
            merge(children, for: relativeDirectory)
        } catch {
            guard requestTracker.isCurrent(requestToken) else { return }
            if Self.refreshFailureDisposition(
                refreshing: refreshing,
                relativeDirectory: relativeDirectory,
                root: rootURL
            ) == .removeSubtree {
                removeSubtree(relativeDirectory)
                return
            }
            rootStatus = .accessDenied(error.localizedDescription)
        }
    }

    private func merge(_ children: FolderNavigatorChildren, for directory: String) {
        let oldCount = childrenByDirectory[directory]?.nodes.count ?? 0
        let available = limits.maximumLoadedNodes - (loadedNodeCount - oldCount)
        let accepted = Array(children.nodes.prefix(max(0, available)))
        childrenByDirectory[directory] = FolderNavigatorChildren(
            nodes: accepted,
            isTruncated: children.isTruncated || accepted.count < children.nodes.count,
            omittedCount: children.omittedCount + max(0, children.nodes.count - accepted.count)
        )

        var reachableDirectories = Set([""])
        var queue = [""]
        while let parent = queue.popLast() {
            for node in childrenByDirectory[parent]?.nodes ?? []
            where node.kind == .directory {
                if reachableDirectories.insert(node.relativePath).inserted {
                    queue.append(node.relativePath)
                }
            }
        }
        childrenByDirectory = childrenByDirectory.filter {
            reachableDirectories.contains($0.key)
        }
        let availablePaths = Set(childrenByDirectory.values.flatMap { $0.nodes.map(\.relativePath) })
        expandedRelativePaths = expandedRelativePaths.filter {
            $0.isEmpty || availablePaths.contains($0)
        }
        if let selectedRelativePath, !availablePaths.contains(selectedRelativePath),
           selectedRelativePath != currentRelativePath {
            self.selectedRelativePath = nil
        }
    }

    private func updateCurrentRelativePath() {
        guard let documentURL, let rootURL else {
            currentRelativePath = nil
            return
        }
        currentRelativePath = FolderNavigatorPath.relativePath(
            of: documentURL,
            in: rootURL
        )
    }

    private func startWatcher() {
        guard let rootURL else { return }
        _ = watcher.start(watching: rootURL) { [weak self] paths in
            self?.refreshLoadedDirectories(affectedBy: paths)
        } onRootUnavailable: { [weak self] in
            guard let self else { return }
            self.requestTracker.invalidateAll()
            self.loadingDirectories.removeAll()
            self.rootStatus = .moved
            self.lease = nil
        }
    }

    private func refreshLoadedDirectories(affectedBy paths: Set<URL>) {
        guard let rootURL else { return }
        // A directory currently loading is eligible for a targeted retry;
        // otherwise an event during its first enumeration could invalidate
        // that request without scheduling its replacement.
        let loaded = Set(childrenByDirectory.keys).union(loadingDirectories)
        let affected: Set<String>
        if paths.contains(where: { FolderNavigatorPath.canonical($0) == rootURL }) {
            affected = loaded
        } else {
            affected = Set(loaded.filter { relative in
                var directoryURL = rootURL
                if !relative.isEmpty {
                    directoryURL.appendPathComponent(relative, isDirectory: true)
                }
                let canonicalDirectory = FolderNavigatorPath.canonical(directoryURL)
                return paths.contains {
                    let path = FolderNavigatorPath.canonical($0)
                    return path.deletingLastPathComponent() == canonicalDirectory
                        || path == canonicalDirectory
                }
            })
        }
        guard !affected.isEmpty else { return }
        requestTracker.invalidate(affected)
        loadingDirectories.subtract(affected)
        Task {
            for directory in Self.parentFirstRefreshOrder(affected) {
                guard directory.isEmpty || Self.isLoadedDirectory(
                    directory, in: childrenByDirectory
                ) else {
                    removeSubtree(directory)
                    continue
                }
                await loadChildren(of: directory, refreshing: true)
            }
        }
    }

    static func parentFirstRefreshOrder(_ directories: Set<String>) -> [String] {
        directories.sorted {
            let lhsDepth = $0.isEmpty ? 0 : $0.split(separator: "/").count
            let rhsDepth = $1.isEmpty ? 0 : $1.split(separator: "/").count
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
            return $0.utf8.lexicographicallyPrecedes($1.utf8)
        }
    }

    static func isLoadedDirectory(
        _ relativeDirectory: String,
        in children: [String: FolderNavigatorChildren]
    ) -> Bool {
        if relativeDirectory.isEmpty {
            return children[""] != nil
        }
        let components = relativeDirectory.split(separator: "/")
        let parent = components.dropLast().joined(separator: "/")
        return children[parent]?.nodes.contains {
            $0.kind == .directory
                && $0.relativePath == relativeDirectory
        } == true
    }

    static func refreshFailureDisposition(
        refreshing: Bool,
        relativeDirectory: String,
        root: URL
    ) -> RefreshFailureDisposition {
        guard refreshing, !relativeDirectory.isEmpty,
              !directoryStillExists(relativeDirectory, under: root) else {
            return .invalidateRoot
        }
        return .removeSubtree
    }

    private static func directoryStillExists(
        _ relativeDirectory: String,
        under root: URL
    ) -> Bool {
        var directory = root
        directory.appendPathComponent(relativeDirectory, isDirectory: true)
        guard let values = try? directory.resourceValues(forKeys: [
            .isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey
        ]) else {
            return false
        }
        return values.isDirectory == true
            && values.isHidden != true
            && values.isPackage != true
            && values.isSymbolicLink != true
            && FolderNavigatorPath.contains(root: root, item: directory)
    }

    private func removeSubtree(_ relativeDirectory: String) {
        guard !relativeDirectory.isEmpty else { return }
        let prefix = relativeDirectory + "/"
        childrenByDirectory = childrenByDirectory.filter {
            $0.key != relativeDirectory && !$0.key.hasPrefix(prefix)
        }
        expandedRelativePaths = expandedRelativePaths.filter {
            $0 != relativeDirectory && !$0.hasPrefix(prefix)
        }
        if let selectedRelativePath,
           selectedRelativePath == relativeDirectory
            || selectedRelativePath.hasPrefix(prefix) {
            self.selectedRelativePath = nil
        }
    }
}
