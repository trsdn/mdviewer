import Foundation

/// Build editions MDViewer ships. Both editions are produced from this single
/// source tree; only capability selection differs.
enum AppEdition: String, CaseIterable, Sendable {
    case lite
    case full

    var displayName: String {
        switch self {
        case .lite: return "Lite"
        case .full: return "Full"
        }
    }

    var productDisplayName: String {
        "MDViewer \(displayName)"
    }
}

/// Typed capability model. Every edition-dependent behaviour reads from here so
/// no feature has to test the compile condition directly.
struct EditionCapabilities: Equatable, Sendable {
    /// Which edition this build is.
    let edition: AppEdition
    /// Lite ships a small custom Prism build inlined into the render page.
    let bundlesPrismHighlighter: Bool
    /// Full lazily imports highlight.js for broad language coverage.
    let lazyBroadHighlighter: Bool
    /// Full lazily imports js-yaml to build frontmatter metadata cards.
    let lazyFrontmatterCards: Bool
    /// Full lazily imports Mermaid plus svg-pan-zoom for offline diagrams.
    let lazyDiagrams: Bool

    /// True when the render page may import bundled ES modules through the
    /// allowlisted `mdviewer-resource:` module path.
    var usesBundledWebModules: Bool {
        lazyBroadHighlighter || lazyFrontmatterCards || lazyDiagrams
    }

    static let lite = EditionCapabilities(
        edition: .lite,
        bundlesPrismHighlighter: true,
        lazyBroadHighlighter: false,
        lazyFrontmatterCards: false,
        lazyDiagrams: false
    )

    static let full = EditionCapabilities(
        edition: .full,
        bundlesPrismHighlighter: false,
        lazyBroadHighlighter: true,
        lazyFrontmatterCards: true,
        lazyDiagrams: true
    )

    #if MDVIEWER_FULL
    static let current = EditionCapabilities.full
    #else
    static let current = EditionCapabilities.lite
    #endif
}

enum AppVersion {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.0.0"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "0"
    }

    /// Edition recorded in Info.plist at build time. Falls back to the compiled
    /// capability model when the key is absent (for example in unit tests that
    /// load a test bundle).
    static var edition: AppEdition {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MDViewerEdition")
                as? String,
              let edition = AppEdition(rawValue: raw.lowercased()) else {
            return EditionCapabilities.current.edition
        }
        return edition
    }

    /// Short line shown in About and Settings, for example
    /// `MDViewer Full 2.0.0 (7)`.
    static var summary: String {
        "\(edition.productDisplayName) \(marketingVersion) (\(buildVersion))"
    }
}
