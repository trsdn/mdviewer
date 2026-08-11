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

    func testFolderNavigatorIsCollapsedByDefaultAndTogglesWithShortcut() async throws {
        let documentURL = temporaryDirectory.appendingPathComponent("Navigator.md")
        try Data("# Navigator".utf8).write(to: documentURL)

        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-folderNavigatorVisible", "NO"
        ]
        app.launch()
        try await openDocuments([documentURL])

        let window = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "Navigator")
        ).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        window.click()
        XCTAssertFalse(window.descendants(matching: .any)["folderNavigator"].exists)

        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            window.descendants(matching: .any)["folderNavigator"]
                .waitForExistence(timeout: 3)
        )
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertFalse(window.descendants(matching: .any)["folderNavigator"].exists)
    }

    func testFolderNavigatorExpansionCleanOpenSelectionAndReopen() async throws {
        let guide = temporaryDirectory.appendingPathComponent("Guide", isDirectory: true)
        try FileManager.default.createDirectory(at: guide, withIntermediateDirectories: true)
        let firstURL = temporaryDirectory.appendingPathComponent("First.md")
        let secondURL = guide.appendingPathComponent("Second.md")
        try Data("# First".utf8).write(to: firstURL)
        try Data("# Second".utf8).write(to: secondURL)

        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-folderNavigatorVisible", "NO"
        ]
        app.launch()
        try await openDocuments([firstURL])

        let firstWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "First")
        ).firstMatch
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 5))
        firstWindow.click()
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(firstWindow.descendants(matching: .any)["folderNavigator"]
            .waitForExistence(timeout: 3))

        app.menuItems["Open Folder…"].click()
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let locationField = app.sheets.textFields.firstMatch
        XCTAssertTrue(locationField.waitForExistence(timeout: 2))
        locationField.typeText(temporaryDirectory.path)
        app.typeKey(.return, modifierFlags: [])
        let grantAccess = panel.buttons["Grant Access"]
        XCTAssertTrue(grantAccess.waitForExistence(timeout: 2))
        grantAccess.click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))

        let expandGuide = firstWindow.buttons["folderNavigator.disclosure.Guide"]
        XCTAssertTrue(
            expandGuide.waitForExistence(timeout: 5),
            firstWindow.debugDescription
        )
        XCTAssertEqual(expandGuide.label, "Expand Guide")
        let currentFirst = firstWindow.buttons["folderNavigator.item.First.md"]
        XCTAssertTrue(currentFirst.waitForExistence(timeout: 3))
        XCTAssertTrue(currentFirst.label.contains("current document"))
        currentFirst.click()

        // Home selects the root; Return collapses it and Space expands it.
        app.typeKey(.home, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(expandGuide.exists)
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(expandGuide.waitForExistence(timeout: 3))

        // End selects the last visible item (First.md). Home/Down then target
        // Guide; expanding it and Down/Return opens its clean child.
        app.typeKey(.end, modifierFlags: [])
        let selectedFirstRow = firstWindow.outlineRows.element(boundBy: 2)
        XCTAssertTrue(selectedFirstRow.isSelected)
        XCTAssertTrue(
            selectedFirstRow.buttons["folderNavigator.item.First.md"].exists
        )
        app.typeKey(.home, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        let guideRow = firstWindow.outlineRows.element(boundBy: 1)
        let guideSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                (object as? XCUIElement)?.isSelected == true
            },
            object: guideRow
        )
        await fulfillment(of: [guideSelected], timeout: 3)
        expandGuide.click()
        let secondFile = firstWindow.buttons["folderNavigator.item.Guide/Second.md"]
        XCTAssertTrue(secondFile.waitForExistence(timeout: 5))
        app.typeKey(.downArrow, modifierFlags: [])
        let selectedSecondRow = firstWindow.outlineRows.element(boundBy: 2)
        XCTAssertTrue(selectedSecondRow.isSelected)
        XCTAssertTrue(
            selectedSecondRow.buttons[
                "folderNavigator.item.Guide/Second.md"
            ].exists
        )
        app.typeKey(.return, modifierFlags: [])

        let secondWindow = app.windows.matching(
            NSPredicate(format: "title CONTAINS %@", "Second")
        ).firstMatch
        XCTAssertTrue(secondWindow.waitForExistence(timeout: 5))
        let currentSecond = secondWindow.buttons[
            "folderNavigator.item.Guide/Second.md"
        ]
        XCTAssertTrue(currentSecond.waitForExistence(timeout: 5))
        XCTAssertTrue(currentSecond.label.contains("current document"))
        let currentSecondRow = secondWindow.outlineRows.element(boundBy: 2)
        XCTAssertTrue(currentSecondRow.isSelected)
        XCTAssertTrue(
            currentSecondRow.buttons[
                "folderNavigator.item.Guide/Second.md"
            ].exists
        )

        secondWindow.click()
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertFalse(secondWindow.descendants(matching: .any)["folderNavigator"].exists)
        app.typeKey("b", modifierFlags: [.command, .shift])
        XCTAssertTrue(secondWindow.descendants(matching: .any)["folderNavigator"]
            .waitForExistence(timeout: 3))
        XCTAssertTrue(currentSecond.exists)
        XCTAssertTrue(currentSecond.label.contains("current document"))
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
