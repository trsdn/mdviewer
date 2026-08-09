import SwiftUI
import WebKit

enum MarkdownLinkDestination: Equatable {
    case samePageFragment
    case internalMarkdown(String)
    case external
    case blocked
}

struct MarkdownNavigationPolicy {
    static let internalScheme = "mdviewer-document"

    static func destination(for url: URL) -> MarkdownLinkDestination {
        if url.fragment != nil,
           url.scheme?.lowercased() == MarkdownResourceResolver.scheme,
           url.host?.lowercased() == MarkdownResourceResolver.host,
           (url.path.isEmpty || url.path == "/"),
           url.query == nil {
            return .samePageFragment
        }

        if url.scheme?.lowercased() == internalScheme,
           url.host?.lowercased() == "open",
           url.query == nil,
           url.fragment == nil,
           url.user == nil,
           url.password == nil,
           url.port == nil {
            let encoded = String(url.path.drop(while: { $0 == "/" }))
            if !encoded.isEmpty,
               let rawLink = encoded.removingPercentEncoding,
               !rawLink.isEmpty,
               rawLink.utf16.count <= InternalMarkdownLinkResolver.maximumRawLength {
                return .internalMarkdown(rawLink)
            }
        }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return .blocked
        }
        return .external
    }
}

@MainActor
final class MarkdownWebViewController: ObservableObject {
    fileprivate weak var webView: WKWebView?
    fileprivate weak var coordinator: MarkdownWebView.Coordinator?

    func find(
        _ query: String,
        backwards: Bool = false,
        completion: @escaping (Bool) -> Void
    ) {
        guard let webView, !query.isEmpty else {
            completion(false)
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { result in
            completion(result.matchFound)
        }
    }

    func dismissFind() {
        let configuration = WKFindConfiguration()
        webView?.find("", configuration: configuration) { _ in }
    }

    func scrollToHeading(_ id: String) {
        webView?.callAsyncJavaScript(
            "return window.scrollToHeading(id);",
            arguments: ["id": id],
            in: nil,
            in: .page,
            completionHandler: nil
        )
    }

    func printDocument() {
        guard let webView else { return }
        guard let coordinator else {
            webView.printOperation(with: NSPrintInfo.shared).run()
            return
        }
        coordinator.preparePrint { _ in
            webView.printOperation(with: NSPrintInfo.shared).run()
        }
    }
}

struct ThemeApplicationRequest: Equatable {
    let id: Int
    let palette: ThemePalette
}

struct ThemeApplicationState {
    private(set) var desiredPalette: ThemePalette
    private(set) var inFlightRequest: ThemeApplicationRequest?
    private(set) var appliedPalette: ThemePalette?
    private var nextRequestID = 0

    init(desiredPalette: ThemePalette) {
        self.desiredPalette = desiredPalette
    }

    mutating func setDesiredPalette(_ palette: ThemePalette) {
        desiredPalette = palette
    }

    mutating func beginNextApplication() -> ThemeApplicationRequest? {
        guard inFlightRequest == nil, appliedPalette != desiredPalette else {
            return nil
        }
        nextRequestID += 1
        let request = ThemeApplicationRequest(id: nextRequestID, palette: desiredPalette)
        inFlightRequest = request
        return request
    }

    @discardableResult
    mutating func complete(requestID: Int, succeeded: Bool) -> Bool {
        guard let request = inFlightRequest, request.id == requestID else {
            return false
        }
        inFlightRequest = nil
        if succeeded {
            appliedPalette = request.palette
        }
        return true
    }

