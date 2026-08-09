import Foundation
import Security

enum MarkdownRenderPageError: LocalizedError {
    case missingResource(String)
    case unreadableResource(String, Error)
    case printPreparationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "The bundled render resource “\(name)” is missing."
        case .unreadableResource(let name, let error):
            return "The bundled render resource “\(name)” couldn’t be read: \(error.localizedDescription)"
        case .printPreparationFailed(let message):
            return "The document couldn’t finish preparing for print: \(message)"
        }
    }
}

/// Builds the Content Security Policy for the render page.
///
/// Lite is nonce-only: nothing but the inlined first-party scripts and the one
/// inlined stylesheet may execute. Full additionally allows scripts from the
/// bundle-only module path so `import()` can load the vendored Mermaid,
/// highlight.js and js-yaml modules. Nothing else is relaxed: no `eval`, no
/// `unsafe-inline` script or style, no remote origin, no frames, objects, base
/// navigation or form submission.
struct MarkdownContentSecurityPolicy {
    let capabilities: EditionCapabilities

    func policy(nonce: String) -> String {
        var scriptSources = ["'nonce-\(nonce)'"]
        if capabilities.usesBundledWebModules {
            scriptSources.append(MarkdownWebModuleResolver.urlPrefix)
        }

        return [
            "default-src 'none'",
            "script-src \(scriptSources.joined(separator: " "))",
            "style-src 'nonce-\(nonce)'",
            "img-src \(MarkdownResourceResolver.scheme):",
            "font-src 'none'",
            "media-src 'none'",
            "connect-src 'none'",
            "worker-src 'none'",
            "object-src 'none'",
            "frame-src 'none'",
            "child-src 'none'",
            "base-uri 'none'",
            "form-action 'none'"
        ].joined(separator: "; ")
    }
}

struct MarkdownRenderPage {
    private struct Resources {
        let template: String
        let marked: String
        let domPurify: String
        let markedFootnote: String
        let renderer: String
        let editionRenderer: String
        let highlighter: String

        static func load(from bundle: Bundle) throws -> Resources {
            let capabilities = EditionCapabilities.current
            return Resources(
                template: try read("template", extension: "html", from: bundle),
                marked: try read("marked.umd", extension: "js", from: bundle),
                domPurify: try read("dompurify.min", extension: "js", from: bundle),
                markedFootnote: try read(
                    "marked-footnote.umd",
                    extension: "js",
                    from: bundle
                ),
                renderer: try read("renderer", extension: "js", from: bundle),
                editionRenderer: try read(
                    capabilities.edition == .full ? "renderer-full" : "renderer-lite",
                    extension: "js",
                    from: bundle
                ),
                highlighter: capabilities.bundlesPrismHighlighter
                    ? try read("prism.min", extension: "js", from: bundle)
                    : ""
            )
        }

        private static func read(
            _ name: String,
            extension fileExtension: String,
            from bundle: Bundle
        ) throws -> String {
            let displayName = "\(name).\(fileExtension)"
            guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
                throw MarkdownRenderPageError.missingResource(displayName)
            }

            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw MarkdownRenderPageError.unreadableResource(displayName, error)
            }
        }
    }

    private static let cachedResources = Result {
        try Resources.load(from: .main)
    }

    static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    /// Runtime configuration handed to the render page as a JSON literal.
    static func configurationJSON(
        capabilities: EditionCapabilities = .current,
        nonce: String
    ) -> String {
        let configuration: [String: Any] = [
            "edition": capabilities.edition.rawValue,
            "nonce": nonce,
            "moduleBase": MarkdownWebModuleResolver.urlPrefix,
            "capabilities": [
                "prism": capabilities.bundlesPrismHighlighter,
                "broadHighlighter": capabilities.lazyBroadHighlighter,
                "frontmatter": capabilities.lazyFrontmatterCards,
                "diagrams": capabilities.lazyDiagrams
            ]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: configuration,
            options: [.sortedKeys]
        ),
            let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func makeHTML(
        capabilities: EditionCapabilities = .current
    ) throws -> String {
        let resources = try cachedResources.get()
        let nonce = makeNonce()
        let policy = MarkdownContentSecurityPolicy(capabilities: capabilities)
            .policy(nonce: nonce)

        return resources.template
            .replacingOccurrences(of: "{{CSP_POLICY}}", with: policy)
            .replacingOccurrences(of: "{{CSP_NONCE}}", with: nonce)
            .replacingOccurrences(
                of: "{{RENDER_CONFIG_JSON}}",
                with: configurationJSON(capabilities: capabilities, nonce: nonce)
            )
            .replacingOccurrences(of: "{{MARKED_JS}}", with: resources.marked)
            .replacingOccurrences(of: "{{DOMPURIFY_JS}}", with: resources.domPurify)
            .replacingOccurrences(
                of: "{{MARKED_FOOTNOTE_JS}}",
                with: resources.markedFootnote
            )
            .replacingOccurrences(of: "{{HIGHLIGHTER_JS}}", with: resources.highlighter)
            .replacingOccurrences(of: "{{RENDERER_JS}}", with: resources.renderer)
            .replacingOccurrences(
                of: "{{EDITION_RENDERER_JS}}",
                with: resources.editionRenderer
            )
    }
}
