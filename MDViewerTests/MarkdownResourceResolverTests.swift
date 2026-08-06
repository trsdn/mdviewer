import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MDViewer

final class MarkdownResourceResolverTests: XCTestCase {
    private var rootURL: URL!
    private let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
    }

    func testResolvesValidatedNestedImageInsideAuthorizedRoot() throws {
        let images = rootURL.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let imageURL = images.appendingPathComponent("pixel.png")
        try pngData.write(to: imageURL)

        let result = try MarkdownResourceResolver.resolveImage(
            try XCTUnwrap(URL(string: "mdviewer-resource://document/images/pixel.png")),
            under: rootURL
        )

        XCTAssertEqual(result.fileURL, imageURL.resolvingSymlinksInPath())
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertEqual(result.fileSize, pngData.count)
    }

    func testValidatesPNGJPEGAndGIFContents() throws {
        for (name, type, mime) in [
            ("pixel.png", UTType.png, "image/png"),
            ("pixel.jpg", UTType.jpeg, "image/jpeg"),
            ("pixel.gif", UTType.gif, "image/gif")
        ] {
            let fileURL = rootURL.appendingPathComponent(name)
            try writeImage(to: fileURL, type: type)

            let result = try MarkdownResourceResolver.resolveImage(
                URL(string: "mdviewer-resource://document/\(name)")!,
                under: rootURL
            )
            XCTAssertEqual(result.mimeType, mime)
        }
    }

    func testRejectsEncodedTraversalAndQueryOrFragment() throws {
        assertError(
            "mdviewer-resource://document/%2E%2E/secret.png",
            equals: .traversal
        )
        assertError(
            "mdviewer-resource://document/image.png?variant=1",
            equals: .invalidPath
        )
        assertError(
            "mdviewer-resource://document/image.png#fragment",
            equals: .invalidPath
        )
    }

    func testRejectsSymlinkEscape() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let secret = outside.appendingPathComponent("secret.png")
        try pngData.write(to: secret)
        let link = rootURL.appendingPathComponent("linked.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        assertError(
            "mdviewer-resource://document/linked.png",
            equals: .outsideAuthorizedRoot
        )
    }

    func testRejectsWrongSchemeHostAndMissingAuthorization() {
        assertError("https://document/image.png", equals: .invalidScheme)
        assertError(
            "mdviewer-resource://elsewhere/image.png",
            equals: .invalidHost
        )

        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolve(
                URL(string: "mdviewer-resource://document/image.png")!,
                under: nil
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, .unavailableRoot)
        }
    }

    func testRejectsSVGDirectoryUnsupportedAndMismatchedContent() throws {
        try Data("<svg/>".utf8).write(to: rootURL.appendingPathComponent("image.svg"))
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("folder.png"),
            withIntermediateDirectories: false
        )
        try pngData.write(to: rootURL.appendingPathComponent("image.txt"))
        try pngData.write(to: rootURL.appendingPathComponent("image.jpg"))

        assertImageError("image.svg", equals: .unsupportedType)
        assertImageError("folder.png", equals: .resourceUnavailable)
        assertImageError("image.txt", equals: .unsupportedType)
        assertImageError("image.jpg", equals: .invalidImageData)
    }

    func testRejectsOversizedEncodedImage() throws {
        let oversized = rootURL.appendingPathComponent("oversized.png")
        FileManager.default.createFile(
            atPath: oversized.path,
            contents: nil
        )
        let handle = try FileHandle(forWritingTo: oversized)
        defer { try? handle.close() }
        try handle.truncate(
            atOffset: UInt64(MarkdownResourceResolver.maximumImageBytes + 1)
        )

        assertImageError("oversized.png", equals: .resourceTooLarge)
    }

    private func assertError(
        _ value: String,
        equals expected: MarkdownResourceError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolve(URL(string: value)!, under: rootURL),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, expected, file: file, line: line)
        }
    }

    private func writeImage(to url: URL, type: UTType) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                type.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func assertImageError(
        _ path: String,
        equals expected: MarkdownResourceError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try MarkdownResourceResolver.resolveImage(
                URL(string: "mdviewer-resource://document/\(path)")!,
                under: rootURL
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? MarkdownResourceError, expected, file: file, line: line)
        }
    }
}
