import XCTest
@testable import MDViewer

final class SiblingMarkdownNavigationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testEnumeratesOnlyMarkdownFilesWithCaseInsensitiveExtensions() throws {
        for name in [
            "one.md", "two.MARKDOWN", "three.MdOwN", "four.MKD",
            "notes.txt", "extensionless"
        ] {
            try createFile(name)
        }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("folder.md"),
            withIntermediateDirectories: false
        )

        XCTAssertEqual(
            try filenames(),
            ["four.MKD", "one.md", "three.MdOwN", "two.MARKDOWN"]
        )
    }

    func testSkipsDotFilesAndFilesMarkedHidden() throws {
        try createFile(".secret.md")
        try createFile("visible.md")
        var hiddenURL = try createFile("hidden.md")
        var values = URLResourceValues()
        values.isHidden = true
        try hiddenURL.setResourceValues(values)

        XCTAssertEqual(try filenames(), ["visible.md"])
    }

    func testUsesDeterministicCaseInsensitiveFilenameOrdering() throws {
        for name in ["beta.md", "Alpha.md", "alpha.MKD", "Gamma.markdown"] {
            try createFile(name)
        }

        XCTAssertEqual(
            try filenames(),
            ["Alpha.md", "alpha.MKD", "beta.md", "Gamma.markdown"]
        )
    }

    func testTargetsDoNotWrapAtBoundaries() throws {
        let first = try createFile("a.md")
        let middle = try createFile("b.md")
        let last = try createFile("c.md")

        XCTAssertEqual(
            try SiblingMarkdownNavigation.targets(for: first),
            SiblingNavigationTargets(previous: nil, next: canonical(middle))
        )
        XCTAssertEqual(
            try SiblingMarkdownNavigation.targets(for: last),
            SiblingNavigationTargets(previous: canonical(middle), next: nil)
        )
    }

    func testResolvesPreviousAndNextTargetsAroundCurrentDocument() throws {
        let previous = try createFile("guide.markdown")
        let current = try createFile("README.MD")
        let next = try createFile("setup.mdown")

        let targets = try SiblingMarkdownNavigation.targets(for: current)

        XCTAssertEqual(targets.previous, canonical(previous))
        XCTAssertEqual(targets.next, canonical(next))
        XCTAssertEqual(targets.target(for: .previous), canonical(previous))
        XCTAssertEqual(targets.target(for: .next), canonical(next))
    }

    func testMissingCurrentDocumentHasNoTargets() throws {
        try createFile("a.md")
        try createFile("b.md")

        XCTAssertEqual(
            try SiblingMarkdownNavigation.targets(
                for: directory.appendingPathComponent("missing.md")
            ),
            .none
        )
    }

    func testEnumerationPropagatesReadErrors() {
        let missingDirectory = directory.appendingPathComponent(
            "missing",
            isDirectory: true
        )

        XCTAssertThrowsError(
            try SiblingMarkdownNavigation.markdownFiles(in: missingDirectory)
        )
    }

    func testFailedRefreshClearsPreviouslyKnownTargets() {
        let staleURL = directory.appendingPathComponent("stale.md")
        var targets = SiblingNavigationTargets(
            previous: staleURL,
            next: staleURL
        )
        let missingDocument = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("current.md")

        XCTAssertThrowsError(
            try SiblingMarkdownNavigation.refresh(
                &targets,
                for: missingDocument
            )
        )
        XCTAssertEqual(targets, .none)
    }

    func testRefreshDiscoversSiblingAddedAfterEmptyInitialResult() throws {
        let current = try createFile("current.md")
        var targets = try SiblingMarkdownNavigation.targets(for: current)
        XCTAssertEqual(targets, .none)

        let added = try createFile("next.md")
        try SiblingMarkdownNavigation.refresh(&targets, for: current)

        XCTAssertNil(targets.previous)
        XCTAssertEqual(targets.next, canonical(added))
    }

    func testReloadRefreshSilentlyClearsTargetsWhenFolderCannotBeRead() {
        let staleURL = directory.appendingPathComponent("stale.md")
        var targets = SiblingNavigationTargets(
            previous: staleURL,
            next: staleURL
        )
        let inaccessibleDocument = directory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("current.md")

        let refreshed = SiblingMarkdownNavigation.refreshAfterReload(
            &targets,
            for: inaccessibleDocument
        )

        XCTAssertFalse(refreshed)
        XCTAssertEqual(targets, .none)
    }

    private func filenames() throws -> [String] {
        try SiblingMarkdownNavigation.markdownFiles(in: directory)
            .map(\.lastPathComponent)
    }

    @discardableResult
    private func createFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("# Test".utf8).write(to: url)
        return url
    }

    private func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
