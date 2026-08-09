import XCTest
@testable import MDViewer

final class MDViewer2ArchitectureTests: XCTestCase {
    func testEditionCapabilitiesAreStrictSupersetAndBundleIdentityIsShared() {
        XCTAssertTrue(EditionCapabilities.lite.bundlesPrismHighlighter)
        XCTAssertFalse(EditionCapabilities.lite.usesBundledWebModules)
        XCTAssertFalse(EditionCapabilities.full.bundlesPrismHighlighter)
        XCTAssertTrue(EditionCapabilities.full.lazyBroadHighlighter)
        XCTAssertTrue(EditionCapabilities.full.lazyFrontmatterCards)
        XCTAssertTrue(EditionCapabilities.full.lazyDiagrams)
        XCTAssertEqual(AppVersion.marketingVersion, "2.0.0")
        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            "com.torstenmahr.MDViewer"
        )
    }

    func testEditionResourcesArePhysicallySeparated() {
        let bundle = Bundle.main
        XCTAssertNotNil(bundle.url(forResource: "renderer", withExtension: "js"))
        XCTAssertNotNil(bundle.url(forResource: "marked-footnote.umd", withExtension: "js"))
        #if MDVIEWER_FULL
        XCTAssertNil(bundle.url(forResource: "prism.min", withExtension: "js"))
        XCTAssertNotNil(bundle.url(forResource: "renderer-full", withExtension: "js"))
        XCTAssertNotNil(
            bundle.url(
                forResource: "web-modules",
                withExtension: "json",
                subdirectory: "WebModules"
            )
        )
        #else
        XCTAssertNotNil(bundle.url(forResource: "prism.min", withExtension: "js"))
        XCTAssertNotNil(bundle.url(forResource: "renderer-lite", withExtension: "js"))
        XCTAssertNil(bundle.url(forResource: "renderer-full", withExtension: "js"))
        XCTAssertNil(
            bundle.url(
                forResource: "web-modules",
                withExtension: "json",
                subdirectory: "WebModules"
            )
        )
        #endif
    }

    func testContentSecurityPolicyNeverAllowsNetworkEvalFramesOrForms() {
        for capabilities in [EditionCapabilities.lite, .full] {
            let policy = MarkdownContentSecurityPolicy(capabilities: capabilities)
                .policy(nonce: "test-nonce")
            XCTAssertTrue(policy.contains("default-src 'none'"))
            XCTAssertTrue(policy.contains("connect-src 'none'"))
            XCTAssertTrue(policy.contains("worker-src 'none'"))
            XCTAssertTrue(policy.contains("frame-src 'none'"))
            XCTAssertTrue(policy.contains("object-src 'none'"))
            XCTAssertTrue(policy.contains("form-action 'none'"))
            XCTAssertFalse(policy.contains("'unsafe-eval'"))
            XCTAssertFalse(policy.contains("'unsafe-inline'"))
            XCTAssertFalse(policy.contains("http:"))
            XCTAssertFalse(policy.contains("https:"))
        }
    }

    func testInternalNavigationURLRoundTripsWithoutBroadSchemeAccess() throws {
        let raw = "Guides/Next%20Step.md#details"
        let encoded = try XCTUnwrap(
            raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        )
        let url = try XCTUnwrap(
            URL(string: "mdviewer-document://open/\(encoded)")
        )
        XCTAssertEqual(
            MarkdownNavigationPolicy.destination(for: url),
            .internalMarkdown("Guides/Next Step.md#details")
        )
        XCTAssertEqual(
            MarkdownNavigationPolicy.destination(
                for: URL(string: "mdviewer-document://other/\(encoded)")!
            ),
            .blocked
        )
    }

    func testInternalLinkResolverConfinesFilesAndRejectsTraversal() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("Current.md")
        let target = root.appendingPathComponent("Next.md")
        try Data("# Current".utf8).write(to: document)
        try Data("# Next".utf8).write(to: target)

        let resolved = try InternalMarkdownLinkResolver.resolve(
            rawLink: "Next.md#section",
            documentURL: document,
            authorizedRoot: root
        )
        XCTAssertEqual(resolved.fileURL, target)
        XCTAssertEqual(resolved.fragment, "section")

        XCTAssertThrowsError(
            try InternalMarkdownLinkResolver.resolve(
                rawLink: "../Outside.md",
                documentURL: document,
                authorizedRoot: root
            )
        ) { error in
            XCTAssertEqual(error as? InternalMarkdownLinkError, .traversal)
        }

        let outside = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        let secret = outside.appendingPathComponent("Secret.md")
        try Data("# Secret".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.md"),
            withDestinationURL: secret
        )
        XCTAssertThrowsError(
            try InternalMarkdownLinkResolver.resolve(
                rawLink: "Linked.md",
                documentURL: document,
                authorizedRoot: root
            )
        ) { error in
            XCTAssertEqual(
                error as? InternalMarkdownLinkError,
                .outsideAuthorizedRoot
            )
        }
    }

    func testQuickOpenAndOutlineFilteringAreDeterministic() {
        let root = URL(fileURLWithPath: "/authorized")
        let items = [
            QuickOpenItem(url: root.appendingPathComponent("Reference.md")),
            QuickOpenItem(url: root.appendingPathComponent("README.md")),
            QuickOpenItem(url: root.appendingPathComponent("Release-Notes.md"))
        ]
        XCTAssertEqual(
            QuickOpenMatcher.filter(items, query: "read").map(\.name),
            ["README.md", "Release-Notes.md"]
        )
        XCTAssertEqual(
            QuickOpenMatcher.filter(items, query: "rln").map(\.name),
            ["Release-Notes.md"]
        )

        let outline = [
            OutlineEntry(id: "one", level: 2, title: "One"),
            OutlineEntry(id: "child", level: 4, title: "Child"),
            OutlineEntry(id: "two", level: 2, title: "Two")
        ]
        XCTAssertEqual(OutlineFilter.indentationLevels(for: outline), [0, 2, 0])
        XCTAssertEqual(
            OutlineFilter.filter(outline, query: "hi").map(\.id),
            ["child"]
        )
    }

    func testWebModulePathsRejectTraversalAndUnknownSchemes() {
        XCTAssertTrue(
            MarkdownWebModuleResolver.isSafeRelativePath(
                "mermaid/chunks/diagram.mjs"
            )
        )
        for path in [
            "../secret.js", "/absolute.js", "nested\\file.js",
            "file.js?query=1", ""
        ] {
            XCTAssertFalse(MarkdownWebModuleResolver.isSafeRelativePath(path))
        }
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

@MainActor
final class MarkdownFolderWatcherTests: XCTestCase {
    func testWatcherUsesNativeEventsAndStopsCleanly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let changed = expectation(description: "Folder change observed")
        let watcher = MarkdownFolderWatcher(debounce: .milliseconds(50))
        XCTAssertTrue(watcher.start(watching: root) {
            changed.fulfill()
        })
        XCTAssertTrue(watcher.isWatching)

        try Data("# New".utf8).write(
            to: root.appendingPathComponent("New.md")
        )
        await fulfillment(of: [changed], timeout: 2)

        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
        XCTAssertNil(watcher.watchedFolder)
    }
}
