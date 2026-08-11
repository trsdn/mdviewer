import XCTest
@testable import MDViewer

private actor FolderNavigatorTestGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

final class FolderNavigatorTreeBuilderTests: XCTestCase {
    func testEnumeratesOneDirectoryWithStableDirectoryFirstOrderingAndExtensions() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try makeDirectory(named: "z-folder", in: root)
        try makeDirectory(named: "A-folder", in: root)
        for name in ["b.markdown", "A.md", "c.mdown", "d.mkd", "skip.txt", ".hidden.md"] {
            try Data("# Test".utf8).write(to: root.appendingPathComponent(name))
        }
        let nested = root.appendingPathComponent("z-folder/nested.md")
        try Data("# Nested".utf8).write(to: nested)

        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )
        XCTAssertEqual(
            result.nodes.map(\.name),
            ["A-folder", "z-folder", "A.md", "b.markdown", "c.mdown", "d.mkd"]
        )
        XCTAssertFalse(result.nodes.contains { $0.name == "nested.md" })
        XCTAssertFalse(result.isTruncated)
    }

    func testRejectsSymlinksPackagesTraversalAndRootEscapes() throws {
        let root = try makeDirectory()
        let outside = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let outsideFile = outside.appendingPathComponent("Secret.md")
        try Data("# Secret".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.md"),
            withDestinationURL: outsideFile
        )
        try makeDirectory(named: "Example.app", in: root)

        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "../outside",
            depth: 1
        )) {
            XCTAssertEqual($0 as? FolderNavigatorError, .invalidRelativePath)
        }
        for path in ["guide%2Fprivate", "guide%5Cprivate", "/absolute"] {
            XCTAssertThrowsError(try FolderNavigatorTreeBuilder.children(
                rootURL: root,
                relativeDirectory: path,
                depth: 1
            ))
        }
        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.markdownFile(
            rootURL: root,
            relativePath: "Linked.md"
        )) {
            XCTAssertEqual($0 as? FolderNavigatorError, .symbolicLink)
        }

        let linkedRoot = root.deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString)-root-link")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: linkedRoot) }
        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.children(
            rootURL: linkedRoot,
            relativeDirectory: "",
            depth: 0
        ))
    }

    func testResolvedFileRevalidatesEveryComponent() throws {
        let root = try makeDirectory()
        let outside = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let visibleDirectory = try makeDirectory(named: "Guide", in: root)
        let visibleFile = visibleDirectory.appendingPathComponent("Visible.md")
        try Data("# Visible".utf8).write(to: visibleFile)
        XCTAssertEqual(
            try FolderNavigatorTreeBuilder.markdownFile(
                rootURL: root,
                relativePath: "Guide/Visible.md"
            ),
            visibleFile
        )

        let dotDirectory = try makeDirectory(named: ".private", in: root)
        try Data("# Hidden".utf8).write(
            to: dotDirectory.appendingPathComponent("Hidden.md")
        )
        try Data("# Hidden".utf8).write(
            to: root.appendingPathComponent(".Hidden.md")
        )
        for path in [".private/Hidden.md", ".Hidden.md"] {
            XCTAssertThrowsError(try FolderNavigatorTreeBuilder.markdownFile(
                rootURL: root,
                relativePath: path
            )) {
                XCTAssertEqual($0 as? FolderNavigatorError, .invalidRelativePath)
            }
        }

        var hiddenDirectory = try makeDirectory(named: "HiddenFlag", in: root)
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try hiddenDirectory.setResourceValues(hiddenValues)
        try Data("# Hidden".utf8).write(
            to: hiddenDirectory.appendingPathComponent("Hidden.md")
        )
        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.markdownFile(
            rootURL: root,
            relativePath: "HiddenFlag/Hidden.md"
        )) {
            XCTAssertEqual($0 as? FolderNavigatorError, .accessDenied)
        }

        let package = try makeDirectory(named: "Example.app", in: root)
        let packageContents = try makeDirectory(named: "Contents", in: package)
        try Data("# Packaged".utf8).write(
            to: packageContents.appendingPathComponent("Packaged.md")
        )
        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.markdownFile(
            rootURL: root,
            relativePath: "Example.app/Contents/Packaged.md"
        )) {
            XCTAssertEqual($0 as? FolderNavigatorError, .accessDenied)
        }

        let outsideDirectory = try makeDirectory(named: "Outside", in: outside)
        try Data("# Linked".utf8).write(
            to: outsideDirectory.appendingPathComponent("Linked.md")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("LinkedDirectory"),
            withDestinationURL: outsideDirectory
        )
        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.markdownFile(
            rootURL: root,
            relativePath: "LinkedDirectory/Linked.md"
        )) {
            XCTAssertEqual($0 as? FolderNavigatorError, .symbolicLink)
        }
    }

    func testAppliesDepthChildAndPayloadLimitsWithTruncationMetadata() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<5 {
            try Data("# Test".utf8).write(
                to: root.appendingPathComponent("File\(index).md")
            )
        }
        let limits = FolderNavigatorLimits(
            maximumDepth: 12,
            maximumDirectChildren: 2,
            maximumLoadedNodes: 5_000,
            maximumPayloadBytes: 1_048_576
        )
        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0,
            limits: limits
        )
        XCTAssertEqual(result.nodes.count, 2)
        XCTAssertTrue(result.isTruncated)
        XCTAssertEqual(result.omittedCount, 3)

        let payloadLimited = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0,
            limits: FolderNavigatorLimits(
                maximumDepth: 12,
                maximumDirectChildren: 500,
                maximumLoadedNodes: 5_000,
                maximumPayloadBytes: 2
            )
        )
        XCTAssertTrue(payloadLimited.nodes.isEmpty)
        XCTAssertTrue(payloadLimited.isTruncated)
        XCTAssertEqual(payloadLimited.omittedCount, 5)

        XCTAssertThrowsError(try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "a/b/c/d/e/f/g/h/i/j/k/l",
            depth: 12
        )) {
            XCTAssertEqual($0 as? FolderNavigatorError, .depthLimit)
        }
    }

    func testLazyEnumerationRetainsOnlyBestFiveHundredEntries() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in (0..<550).reversed() {
            try Data().write(
                to: root.appendingPathComponent(
                    String(format: "File%03d.md", index)
                )
            )
        }

        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0
        )

        XCTAssertEqual(result.nodes.count, 500)
        XCTAssertEqual(result.nodes.first?.name, "File000.md")
        XCTAssertEqual(result.nodes.last?.name, "File499.md")
        XCTAssertTrue(result.isTruncated)
        XCTAssertEqual(result.omittedCount, 50)
    }

    func testBoundedSelectionStillPrefersDirectoriesOverFiles() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["A.md", "B.md", "C.md"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        try makeDirectory(named: "Zeta", in: root)
        try makeDirectory(named: "Alpha", in: root)

        let result = try FolderNavigatorTreeBuilder.children(
            rootURL: root,
            relativeDirectory: "",
            depth: 0,
            limits: FolderNavigatorLimits(
                maximumDepth: 12,
                maximumDirectChildren: 2,
                maximumLoadedNodes: 5_000,
                maximumPayloadBytes: 1_048_576
            )
        )

        XCTAssertEqual(result.nodes.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(result.omittedCount, 3)
    }

    func testComponentConfinementRejectsSharedStringPrefix() {
        let root = URL(fileURLWithPath: "/tmp/docs")
        XCTAssertTrue(FolderNavigatorPath.contains(
            root: root,
            item: root.appendingPathComponent("guide/readme.md")
        ))
        XCTAssertFalse(FolderNavigatorPath.contains(
            root: root,
            item: URL(fileURLWithPath: "/tmp/docs-private/readme.md")
        ))
        XCTAssertTrue(FolderAccessStore.isComponentAncestor(
            root,
            of: root.appendingPathComponent("guide")
        ))
        XCTAssertFalse(FolderAccessStore.isComponentAncestor(
            root,
            of: URL(fileURLWithPath: "/tmp/docs-private")
        ))
        XCTAssertEqual(
            FolderAccessStore.mostSpecificAncestor(
                of: root.appendingPathComponent("guide/chapter/README.md"),
                among: [
                    URL(fileURLWithPath: "/tmp"),
                    root,
                    root.appendingPathComponent("guide"),
                    URL(fileURLWithPath: "/tmp/docs-private")
                ]
            ),
            root.appendingPathComponent("guide")
        )
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeDirectory(named name: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class FolderNavigatorContextTests: XCTestCase {
    func testPendingContextIsConsumedOnceWithoutTransferringLease() {
        let destination = URL(fileURLWithPath: "/tmp/root/Next.md")
        let context = PendingFolderNavigatorContext(
            rootURL: URL(fileURLWithPath: "/tmp/root"),
            isVisible: true,
            expandedRelativePaths: ["", "guide"],
            selectedRelativePath: "guide/Next.md",
            width: 280
        )
        FolderNavigatorContextStore.shared.store(context, for: destination)
        XCTAssertEqual(FolderNavigatorContextStore.shared.consume(for: destination), context)
        XCTAssertNil(FolderNavigatorContextStore.shared.consume(for: destination))
    }

    func testLeaseLifetimeHelperRetainsThroughAsyncOperation() async throws {
        final class Token {}
        var token: Token? = Token()
        weak var weakToken: Token?
        weakToken = token
        let operationStarted = expectation(description: "operation started")
        let retained = token!
        token = nil

        await SecurityScopedLeaseLifetime.retaining(retained) {
            operationStarted.fulfill()
            await fulfillment(of: [operationStarted], timeout: 1)
            XCTAssertNotNil(weakToken)
        }
        XCTAssertNotNil(weakToken)
    }

    func testSlowDestinationInitializationRetainsContextUntilConsume() {
        var currentTime = Date(timeIntervalSince1970: 1_000)
        let store = FolderNavigatorContextStore(
            expiration: 600,
            maximumEntries: 4,
            now: { currentTime }
        )
        let destination = URL(fileURLWithPath: "/tmp/root/Slow.md")
        let context = makeContext(selected: "Slow.md")

        store.store(context, for: destination)
        currentTime.addTimeInterval(9 * 60)

        XCTAssertEqual(store.consume(for: destination), context)
        XCTAssertNil(store.consume(for: destination))
    }

    func testContextStoreExpiresStaleEntriesAndBoundsAbandonedOpens() {
        var currentTime = Date(timeIntervalSince1970: 2_000)
        let store = FolderNavigatorContextStore(
            expiration: 60,
            maximumEntries: 2,
            now: { currentTime }
        )
        let first = URL(fileURLWithPath: "/tmp/root/First.md")
        let second = URL(fileURLWithPath: "/tmp/root/Second.md")
        let third = URL(fileURLWithPath: "/tmp/root/Third.md")

        store.store(makeContext(selected: "First.md"), for: first)
        currentTime.addTimeInterval(1)
        store.store(makeContext(selected: "Second.md"), for: second)
        currentTime.addTimeInterval(1)
        store.store(makeContext(selected: "Third.md"), for: third)

        XCTAssertNil(store.consume(for: first))
        XCTAssertNotNil(store.consume(for: second))
        currentTime.addTimeInterval(61)
        XCTAssertNil(store.consume(for: third))
    }

    func testOpenFailureClearsPendingContextImmediately() {
        let store = FolderNavigatorContextStore()
        let destination = URL(fileURLWithPath: "/tmp/root/Failed.md")
        store.store(makeContext(selected: "Failed.md"), for: destination)
        store.clear(for: destination)
        XCTAssertNil(store.consume(for: destination))
    }

    private func makeContext(selected: String) -> PendingFolderNavigatorContext {
        PendingFolderNavigatorContext(
            rootURL: URL(fileURLWithPath: "/tmp/root"),
            isVisible: true,
            expandedRelativePaths: [""],
            selectedRelativePath: selected,
            width: 240
        )
    }
}

@MainActor
final class RecursiveFolderNavigatorWatcherTests: XCTestCase {
    func testNestedEventsAreReportedAndWatcherStopsWhenRootIsRemoved() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("guide", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let nestedChange = expectation(description: "nested change")
        let unavailable = expectation(description: "root unavailable")
        let watcher = RecursiveFolderNavigatorWatcher(debounce: .milliseconds(25))
        XCTAssertTrue(watcher.start(watching: root) { paths in
            if paths.contains(where: { $0.path.contains("Nested.md") || $0 == nested }) {
                nestedChange.fulfill()
            }
        } onRootUnavailable: {
            unavailable.fulfill()
        })

        try Data("# Nested".utf8).write(to: nested.appendingPathComponent("Nested.md"))
        await fulfillment(of: [nestedChange], timeout: 3)
        try FileManager.default.removeItem(at: root)
        await fulfillment(of: [unavailable], timeout: 3)
    }

    func testReplacementRejectsQueuedEventsFromPreviousStreamGeneration() async throws {
        let firstRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }

        let watcher = RecursiveFolderNavigatorWatcher(debounce: .milliseconds(25))
        XCTAssertTrue(watcher.start(watching: firstRoot) { _ in } onRootUnavailable: {})
        let oldGeneration = try XCTUnwrap(watcher.activeGeneration)

        let staleCallback = expectation(description: "stale callback rejected")
        staleCallback.isInverted = true
        let currentCallback = expectation(description: "current callback accepted")
        XCTAssertTrue(watcher.start(watching: secondRoot) { paths in
            if paths.contains(where: { $0.lastPathComponent == "Current.md" }) {
                currentCallback.fulfill()
            }
            if paths.contains(where: { $0.lastPathComponent == "Old.md" }) {
                staleCallback.fulfill()
            }
        } onRootUnavailable: {})
        let currentGeneration = try XCTUnwrap(watcher.activeGeneration)
        XCTAssertNotEqual(oldGeneration, currentGeneration)

        watcher.receive(
            [firstRoot.appendingPathComponent("Old.md")],
            rootUnavailable: false,
            streamGeneration: oldGeneration
        )
        await fulfillment(of: [staleCallback], timeout: 0.15)

        watcher.receive(
            [secondRoot.appendingPathComponent("Current.md")],
            rootUnavailable: false,
            streamGeneration: currentGeneration
        )
        await fulfillment(of: [currentCallback], timeout: 1)
        watcher.stop()
    }

    func testDroppedAndMustScanFlagsRequireFullLoadedDirectoryRefresh() {
        for flag in [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped
        ] {
            XCTAssertTrue(RecursiveFolderNavigatorWatcher.requiresFullRefresh(
                FSEventStreamEventFlags(flag)
            ))
        }
        XCTAssertFalse(RecursiveFolderNavigatorWatcher.requiresFullRefresh(
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        ))
    }
}

@MainActor
final class FolderNavigatorRefreshPlanningTests: XCTestCase {
    func testUnrelatedRefreshDoesNotDiscardDelayedDirectoryLoad() async {
        var tracker = FolderNavigatorRequestTracker()
        let delayedToken = tracker.begin("Guide")
        let started = expectation(description: "delayed Guide load started")
        let gate = FolderNavigatorTestGate()
        let delayedLoad = Task.detached {
            started.fulfill()
            await gate.wait()
            return "Guide result"
        }
        await fulfillment(of: [started], timeout: 1)

        // A filesystem event for another loaded directory must not invalidate
        // the in-flight Guide request.
        tracker.invalidate(["Reference"])
        await gate.open()
        let delayedResult = await delayedLoad.value
        XCTAssertEqual(delayedResult, "Guide result")
        XCTAssertTrue(tracker.isCurrent(delayedToken))

        // Targeted and root invalidation still reject their own stale work.
        tracker.invalidate(["Guide"])
        XCTAssertFalse(tracker.isCurrent(delayedToken))
        let newToken = tracker.begin("Guide")
        tracker.invalidateAll()
        XCTAssertFalse(tracker.isCurrent(newToken))
    }

    func testRefreshesParentsBeforeDescendants() {
        XCTAssertEqual(
            FolderNavigatorState.parentFirstRefreshOrder(
                ["A/B", "Z", "", "A", "A/B/C"]
            ),
            ["", "A", "Z", "A/B", "A/B/C"]
        )
    }

    func testDeletedChildIsNoLongerRefreshableAfterParentReconciliation() {
        let child = FolderNavigatorNode(
            id: "A",
            name: "A",
            relativePath: "A",
            kind: .directory,
            depth: 1,
            isExpandable: true,
            isTruncated: false
        )
        var loaded = [
            "": FolderNavigatorChildren(
                nodes: [child],
                isTruncated: false,
                omittedCount: 0
            ),
            "A": FolderNavigatorChildren(
                nodes: [],
                isTruncated: false,
                omittedCount: 0
            )
        ]
        XCTAssertTrue(FolderNavigatorState.isLoadedDirectory("A", in: loaded))

        // The parent refresh observed deletion. A queued stale refresh for A
        // must now be skipped and treated as subtree removal.
        loaded[""] = FolderNavigatorChildren(
            nodes: [],
            isTruncated: false,
            omittedCount: 0
        )
        XCTAssertFalse(FolderNavigatorState.isLoadedDirectory("A", in: loaded))
    }

    func testMissingRefreshedChildRemovesSubtreeWithoutInvalidatingRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("A", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: child)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(
            FolderNavigatorState.refreshFailureDisposition(
                refreshing: true,
                relativeDirectory: "A",
                root: root
            ),
            .removeSubtree
        )
        XCTAssertEqual(
            FolderNavigatorState.refreshFailureDisposition(
                refreshing: true,
                relativeDirectory: "",
                root: root
            ),
            .invalidateRoot
        )
    }
}