    mutating func resetForPageLoad() {
        inFlightRequest = nil
        appliedPalette = nil
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let palette: ThemePalette
    let zoomLevel: Double
    let resourceRoot: URL?
    let controller: MarkdownWebViewController
    var onError: ((String) -> Void)?
    var onRelativeImages: (([String]) -> Void)?
    var onOutline: (([OutlineEntry]) -> Void)?
    var onInternalMarkdownLink: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let resourceHandler = MarkdownResourceSchemeHandler(authorizedRoot: resourceRoot)
        configuration.setURLSchemeHandler(
            resourceHandler,
            forURLScheme: MarkdownResourceResolver.scheme
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.clipboardHandlerName
        )
        configuration.userContentController.add(
            context.coordinator,
            name: Coordinator.printReadyHandlerName
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setAccessibilityIdentifier("markdownPreview")
        webView.setAccessibilityLabel("Markdown preview")
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        let coordinator = context.coordinator
        coordinator.webView = webView
        coordinator.resourceHandler = resourceHandler
        coordinator.pendingText = text
        coordinator.setDesiredPalette(palette)
        coordinator.lastZoom = zoomLevel
        coordinator.lastResourceRoot = resourceRoot
        controller.webView = webView
        controller.coordinator = coordinator

        applyNativeAppearance(to: webView)
        applyZoom(to: webView)
        coordinator.loadRenderPage()
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.clipboardHandlerName
        )
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.printReadyHandlerName
        )
        coordinator.stopThemeApplication()
        coordinator.cancelPendingPrint()
        if coordinator.parent.controller.webView === webView {
            coordinator.parent.controller.webView = nil
        }
        if coordinator.parent.controller.coordinator === coordinator {
            coordinator.parent.controller.coordinator = nil
        }
        coordinator.webView = nil
        coordinator.resourceHandler = nil
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if coordinator.lastResourceRoot != resourceRoot {
            coordinator.lastResourceRoot = resourceRoot
            coordinator.resourceHandler?.authorizedRoot = resourceRoot
            coordinator.invalidateRender()
        }

        if coordinator.desiredPalette != palette {
            coordinator.setDesiredPalette(palette)
            applyNativeAppearance(to: webView)
        }

        if coordinator.lastZoom != zoomLevel {
            coordinator.lastZoom = zoomLevel
            applyZoom(to: webView)
        }

        coordinator.requestThemeApplication()
        coordinator.requestRender(text)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
        WKScriptMessageHandler {
        static let clipboardHandlerName = "copyText"
        static let printReadyHandlerName = "printReady"
        static let maximumClipboardCharacters = 1_000_000
        /// Upper bound while waiting for the page to confirm print preparation
        /// (forced diagram rendering, frontmatter card expansion). Printing
        /// proceeds with best-effort content if this elapses without a signal.
        static let printPreparationTimeout: Duration = .seconds(10)

        var parent: MarkdownWebView
        var pendingText = ""
        var lastZoom: Double = 1.0
        var lastResourceRoot: URL?
        weak var webView: WKWebView?
        var resourceHandler: MarkdownResourceSchemeHandler?

        private var isPageReady = false
        private var lastRenderedText: String?
        private var renderGeneration = 0
        private var themeState: ThemeApplicationState
        private var themeRetryTask: Task<Void, Never>?
        private var themeRetryCount = 0
        private let maximumAutomaticThemeRetries = 2
        private var pendingPrintCompletion: ((Result<Void, Error>) -> Void)?
        private var printTimeoutTask: Task<Void, Never>?

        var desiredPalette: ThemePalette {
            themeState.desiredPalette
        }

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            self.themeState = ThemeApplicationState(desiredPalette: parent.palette)
            super.init()
        }

        func setDesiredPalette(_ palette: ThemePalette) {
            guard themeState.desiredPalette != palette else { return }
            themeState.setDesiredPalette(palette)
            themeRetryTask?.cancel()
            themeRetryTask = nil
            themeRetryCount = 0
        }

        func stopThemeApplication() {
            themeRetryTask?.cancel()
            themeRetryTask = nil
        }

