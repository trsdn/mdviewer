import Foundation

enum FolderNavigatorTreeBuilder {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        .isHiddenKey, .isPackageKey
    ]

    static func children(
        rootURL: URL,
        relativeDirectory: String,
        depth: Int,
        limits: FolderNavigatorLimits = .standard,
        fileManager: FileManager = .default
    ) throws -> FolderNavigatorChildren {
        guard depth >= 0, depth < limits.maximumDepth else {
            throw FolderNavigatorError.depthLimit
        }
        try rejectSymbolicLink(rootURL)
        let root = FolderNavigatorPath.canonical(rootURL)
        let components = try FolderNavigatorPath.validatedComponents(relativeDirectory)
        guard components.count == depth else {
            throw FolderNavigatorError.invalidRelativePath
        }

        var directory = root
        for component in components {
            directory.appendPathComponent(component, isDirectory: true)
            try rejectSymbolicLink(directory)
        }
        let canonicalDirectory = FolderNavigatorPath.canonical(directory)
        guard FolderNavigatorPath.contains(root: root, item: canonicalDirectory) else {
            throw FolderNavigatorError.outsideAuthorizedRoot
        }
        let directoryValues = try canonicalDirectory.resourceValues(forKeys: resourceKeys)
        guard directoryValues.isDirectory == true, directoryValues.isPackage != true else {
            throw FolderNavigatorError.accessDenied
        }

        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: canonicalDirectory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants, .skipsSubdirectoryDescendants],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw FolderNavigatorError.accessDenied
        }
        var accepted: [(URL, FolderNavigatorNodeKind)] = []
        accepted.reserveCapacity(limits.maximumDirectChildren)
        var acceptedCount = 0

        while let entry = enumerator.nextObject() as? URL {
            guard !entry.lastPathComponent.hasPrefix(".") else { continue }
            let values = try entry.resourceValues(forKeys: resourceKeys)
            if values.isDirectory == true {
                // Be explicit even though `.skipsSubdirectoryDescendants` is
                // requested: no descendant may enter this direct-child result.
                enumerator.skipDescendants()
            }
            guard values.isHidden != true,
                  values.isPackage != true,
                  values.isSymbolicLink != true else { continue }
            let candidate: (URL, FolderNavigatorNodeKind)?
            if values.isDirectory == true {
                let canonical = FolderNavigatorPath.canonical(entry)
                guard FolderNavigatorPath.contains(root: root, item: canonical) else { continue }
                candidate = (canonical, .directory)
            } else if values.isRegularFile == true,
                      MarkdownFileCatalog.isSupportedMarkdownFile(entry) {
                let canonical = FolderNavigatorPath.canonical(entry)
                guard FolderNavigatorPath.contains(root: root, item: canonical) else { continue }
                candidate = (canonical, .markdownFile)
            } else {
                candidate = nil
            }
            guard let candidate else { continue }
            acceptedCount += 1
            guard limits.maximumDirectChildren > 0 else { continue }
            if accepted.count < limits.maximumDirectChildren {
                accepted.append(candidate)
                accepted.sort(by: entryPrecedes)
            } else if let worst = accepted.last,
                      entryPrecedes(candidate, worst) {
                accepted[accepted.count - 1] = candidate
                accepted.sort(by: entryPrecedes)
            }
        }
        if let enumerationError {
            throw enumerationError
        }

        var payloadBytes = 2 // JSON array brackets
        var nodes: [FolderNavigatorNode] = []
        for (url, kind) in accepted {
            guard let relativePath = FolderNavigatorPath.relativePath(of: url, in: root) else {
                continue
            }
            let node = FolderNavigatorNode(
                id: relativePath,
                name: url.lastPathComponent,
                relativePath: relativePath,
                kind: kind,
                depth: depth + 1,
                isExpandable: kind == .directory && depth + 1 < limits.maximumDepth,
                isTruncated: kind == .directory && depth + 1 >= limits.maximumDepth
            )
            let encodedBytes = (try? JSONEncoder().encode(node).count)
                ?? limits.maximumPayloadBytes
            guard payloadBytes + encodedBytes + 1 <= limits.maximumPayloadBytes else {
                break
            }
            payloadBytes += encodedBytes + 1
            nodes.append(node)
        }
        return FolderNavigatorChildren(
            nodes: nodes,
            isTruncated: nodes.count < acceptedCount,
            omittedCount: max(0, acceptedCount - nodes.count)
        )
    }

    static func markdownFile(rootURL: URL, relativePath: String) throws -> URL {
        try rejectSymbolicLink(rootURL)
        let root = FolderNavigatorPath.canonical(rootURL)
        let components = try FolderNavigatorPath.validatedComponents(relativePath)
        guard !components.isEmpty, components.count <= FolderNavigatorLimits.standard.maximumDepth else {
            throw FolderNavigatorError.invalidRelativePath
        }
        var candidate = root
        for (index, component) in components.enumerated() {
            candidate.appendPathComponent(component)
            let values = try candidate.resourceValues(forKeys: resourceKeys)
            guard values.isHidden != true,
                  values.isPackage != true,
                  values.isSymbolicLink != true else {
                throw values.isSymbolicLink == true
                    ? FolderNavigatorError.symbolicLink
                    : FolderNavigatorError.accessDenied
            }
            let isFinal = index == components.count - 1
            guard isFinal ? values.isRegularFile == true : values.isDirectory == true else {
                throw FolderNavigatorError.unsupportedFile
            }
            let canonicalComponent = FolderNavigatorPath.canonical(candidate)
            guard FolderNavigatorPath.contains(root: root, item: canonicalComponent) else {
                throw FolderNavigatorError.outsideAuthorizedRoot
            }
        }
        let canonical = FolderNavigatorPath.canonical(candidate)
        guard FolderNavigatorPath.contains(root: root, item: canonical) else {
            throw FolderNavigatorError.outsideAuthorizedRoot
        }
        guard MarkdownFileCatalog.isSupportedMarkdownFile(canonical) else {
            throw FolderNavigatorError.unsupportedFile
        }
        return canonical
    }

    static func rejectSymbolicLink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw FolderNavigatorError.symbolicLink
        }
    }

    private static func stableNamePrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let lhsFolded = Array(lhs.lowercased().utf8)
        let rhsFolded = Array(rhs.lowercased().utf8)
        if lhsFolded == rhsFolded {
            return lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
        return lhsFolded.lexicographicallyPrecedes(rhsFolded)
    }

    private static func entryPrecedes(
        _ lhs: (URL, FolderNavigatorNodeKind),
        _ rhs: (URL, FolderNavigatorNodeKind)
    ) -> Bool {
        if lhs.1 != rhs.1 { return lhs.1 == .directory }
        return stableNamePrecedes(
            lhs.0.lastPathComponent,
            rhs.0.lastPathComponent
        )
    }
}
