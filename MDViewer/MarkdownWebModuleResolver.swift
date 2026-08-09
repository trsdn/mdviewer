import Foundation

enum MarkdownWebModuleError: LocalizedError, Equatable {
    case editionDoesNotBundleModules
    case unknownModule
    case unreadableModule

    var errorDescription: String? {
        switch self {
        case .editionDoesNotBundleModules:
            return "This edition does not bundle web modules."
        case .unknownModule:
            return "The requested module is not part of the bundled allowlist."
        case .unreadableModule:
            return "The bundled module could not be read."
        }
    }
}

struct ResolvedWebModule {
    let fileURL: URL
    let mimeType: String
    let byteCount: Int
}

/// Serves the small set of ES modules MDViewer Full bundles.
///
/// The resolver is deliberately narrow:
/// * only paths under `/__mdviewer__/module/` reach it,
/// * only relative paths listed in the generated `web-modules.json` allowlist
///   are served,
/// * files are read from the application bundle only — never from a document
///   folder, a user-selected location or the network.
enum MarkdownWebModuleResolver {
    static let pathPrefix = "/__mdviewer__/module/"
    static let bundleSubdirectory = "WebModules"
    static let allowlistFilename = "web-modules.json"

    /// Absolute URL prefix used in the render page and in the Content Security
    /// Policy `script-src` source list.
    static var urlPrefix: String {
        "\(MarkdownResourceResolver.scheme)://\(MarkdownResourceResolver.host)\(pathPrefix)"
    }

    private static let cachedAllowlist: Set<String> = loadAllowlist(from: .main)

    static func loadAllowlist(from bundle: Bundle) -> Set<String> {
        guard EditionCapabilities.current.usesBundledWebModules,
              let url = bundle.url(
                  forResource: "web-modules",
                  withExtension: "json",
                  subdirectory: bundleSubdirectory
              ),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let modules = root["modules"] as? [[String: Any]] else {
            return []
        }

        return Set(
            modules.compactMap { entry -> String? in
                guard let path = entry["path"] as? String,
                      isSafeRelativePath(path) else { return nil }
                return path
            }
        )
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              !path.contains("\\"),
              !path.contains("\0"),
              path.count <= 512 else {
            return false
        }
        return path.allSatisfy { character in
            character.isLetter || character.isNumber
                || character == "." || character == "-"
                || character == "_" || character == "/"
        }
    }

    /// Returns the relative module path when `resourceURL` addresses the module
    /// namespace, or `nil` when the request is an ordinary resource request.
    static func modulePath(for resourceURL: URL) -> String? {
        guard let components = URLComponents(
            url: resourceURL,
            resolvingAgainstBaseURL: false
        ),
            let encodedPath = Optional(components.percentEncodedPath),
            encodedPath.hasPrefix(pathPrefix) else {
            return nil
        }
        return String(encodedPath.dropFirst(pathPrefix.count))
    }

    static func resolve(
        _ resourceURL: URL,
        bundle: Bundle = .main,
        allowlist: Set<String>? = nil
    ) throws -> ResolvedWebModule {
        guard EditionCapabilities.current.usesBundledWebModules else {
            throw MarkdownWebModuleError.editionDoesNotBundleModules
        }
        guard resourceURL.scheme?.lowercased() == MarkdownResourceResolver.scheme,
              resourceURL.host?.lowercased() == MarkdownResourceResolver.host,
              resourceURL.query == nil,
              resourceURL.fragment == nil,
              resourceURL.user == nil,
              resourceURL.password == nil,
              resourceURL.port == nil else {
            throw MarkdownWebModuleError.unknownModule
        }
        guard let encoded = modulePath(for: resourceURL),
              let relativePath = encoded.removingPercentEncoding,
              isSafeRelativePath(relativePath) else {
            throw MarkdownWebModuleError.unknownModule
        }
        guard (allowlist ?? cachedAllowlist).contains(relativePath) else {
            throw MarkdownWebModuleError.unknownModule
        }
        guard let root = bundle.url(
            forResource: bundleSubdirectory,
            withExtension: nil
        ) else {
            throw MarkdownWebModuleError.unknownModule
        }

        var fileURL = root
        for component in relativePath.split(separator: "/") {
            fileURL.appendPathComponent(String(component))
        }
        let canonicalRoot = MarkdownFileCatalog.canonical(root)
        let canonicalFile = MarkdownFileCatalog.canonical(fileURL)
        guard canonicalFile.pathComponents.count > canonicalRoot.pathComponents.count,
              Array(
                canonicalFile.pathComponents.prefix(canonicalRoot.pathComponents.count)
              ) == canonicalRoot.pathComponents else {
            throw MarkdownWebModuleError.unknownModule
        }
        guard let values = try? canonicalFile.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        ),
            values.isRegularFile == true,
            let size = values.fileSize else {
            throw MarkdownWebModuleError.unreadableModule
        }

        return ResolvedWebModule(
            fileURL: canonicalFile,
            mimeType: mimeType(for: canonicalFile.pathExtension.lowercased()),
            byteCount: size
        )
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension {
        case "mjs", "js": return "text/javascript"
        case "json": return "application/json"
        case "css": return "text/css"
        default: return "application/octet-stream"
        }
    }
}