        func loadRenderPage() {
            guard let webView else { return }

            do {
                isPageReady = false
                lastRenderedText = nil
                themeState.resetForPageLoad()
                themeRetryTask?.cancel()
                themeRetryTask = nil
                themeRetryCount = 0
                webView.loadHTMLString(
                    try MarkdownRenderPage.makeHTML(),
                    baseURL: MarkdownResourceResolver.baseURL
                )
            } catch {
                report(error)
            }
        }

        func invalidateRender() {
            lastRenderedText = nil
            requestRender(pendingText)
        }

        /// Forces lazy print-only work (full Mermaid rendering, expanded
        /// frontmatter cards) to settle before printing.
        ///
        /// This deliberately does not use `callAsyncJavaScript`'s return-value
        /// bridging: awaiting a heavy asynchronous chain (Full's Mermaid
        /// dynamic-import graph) directly as the result of a native JS
        /// evaluation call can fail at the WebKit layer. Instead the page is
        /// asked to run the work on its own subsequent turn of the event loop
        /// and report completion through a dedicated script message, which
        /// this method awaits with a bounded timeout so printing always
        /// proceeds.
        func preparePrint(completion: @escaping (Result<Void, Error>) -> Void) {
            guard let webView else {
                completion(.success(()))
                return
            }
            guard pendingPrintCompletion == nil else {
                completion(.failure(
                    MarkdownRenderPageError.printPreparationFailed(
                        "error:a print request is already in progress"
                    )
                ))
                return
            }

            pendingPrintCompletion = completion
            printTimeoutTask?.cancel()
            printTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Coordinator.printPreparationTimeout)
                guard !Task.isCancelled else { return }
                self?.completePrintPreparation(.success(()))
            }

