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

    func testSharedFootnotesAlertsOutlineImagesAndCodeControls() async throws {
        let webView = try await loadRenderPage()
        try await render(
            """
            # Café
            ## Duplicate
            ## Duplicate

            > [!WARNING]
            > Keep a backup.

            - [ ] Pending

            Here is a note[^one].

            [^one]: Footnote text.

            ![Local diagram](images/diagram.png)

            ```swift
            let greeting = "hello"
            ```
            """,
            in: webView
        )

        let result = try await values(
            """
            (() => {
                document.querySelector('img.md-zoomable')?.click();
                return {
                    headingIDs: Array.from(document.querySelectorAll('h1, h2'))
                        .filter((node) => !node.closest('.footnotes'))
                        .map((node) => node.id),
                    alertLabel: document.querySelector('.md-alert-label')?.textContent || '',
                    taskDisabled: document.querySelector('.task-list-item input')?.disabled === true,
                    footnote: document.querySelectorAll('.footnotes [data-footnote-backref]').length,
                    codeFigure: document.querySelectorAll('figure.md-code').length,
                    codeLanguage: document.querySelector('.md-code-language')?.textContent || '',
                    codeButtons: document.querySelectorAll('.md-code-actions button').length,
                    exactSource: document.querySelector('figure.md-code code')?.dataset.mdviewerSource || '',
                    highlighted: document.querySelectorAll('figure.md-code code span').length,
                    imageViewerOpen: document.querySelector('.md-image-viewer')?.hidden === false
                };
            })()
            """,
            in: webView
        )

        XCTAssertEqual(result["headingIDs"] as? [String], ["café", "duplicate", "duplicate-1"])
        XCTAssertTrue((result["alertLabel"] as? String)?.contains("Warning") == true)
        XCTAssertTrue(bool(result, "taskDisabled"))
        XCTAssertEqual(int(result, "footnote"), 1)
        XCTAssertEqual(int(result, "codeFigure"), 1)
        XCTAssertEqual(result["codeLanguage"] as? String, "swift")
        XCTAssertEqual(int(result, "codeButtons"), 3)
        XCTAssertEqual(result["exactSource"] as? String, "let greeting = \"hello\"\n")
        XCTAssertGreaterThan(int(result, "highlighted"), 0)
        XCTAssertTrue(bool(result, "imageViewerOpen"))
    }

    #if MDVIEWER_FULL
    func testFullFeaturesLoadOnlyForMatchingContent() async throws {
        let webView = try await loadRenderPage()
        try await render("# Ordinary", in: webView)
        var diagnostics = try await values(
            """
            ({...window.__mdviewerFullDiagnostics})
            """,
            in: webView
        )
        XCTAssertFalse(bool(diagnostics, "highlightLoaded"))
        XCTAssertFalse(bool(diagnostics, "yamlLoaded"))
        XCTAssertFalse(bool(diagnostics, "mermaidLoaded"))
        XCTAssertFalse(bool(diagnostics, "panZoomLoaded"))

        try await render(
            """
            ---
            title: Secure metadata
            tags:
              - native
              - offline
            ---
            # Full

            ```typescript
            const value: number = 42;
            ```
            """,
            in: webView
        )
        diagnostics = try await values(
            """
            ({
                ...window.__mdviewerFullDiagnostics,
                card: document.querySelector('.md-frontmatter')?.textContent || '',
                title: document.querySelector('h1')?.textContent || '',
                highlighted: document.querySelectorAll('.hljs span').length
            })
            """,
            in: webView
        )
        XCTAssertTrue(bool(diagnostics, "highlightLoaded"))
        XCTAssertTrue(bool(diagnostics, "yamlLoaded"))
        XCTAssertFalse(bool(diagnostics, "mermaidLoaded"))
        XCTAssertTrue((diagnostics["card"] as? String)?.contains("Secure metadata") == true)
        XCTAssertEqual(diagnostics["title"] as? String, "Full")
        XCTAssertGreaterThan(int(diagnostics, "highlighted"), 0)
    }

    func testFullRejectsUnsafeFrontmatterAndRendersMermaidOffline() async throws {
        final class PrintReadySignal: NSObject, WKScriptMessageHandler {
            var received: (() -> Void)?
            func userContentController(
                _ userContentController: WKUserContentController,
                didReceive message: WKScriptMessage
            ) {
                received?()
            }
        }
        let signal = PrintReadySignal()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(signal, name: "printReady")
        let webView = try await loadRenderPage(configuration: configuration)
        try await render(
            """
            ---
            unsafe: !!js/function "() => 1"
            ---
            # Body remains

            ```mermaid
            flowchart LR
              A[Safe] --> B[Offline]
            ```
            """,
            in: webView
        )

        // Mirrors MarkdownWebView.Coordinator.preparePrint: dispatched on a
        // later turn of the event loop and reported through a script message
        // rather than awaited as the direct result of the JS-evaluation call,
        // because awaiting Full's heavy Mermaid dynamic-import chain directly
        // as a `callAsyncJavaScript`/`evaluateJavaScript` return value can
        // fail at the WebKit layer.
        let printReady = expectation(description: "print preparation completed")
        signal.received = { printReady.fulfill() }
        _ = try await webView.evaluateJavaScript(
            """
            setTimeout(() => {
                window.prepareForPrint().then(
                    () => window.webkit.messageHandlers.printReady.postMessage('ok'),
                    (error) => window.webkit.messageHandlers.printReady
                        .postMessage('error:' + String(error))
                );
            }, 0);
            """
        )
        await fulfillment(of: [printReady], timeout: 15)

        var rendered = false
        for _ in 0..<100 {
            rendered = try await webView.evaluateJavaScript(
                "document.querySelector('.md-diagram')?.dataset.state === 'rendered'"
            ) as? Bool == true
            if rendered { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let result = try await values(
            """
            ({
                body: document.querySelector('h1')?.textContent || '',
                metadataError: document.querySelector('.md-frontmatter-error')?.textContent || '',
                diagramState: document.querySelector('.md-diagram')?.dataset.state || '',
                diagramError: document.querySelector('.md-diagram-error')?.textContent || '',
                rendered: document.querySelector('.md-diagram')?.dataset.state === 'rendered',
                svg: document.querySelectorAll('.md-diagram svg').length,
                foreignObjects: document.querySelectorAll('.md-diagram foreignObject').length,
                eventAttributes: document.querySelectorAll('.md-diagram [onload], .md-diagram [onclick], .md-diagram [onerror]').length,
                mermaidLoaded: window.__mdviewerFullDiagnostics.mermaidLoaded,
                panZoomLoaded: window.__mdviewerFullDiagnostics.panZoomLoaded
            })
            """,
            in: webView
        )
        XCTAssertEqual(result["body"] as? String, "Body remains")
        XCTAssertFalse((result["metadataError"] as? String)?.isEmpty ?? true)
        XCTAssertTrue(
            bool(result, "rendered"),
            "\(result["diagramState"] ?? ""): \(result["diagramError"] ?? "")"
        )
        XCTAssertEqual(
            int(result, "svg"),
            1,
            "\(result["diagramState"] ?? ""): \(result["diagramError"] ?? "")"
        )
        XCTAssertEqual(int(result, "foreignObjects"), 0)
        XCTAssertEqual(int(result, "eventAttributes"), 0)
        XCTAssertTrue(bool(result, "mermaidLoaded"))
        XCTAssertTrue(bool(result, "panZoomLoaded"))
    }
    #endif

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
        XCTAssertEqual(
            result["relative"] as? String,
            "mdviewer-document://open/docs%2Fnext.md"
        )
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

    func testThemeAndZoomDoNotRerenderReplaceContentOrLoseScroll() async throws {
        let webView = try await loadRenderPage()
        webView.frame = CGRect(x: 0, y: 0, width: 800, height: 300)
        try await render(
            (["# Kept"] + (1...100).map { "Paragraph \($0)" }).joined(separator: "\n\n"),
            in: webView
        )
        webView.pageZoom = 1.4
        _ = try await webView.evaluateJavaScript(
            "window.__keptHeading = document.querySelector('h1'); window.scrollTo(0, 240);"
        )

        let before = try await values(
            """
            ({
                count: window.__mdviewerRenderCount,
                text: document.querySelector('h1').textContent,
                scrollY: window.scrollY,
                location: window.location.href
            })
            """,
            in: webView
        )
        let nord = ThemeRegistry.theme(id: "nord", category: .dark)
        _ = try await webView.callAsyncJavaScript(
            "return window.applyTheme(theme);",
            arguments: ["theme": nord.colors.webArguments],
            in: nil,
            contentWorld: .page
        )
        webView.appearance = NSAppearance(named: .darkAqua)
        let after = try await values(
            """
            ({
                count: window.__mdviewerRenderCount,
                text: document.querySelector('h1').textContent,
                sameNode: window.__keptHeading === document.querySelector('h1'),
                scrollY: window.scrollY,
                location: window.location.href,
                cssVariables: Object.fromEntries(
                    Array.from(document.documentElement.style)
                        .filter((name) => name.startsWith('--color-'))
                        .map((name) => [
                            name,
                            document.documentElement.style.getPropertyValue(name)
                        ])
                )
            })
            """,
            in: webView
        )

        XCTAssertEqual(int(before, "count"), 1)
        XCTAssertEqual(int(after, "count"), 1)
        XCTAssertEqual(after["text"] as? String, "Kept")
        XCTAssertTrue(bool(after, "sameNode"))
        XCTAssertEqual(int(after, "scrollY"), int(before, "scrollY"))
        XCTAssertEqual(after["location"] as? String, before["location"] as? String)
        let cssVariables = try XCTUnwrap(after["cssVariables"] as? [String: String])
        XCTAssertEqual(cssVariables, [
            "--color-bg": "#2e3440",
            "--color-fg": "#eceff4",
            "--color-border": "#4c566a",
            "--color-code-bg": "#3b4252",
            "--color-code-fg": "#e5e9f0",
            "--color-link": "#88c0d0",
            "--color-blockquote-fg": "#d8dee9",
            "--color-blockquote-border": "#4c566a",
            "--color-hr": "#4c566a",
            "--color-selection-bg": "#434c5e",
            "--color-selection-fg": "#eceff4",
            "--color-caret": "#eceff4",
            "--color-active-line": "#3b4252",
            "--color-gutter-bg": "#2e3440",
            "--color-gutter-fg": "#81a1c1",
            "--color-splitter": "#4c566a",
            "--color-splitter-hover": "#88c0d0",
            "--color-search-match": "#5e5a2f",
            "--color-search-match-selected": "#434c5e"
        ])
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
        if config.urlSchemeHandler(
            forURLScheme: MarkdownResourceResolver.scheme
        ) == nil {
            config.setURLSchemeHandler(
                MarkdownResourceSchemeHandler(authorizedRoot: nil),
                forURLScheme: MarkdownResourceResolver.scheme
            )
        }
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
                    baseURL: baseURL ?? MarkdownResourceResolver.baseURL
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
