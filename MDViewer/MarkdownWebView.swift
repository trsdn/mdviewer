import SwiftUI
import WebKit

enum MarkdownLinkDestination: Equatable {
    case samePageFragment
    case external
    case blocked
}

struct MarkdownNavigationPolicy {
    static func destination(for url: URL) -> MarkdownLinkDestination {
        if url.fragment != nil,
           url.scheme?.lowercased() == MarkdownResourceResolver.scheme,
           url.host?.lowercased() == MarkdownResourceResolver.host,
           (url.path.isEmpty || url.path == "/"),
           url.query == nil {
            return .samePageFragment
        }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return .blocked
        }
        return .external
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let text: String
    let appearanceMode: AppearanceMode
    let zoomLevel: Double
    let resourceRoot: URL?
    var onError: ((String) -> Void)?
    var onRelativeImages: (([String]) -> Void)?

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
        coordinator.lastAppearance = appearanceMode
        coordinator.lastZoom = zoomLevel
        coordinator.lastResourceRoot = resourceRoot

        applyAppearance(to: webView)
        applyZoom(to: webView)
        coordinator.loadRenderPage()
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
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

        if coordinator.lastAppearance != appearanceMode {
            coordinator.lastAppearance = appearanceMode
            applyAppearance(to: webView)
        }

        if coordinator.lastZoom != zoomLevel {
            coordinator.lastZoom = zoomLevel
            applyZoom(to: webView)
        }

        coordinator.requestRender(text)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: MarkdownWebView
        var pendingText = ""
        var lastAppearance: AppearanceMode = .system
        var lastZoom: Double = 1.0
        var lastResourceRoot: URL?
        weak var webView: WKWebView?
        var resourceHandler: MarkdownResourceSchemeHandler?

        private var isPageReady = false
        private var lastRenderedText: String?
        private var renderGeneration = 0

        init(_ parent: MarkdownWebView) {
            self.parent = parent
            super.init()
        }

        func loadRenderPage() {
            guard let webView else { return }

            do {
                isPageReady = false
                lastRenderedText = nil
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
                case .failure(let error):
                    self.lastRenderedText = nil
                    self.report(error)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView === self.webView else { return }
            isPageReady = true
            lastRenderedText = nil
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
                if MarkdownNavigationPolicy.destination(for: url) == .samePageFragment {
                    decisionHandler(.allow)
                } else {
                    openExternalLink(url)
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
                if MarkdownNavigationPolicy.destination(for: url) == .samePageFragment {
                    webView.load(navigationAction.request)
                } else {
                    openExternalLink(url)
                }
            }
            return nil
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

    private func applyAppearance(to webView: WKWebView) {
        switch appearanceMode {
        case .system:
            webView.appearance = nil
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
