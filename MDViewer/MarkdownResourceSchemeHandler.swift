import Foundation
import WebKit

final class MarkdownResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let lock = NSLock()
    private var rootURL: URL?

    init(authorizedRoot: URL?) {
        rootURL = authorizedRoot
    }

    var authorizedRoot: URL? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return rootURL
        }
        set {
            lock.lock()
            rootURL = newValue
            lock.unlock()
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard urlSchemeTask.request.httpMethod == nil
                    || urlSchemeTask.request.httpMethod == "GET",
                  let requestURL = urlSchemeTask.request.url else {
                throw MarkdownResourceError.invalidPath
            }

            let image = try MarkdownResourceResolver.resolveImage(
                requestURL,
                under: authorizedRoot
            )
            let data = try Data(contentsOf: image.fileURL, options: .mappedIfSafe)
            let response = URLResponse(
                url: requestURL,
                mimeType: image.mimeType,
                expectedContentLength: image.fileSize,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