            webView.evaluateJavaScript(
                """
                if (typeof window.prepareForPrint === 'function') {
                    setTimeout(() => {
                        window.prepareForPrint().then(
                            () => window.webkit.messageHandlers.printReady.postMessage('ok'),
                            (error) => window.webkit.messageHandlers.printReady
                                .postMessage('error:' + String(error))
                        );
                    }, 0);
                } else {
                    window.webkit.messageHandlers.printReady.postMessage('error:unavailable');
                }
                """
            ) { [weak self] _, error in
                guard let self, let error else { return }
                // Dispatching the script itself failed synchronously; no
                // message will ever arrive, so resolve now.
                self.completePrintPreparation(.failure(error))
            }
        }

        /// Resolves any in-flight print preparation immediately. Called when
        /// the web view is torn down so a pending completion handler is never
        /// silently dropped.
        func cancelPendingPrint() {
            completePrintPreparation(.success(()))
        }

        private func completePrintPreparation(_ result: Result<Void, Error>) {
            printTimeoutTask?.cancel()
            printTimeoutTask = nil
            guard let completion = pendingPrintCompletion else { return }
            pendingPrintCompletion = nil
            completion(result)
        }

        func requestRender(_ text: String) {
            pendingText = text
            guard isPageReady, lastRenderedText != text else { return }

            lastRenderedText = text
            renderGeneration += 1
            let generation = renderGeneration

            webView?.callAsyncJavaScript(
                "return window.renderMarkdown(markdown);",
                arguments: ["markdown": text],
                in: nil,
                in: .page
            ) { [weak self] result in
                guard let self, generation == self.renderGeneration else { return }

                switch result {
                case .success(let value):
                    if let values = value as? [String: Any],
                       let images = values["images"] as? [String] {
                        self.parent.onRelativeImages?(images)
                    }
                    if let values = value as? [String: Any],
                       let payloads = values["outline"] as? [[String: Any]] {
                        self.parent.onOutline?(
                            payloads.compactMap(OutlineEntry.init(payload:))
                        )
                    }
                case .failure(let error):
                    self.lastRenderedText = nil
                    self.report(error)
                }
            }
        }

        func requestThemeApplication() {
            guard isPageReady,
                  let webView,
                  let request = themeState.beginNextApplication() else { return }

            webView.callAsyncJavaScript(
                "return window.applyTheme(theme);",
                arguments: ["theme": request.palette.colors.webArguments],
                in: nil,
                in: .page
            ) { [weak self] result in
                guard let self else { return }

                switch result {
                case .success:
                    guard self.themeState.complete(
                        requestID: request.id,
                        succeeded: true
                    ) else { return }
                    self.themeRetryTask?.cancel()
                    self.themeRetryTask = nil
                    self.themeRetryCount = 0
                    self.requestThemeApplication()
                case .failure(let error):
                    guard self.themeState.complete(
                        requestID: request.id,
                        succeeded: false
                    ) else { return }
                    self.report(error)
                    if self.themeState.desiredPalette == request.palette {
                        self.scheduleThemeRetry()
                    } else {
                        self.requestThemeApplication()
                    }
                }
            }
        }

        private func scheduleThemeRetry() {
            guard themeState.appliedPalette != themeState.desiredPalette,
                  themeRetryCount < maximumAutomaticThemeRetries else { return }

            themeRetryCount += 1
            themeRetryTask?.cancel()
            themeRetryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                self?.themeRetryTask = nil
                self?.requestThemeApplication()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === self.webView else { return }
            isPageReady = true
            lastRenderedText = nil
            themeState.resetForPageLoad()
            themeRetryTask?.cancel()
            themeRetryTask = nil
            themeRetryCount = 0
            requestThemeApplication()
            requestRender(pendingText)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            report("The Markdown renderer stopped unexpectedly.")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                switch MarkdownNavigationPolicy.destination(for: url) {
                case .samePageFragment:
                    decisionHandler(.allow)
                case .internalMarkdown(let rawLink):
                    parent.onInternalMarkdownLink?(rawLink)
                    decisionHandler(.cancel)
                case .external:
                    openExternalLink(url)
                    decisionHandler(.cancel)
                case .blocked:
                    decisionHandler(.cancel)
                }
                return
            }

            if navigationAction.targetFrame?.isMainFrame == true {
                let scheme = url.scheme?.lowercased()
                let isRenderPage = scheme == "about"
                    || (scheme == MarkdownResourceResolver.scheme
                        && url.host?.lowercased() == MarkdownResourceResolver.host
                        && (url.path.isEmpty || url.path == "/"))
                decisionHandler(isRenderPage ? .allow : .cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                switch MarkdownNavigationPolicy.destination(for: url) {
                case .samePageFragment:
                    webView.load(navigationAction.request)
                case .internalMarkdown(let rawLink):
                    parent.onInternalMarkdownLink?(rawLink)
                case .external:
                    openExternalLink(url)
                case .blocked:
                    break
                }
            }
            return nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case Self.clipboardHandlerName:
                guard let text = message.body as? String,
                      text.count <= Self.maximumClipboardCharacters else {
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            case Self.printReadyHandlerName:
                let body = message.body as? String ?? ""
                if body.hasPrefix("error:") {
                    completePrintPreparation(
                        .failure(MarkdownRenderPageError.printPreparationFailed(body))
                    )
                } else {
                    completePrintPreparation(.success(()))
                }
            default:
                break
            }
        }

        private func openExternalLink(_ url: URL) {
            guard MarkdownNavigationPolicy.destination(for: url) == .external else { return }
            NSWorkspace.shared.open(url)
        }

        private func report(_ error: Error) {
            report(error.localizedDescription)
        }

        private func report(_ message: String) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.onError?(message)
            }
        }
    }

    private func applyNativeAppearance(to webView: WKWebView) {
        switch palette.category {
        case .light:
            webView.appearance = NSAppearance(named: .aqua)
        case .dark:
            webView.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyZoom(to webView: WKWebView) {
        webView.pageZoom = zoomLevel
        webView.setAccessibilityValue(String(format: "%.1f", zoomLevel))
    }
}
