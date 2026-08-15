import XCTest
@testable import MDViewer

final class DroppedItemsTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/notes", isDirectory: true)
    private let markdown = URL(fileURLWithPath: "/tmp/notes/guide.md")
    private let uppercased = URL(fileURLWithPath: "/tmp/notes/README.MARKDOWN")
    private let image = URL(fileURLWithPath: "/tmp/notes/diagram.png")
    private let missing = URL(fileURLWithPath: "/tmp/notes/gone.md")

    private func classify(_ urls: [URL]) -> DroppedItems.Classification {
        DroppedItems.classify(urls) { url in
            if url == self.missing { return nil }
            return url.pathExtension.isEmpty
        }
    }

    func testMarkdownFilesAreAcceptedRegardlessOfCase() {
        let result = classify([markdown, uppercased])
        XCTAssertEqual(result.markdownFiles, [markdown, uppercased])
        XCTAssertTrue(result.folders.isEmpty)
        XCTAssertTrue(result.unsupported.isEmpty)
    }

    func testFoldersAreSeparatedFromFiles() {
        let result = classify([folder, markdown])
        XCTAssertEqual(result.folders, [folder])
        XCTAssertEqual(result.markdownFiles, [markdown])
    }

    func testUnsupportedAndMissingItemsAreRejected() {
        let result = classify([image, missing])
        XCTAssertTrue(result.markdownFiles.isEmpty)
        XCTAssertEqual(result.unsupported, [image, missing])
    }

    func testDuplicatesAreCollapsed() {
        let alias = URL(fileURLWithPath: "/tmp/notes/./guide.md")
        let result = classify([markdown, alias, folder, folder])
        XCTAssertEqual(result.markdownFiles, [markdown])
        XCTAssertEqual(result.folders, [folder])
    }

    func testOrderIsPreserved() {
        let second = URL(fileURLWithPath: "/tmp/notes/api.md")
        let result = classify([markdown, second])
        XCTAssertEqual(result.markdownFiles, [markdown, second])
    }

    func testRejectionMessageNamesASingleItem() {
        let message = DroppedItems.rejectionMessage(for: [image])
        XCTAssertTrue(message.contains("diagram.png"))
        XCTAssertTrue(message.contains(".md"))
    }

    func testRejectionMessageCountsSeveralItems() {
        let message = DroppedItems.rejectionMessage(for: [image, missing])
        XCTAssertTrue(message.contains("2"))
    }

    func testRejectionMessageHandlesAnEmptyDrop() {
        let message = DroppedItems.rejectionMessage(for: [])
        XCTAssertTrue(message.contains(".markdown"))
    }
}
