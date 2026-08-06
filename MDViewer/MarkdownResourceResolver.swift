import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MarkdownResourceError: LocalizedError, Equatable {
    case invalidScheme
    case invalidHost
    case invalidPath
    case traversal
    case outsideAuthorizedRoot
    case unavailableRoot
    case resourceUnavailable
    case unsupportedType
    case invalidImageData
    case resourceTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "The resource URL uses an unsupported scheme."
        case .invalidHost:
            return "The resource URL has an invalid host."
        case .invalidPath:
            return "The resource URL has an invalid path."
        case .traversal:
            return "The resource path attempts to leave the authorized folder."
        case .outsideAuthorizedRoot:
            return "The resource resolves outside the authorized folder."
        case .unavailableRoot:
            return "The document folder has not been authorized."
        case .resourceUnavailable:
            return "The local image is missing or is not a regular file."
        case .unsupportedType:
            return "The local image type is not supported."
        case .invalidImageData:
            return "The local image contents do not match its supported image type."
        case .resourceTooLarge:
            return "The local image exceeds the safe size limit."
        }
    }
}

struct ResolvedMarkdownImage {
    let fileURL: URL
    let mimeType: String
    let fileSize: Int
}

struct MarkdownResourceResolver {
    static let scheme = "mdviewer-resource"
    static let host = "document"
    static let baseURL = URL(string: "\(scheme)://\(host)/")!
    static let maximumImageBytes = 50 * 1024 * 1024
    static let maximumImagePixels = 100_000_000

    private static let supportedTypes: [String: (type: UTType, mime: String)] = [
        "png": (.png, "image/png"),
        "jpg": (.jpeg, "image/jpeg"),
        "jpeg": (.jpeg, "image/jpeg"),
        "gif": (.gif, "image/gif"),
        "webp": (.webP, "image/webp")
    ]

    static func resolve(_ resourceURL: URL, under authorizedRoot: URL?) throws -> URL {
        guard resourceURL.scheme?.lowercased() == scheme else {
            throw MarkdownResourceError.invalidScheme
        }
        guard resourceURL.host?.lowercased() == host else {
            throw MarkdownResourceError.invalidHost
        }
        guard resourceURL.user == nil,
              resourceURL.password == nil,
              resourceURL.port == nil,
              resourceURL.query == nil,
              resourceURL.fragment == nil else {
            throw MarkdownResourceError.invalidPath
        }
        guard let authorizedRoot else {
            throw MarkdownResourceError.unavailableRoot
        }

        guard let encodedPath = URLComponents(
            url: resourceURL,
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath,
              let decodedPath = encodedPath.removingPercentEncoding,
              !decodedPath.contains("\0"),
              !decodedPath.contains("\\") else {
            throw MarkdownResourceError.invalidPath
        }

        let components = decodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty else {
            throw MarkdownResourceError.invalidPath
        }
        guard !components.contains("..") else {
            throw MarkdownResourceError.traversal
        }

        let canonicalRoot = authorizedRoot.standardizedFileURL.resolvingSymlinksInPath()
        var target = canonicalRoot
        for component in components where component != "." {
            target.appendPathComponent(component)
        }
        let canonicalTarget = target.standardizedFileURL.resolvingSymlinksInPath()

        let rootComponents = canonicalRoot.pathComponents
        let targetComponents = canonicalTarget.pathComponents
        guard targetComponents.count > rootComponents.count,
              Array(targetComponents.prefix(rootComponents.count)) == rootComponents else {
            throw MarkdownResourceError.outsideAuthorizedRoot
        }

        return canonicalTarget
    }

    static func resolveImage(
        _ resourceURL: URL,
        under authorizedRoot: URL?
    ) throws -> ResolvedMarkdownImage {
        let fileURL = try resolve(resourceURL, under: authorizedRoot)
        guard let supported = supportedTypes[fileURL.pathExtension.lowercased()] else {
            throw MarkdownResourceError.unsupportedType
        }

        guard let values = try? fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ]),
              values.isRegularFile == true,
              let fileSize = values.fileSize else {
            throw MarkdownResourceError.resourceUnavailable
        }
        guard fileSize <= maximumImageBytes else {
            throw MarkdownResourceError.resourceTooLarge
        }

        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let identifier = CGImageSourceGetType(source),
              let detectedType = UTType(identifier as String),
              detectedType.conforms(to: supported.type)
                || supported.type.conforms(to: detectedType) else {
            throw MarkdownResourceError.invalidImageData
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0,
              height.intValue > 0,
              width.int64Value <= Int64(maximumImagePixels) / height.int64Value else {
            throw MarkdownResourceError.resourceTooLarge
        }

        return ResolvedMarkdownImage(
            fileURL: fileURL,
            mimeType: supported.mime,
            fileSize: fileSize
        )
    }
}
