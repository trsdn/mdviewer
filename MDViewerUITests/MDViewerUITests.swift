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

    func testSiblingNavigationCommandsArePresentAndDisabledWithoutDocument() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let previous = app.menuItems["Previous Markdown File"]
        let next = app.menuItems["Next Markdown File"]
        let refresh = app.menuItems["Refresh Sibling Navigation…"]

        XCTAssertTrue(previous.exists)
        XCTAssertTrue(next.exists)
        XCTAssertTrue(refresh.exists)
        XCTAssertFalse(previous.isEnabled)
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(refresh.isEnabled)
    }

    func testRefreshSiblingNavigationIsAvailableWithoutKnownSiblings() async throws {
        let documentURL = temporaryDirectory.appendingPathComponent("Only.md")
        try Data("# Only".utf8).write(to: documentURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        try await openDocuments([documentURL])

        let window = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "Only")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.click()

        XCTAssertFalse(app.menuItems["Previous Markdown File"].isEnabled)
        XCTAssertFalse(app.menuItems["Next Markdown File"].isEnabled)
        XCTAssertTrue(app.menuItems["Refresh Sibling Navigation…"].isEnabled)
    }

    func testFindAndOutlineAreWindowScoped() async throws {
        let documentURL = temporaryDirectory.appendingPathComponent("Navigation.md")
        try Data(
            """
            # First Heading

            Body text.

            ## Second Heading
            """.utf8
        ).write(to: documentURL)

        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        try await openDocuments([documentURL])

        let window = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "Navigation")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.click()

        app.typeKey("f", modifierFlags: .command)
        let findField = window.textFields["documentFindField"]
        XCTAssertTrue(findField.waitForExistence(timeout: 3))
        findField.typeText("Second")
        let status = window.staticTexts["documentFindStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        let matchExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Match found"),
            object: status
        )
        await fulfillment(of: [matchExpectation], timeout: 3)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(findField.exists)

        app.typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.textFields["documentOutlineField"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["First Heading"].exists)
        XCTAssertTrue(app.staticTexts["Second Heading"].exists)
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
