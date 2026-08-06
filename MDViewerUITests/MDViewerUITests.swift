import AppKit
import XCTest

@MainActor
final class MDViewerUITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testReloadAndZoomAffectOnlyActiveDocumentWindow() async throws {
        let firstURL = temporaryDirectory.appendingPathComponent("First.md")
        let secondURL = temporaryDirectory.appendingPathComponent("Second.md")
        try Data("# First original".utf8).write(to: firstURL)
        try Data("# Second original".utf8).write(to: secondURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        try await openDocuments([firstURL, secondURL])

        let firstWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "First")
        ).firstMatch
        let secondWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "Second")
        ).firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondWindow.waitForExistence(timeout: 5))

        try Data("# First reloaded".utf8).write(to: firstURL)
        try Data("# Second on disk".utf8).write(to: secondURL)

        firstWindow.click()
        app.typeKey("r", modifierFlags: .command)
        XCTAssertTrue(
            firstWindow.descendants(matching: .any)["First reloaded"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            secondWindow.descendants(matching: .any)["Second original"].exists
        )
        XCTAssertFalse(
            secondWindow.descendants(matching: .any)["Second on disk"].exists
        )

        let firstPreview = firstWindow.descendants(matching: .any)["markdownPreview"]
        let secondPreview = secondWindow.descendants(matching: .any)["markdownPreview"]
        XCTAssertTrue(firstPreview.waitForExistence(timeout: 5))
        XCTAssertTrue(secondPreview.waitForExistence(timeout: 5))
        let secondZoom = secondPreview.value as? String

        firstWindow.click()
        app.typeKey("+", modifierFlags: .command)

        XCTAssertEqual(firstPreview.value as? String, "1.1")
        XCTAssertEqual(secondPreview.value as? String, secondZoom)
    }

    private func openDocuments(_ urls: [URL]) async throws {
        let bundleIdentifier = "com.torstenmahr.MDViewer"
        let appURL = try XCTUnwrap(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first?.bundleURL
        )
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                urls,
                withApplicationAt: appURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
