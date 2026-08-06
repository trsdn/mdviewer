import Foundation

enum MarkdownRenderPageError: LocalizedError {
    case missingResource(String)
    case unreadableResource(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name):
            return "The bundled render resource “\(name)” is missing."
        case .unreadableResource(let name, let error):
            return "The bundled render resource “\(name)” couldn’t be read: \(error.localizedDescription)"
        }
    }
}

struct MarkdownRenderPage {
    private struct Resources {
        let template: String
        let marked: String
        let domPurify: String

        static func load(from bundle: Bundle) throws -> Resources {
            Resources(
                template: try read("template", extension: "html", from: bundle),
                marked: try read("marked.umd", extension: "js", from: bundle),
                domPurify: try read("dompurify.min", extension: "js", from: bundle)
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

    static func makeHTML() throws -> String {
        let resources = try cachedResources.get()
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")

        return resources.template
            .replacingOccurrences(of: "{{CSP_NONCE}}", with: nonce)
            .replacingOccurrences(of: "{{MARKED_JS}}", with: resources.marked)
            .replacingOccurrences(of: "{{DOMPURIFY_JS}}", with: resources.domPurify)
    }
}
