import XCTest
@testable import MDViewer

final class DocumentCommandTests: XCTestCase {
    func testNewWindowsUseLatestZoomWithoutChangingExistingWindows() {
        let suiteName = "ZoomPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var firstWindowZoom = ZoomPreference.current(in: defaults)
        XCTAssertEqual(firstWindowZoom, 1.0)

        firstWindowZoom = ZoomPreference.value(after: .zoomIn, current: firstWindowZoom)
        ZoomPreference.save(firstWindowZoom, in: defaults)
        let secondWindowZoom = ZoomPreference.current(in: defaults)

        XCTAssertEqual(firstWindowZoom, 1.1)
        XCTAssertEqual(secondWindowZoom, 1.1)

        let changedSecondZoom = ZoomPreference.value(
            after: .zoomIn,
            current: secondWindowZoom
        )
        ZoomPreference.save(changedSecondZoom, in: defaults)

        XCTAssertEqual(firstWindowZoom, 1.1)
        XCTAssertEqual(ZoomPreference.current(in: defaults), 1.2)
    }

    func testZoomActionsClampAndReset() {
        XCTAssertEqual(
            ZoomPreference.value(after: .zoomOut, current: 0.5),
            0.5
        )
        XCTAssertEqual(
            ZoomPreference.value(after: .zoomIn, current: 3.0),
            3.0
        )
        XCTAssertEqual(
            ZoomPreference.value(after: .zoomReset, current: 2.0),
            1.0
        )
    }

    func testDocumentLoaderReadsUTF8AndSurfacesFailures() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let valid = directory.appendingPathComponent("valid.md")
        try Data("# Updated".utf8).write(to: valid)
        XCTAssertEqual(try MarkdownDocumentLoader.load(from: valid), "# Updated")

        let invalid = directory.appendingPathComponent("invalid.md")
        try Data([0xFF, 0xFE]).write(to: invalid)
        XCTAssertThrowsError(try MarkdownDocumentLoader.load(from: invalid))
        XCTAssertThrowsError(
            try MarkdownDocumentLoader.load(from: directory.appendingPathComponent("missing.md"))
        )
    }

    func testNavigationPolicyAllowsOnlyFragmentsAndApprovedExternalSchemes() {
        XCTAssertEqual(
            MarkdownNavigationPolicy.destination(
                for: URL(string: "mdviewer-resource://document/#section")!
            ),
            .samePageFragment
        )
        for value in [
            "https://example.com",
            "http://example.com",
            "mailto:test@example.com"
        ] {
            XCTAssertEqual(
                MarkdownNavigationPolicy.destination(for: URL(string: value)!),
                .external
            )
        }
        for value in [
            "javascript:alert(1)",
            "file:///tmp/secret",
            "mdviewer-resource://document/other.md",
            "mdviewer-resource://document/?query=1#section"
        ] {
            XCTAssertEqual(
                MarkdownNavigationPolicy.destination(for: URL(string: value)!),
                .blocked
            )
        }
    }
}
