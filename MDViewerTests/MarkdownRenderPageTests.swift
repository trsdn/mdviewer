import AppKit
import WebKit
import XCTest
@testable import MDViewer

@MainActor
final class MarkdownRenderPageTests: XCTestCase {
    func testExecutableHTMLAndScriptClosingPayloadAreRemoved() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            </script><script>window.__owned = true</script>
            <img src="https://example.com/tracker.png" onerror="window.__owned = true">
            <svg onload="window.__owned = true"><circle></circle></svg>
            <iframe srcdoc="<script>window.__owned = true</script>"></iframe>
            <form action="https://example.com"><button>Submit</button></form>
            <a href="javascript:window.__owned = true">bad</a>
            """,
            in: webView
        )

        let result = try await values(
            """
            ({
                executed: window.__owned === true,
                scripts: document.querySelectorAll('#content script').length,
                svgs: document.querySelectorAll('#content svg').length,
                frames: document.querySelectorAll('#content iframe').length,
                forms: document.querySelectorAll('#content form').length,
                eventAttributes: document.querySelectorAll('#content [onerror], #content [onload]').length,
                remoteImageKept: document.querySelector('#content img')?.hasAttribute('src') === true,
                unsafeLinkKept: document.querySelector('#content a')?.hasAttribute('href') === true
            })
            """,
            in: webView
        )

        XCTAssertFalse(bool(result, "executed"))
        XCTAssertEqual(int(result, "scripts"), 0)
        XCTAssertEqual(int(result, "svgs"), 0)
        XCTAssertEqual(int(result, "frames"), 0)
        XCTAssertEqual(int(result, "forms"), 0)
        XCTAssertEqual(int(result, "eventAttributes"), 0)
        XCTAssertFalse(bool(result, "remoteImageKept"))
        XCTAssertFalse(bool(result, "unsafeLinkKept"))
    }

    func testNormalGFMAndApprovedHTMLArePreserved() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            ## Status

            <details open><summary>More</summary>H<sub>2</sub>O and x<sup>2</sup></details>

            - [x] Complete

            | Name | Value |
            | --- | --- |
            | A | B |

            ~~removed~~
            """,
            in: webView
        )

        let result = try await values(
            """
            ({
                headingID: document.querySelector('#content h2')?.id || '',
                details: document.querySelectorAll('#content details[open]').length,
                summary: document.querySelectorAll('#content summary').length,
                tables: document.querySelectorAll('#content table').length,
                deleted: document.querySelectorAll('#content del').length,
                checkboxType: document.querySelector('#content input')?.type || '',
                checkboxDisabled: document.querySelector('#content input')?.disabled === true,
                checkboxChecked: document.querySelector('#content input')?.checked === true
            })
            """,
            in: webView
        )

        XCTAssertEqual(result["headingID"] as? String, "status")
        XCTAssertEqual(int(result, "details"), 1)
        XCTAssertEqual(int(result, "summary"), 1)
        XCTAssertEqual(int(result, "tables"), 1)
        XCTAssertEqual(int(result, "deleted"), 1)
        XCTAssertEqual(result["checkboxType"] as? String, "checkbox")
        XCTAssertTrue(bool(result, "checkboxDisabled"))
        XCTAssertTrue(bool(result, "checkboxChecked"))
    }

    func testLinksFragmentsAndImagesFollowPolicy() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            # Section

            [web](https://example.com) [mail](mailto:test@example.com)
            [fragment](#section) [relative](docs/next.md)

            ![remote](https://example.com/image.png)
            ![local](images/image.png)
            ![traversal](../secret.png)
            ![svg](image.svg)
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
                const anchors = Object.fromEntries(
                    Array.from(document.querySelectorAll('#content a'))
                        .map((anchor) => [anchor.textContent, anchor.getAttribute('href')])
                );
                const images = Object.fromEntries(
                    Array.from(document.querySelectorAll('#content img'))
                        .map((image) => [image.getAttribute('alt'), image.getAttribute('src')])
                );
                return {
                    web: anchors.web,
                    mail: anchors.mail,
                    fragment: anchors.fragment,
                    relative: anchors.relative,
                    remote: images.remote,
                    local: images.local,
                    traversal: images.traversal,
                    svg: images.svg
                };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(result["web"] as? String, "https://example.com")
        XCTAssertEqual(result["mail"] as? String, "mailto:test@example.com")
        XCTAssertEqual(result["fragment"] as? String, "#section")
        XCTAssertTrue(result["relative"] is NSNull)
        XCTAssertTrue(result["remote"] is NSNull)
        XCTAssertEqual(result["local"] as? String, "images/image.png")
        XCTAssertTrue(result["traversal"] is NSNull)
        XCTAssertTrue(result["svg"] is NSNull)
    }

    func testAuthorizedRelativePNGLoadsThroughCustomScheme() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try pngData.write(to: rootURL.appendingPathComponent("pixel.png"))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(
            MarkdownResourceSchemeHandler(authorizedRoot: rootURL),
            forURLScheme: MarkdownResourceResolver.scheme
        )
        let webView = try await loadRenderPage(
            configuration: configuration,
            baseURL: MarkdownResourceResolver.baseURL
        )
        try await render("![pixel](pixel.png)", in: webView)

        var loaded = false
        for _ in 0..<30 {
            loaded = try await webView.evaluateJavaScript(
                "document.querySelector('#content img')?.naturalWidth === 1"
            ) as? Bool == true
            if loaded { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTAssertTrue(loaded)
    }

    func testAppearanceAndZoomDoNotRerenderOrReplaceContent() async throws {
        let webView = try await loadRenderPage()
        try await render("# Kept", in: webView)

        let before = try await values(
            "({ count: window.__mdviewerRenderCount, text: document.querySelector('h1').textContent })",
            in: webView
        )
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.pageZoom = 1.4
        let after = try await values(
            "({ count: window.__mdviewerRenderCount, text: document.querySelector('h1').textContent })",
            in: webView
        )

        XCTAssertEqual(int(before, "count"), 1)
        XCTAssertEqual(int(after, "count"), 1)
        XCTAssertEqual(after["text"] as? String, "Kept")
        XCTAssertEqual(webView.pageZoom, 1.4, accuracy: 0.001)
    }

    private var pngData: Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadRenderPage(
        configuration: WKWebViewConfiguration? = nil,
        baseURL: URL? = nil
    ) async throws -> WKWebView {
        let config = configuration ?? WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        let waiter = NavigationWaiter()
        webView.navigationDelegate = waiter

        try await withCheckedThrowingContinuation { continuation in
            waiter.completion = { result in
                continuation.resume(with: result)
            }
            do {
                webView.loadHTMLString(
                    try MarkdownRenderPage.makeHTML(),
                    baseURL: baseURL
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
        return webView
    }

    private func render(_ markdown: String, in webView: WKWebView) async throws {
        _ = try await webView.callAsyncJavaScript(
            "return window.renderMarkdown(markdown);",
            arguments: ["markdown": markdown],
            in: nil,
            contentWorld: .page
        )
    }

    private func values(_ script: String, in webView: WKWebView) async throws -> [String: Any] {
        let value = try await webView.evaluateJavaScript(script)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func bool(_ values: [String: Any], _ key: String) -> Bool {
        (values[key] as? NSNumber)?.boolValue == true
    }

    private func int(_ values: [String: Any], _ key: String) -> Int {
        (values[key] as? NSNumber)?.intValue ?? -1
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    var completion: ((Result<Void, Error>) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completion?(.success(()))
        completion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        completion?(.failure(error))
        completion = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        completion?(.failure(error))
        completion = nil
    }
}
