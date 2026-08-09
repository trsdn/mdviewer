import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        rawValue.capitalized
    }
}

enum ThemeCategory: String {
    case light
    case dark
}

enum ThemeColorToken: String, CaseIterable {
    case background
    case foreground
    case border
    case codeBackground
    case codeForeground
    case link
    case blockquoteForeground
    case blockquoteBorder
    case horizontalRule
    case selectionBackground
    case selectionForeground
    case caret
    case activeLine
    case gutterBackground
    case gutterForeground
    case splitter
    case splitterHover
    case searchMatch
    case searchMatchSelected
}

struct ThemeColorValue: Equatable {
    let hex: String

    init(_ hex: String) {
        precondition(
            hex.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil,
            "Theme colors must be six-digit hexadecimal values."
        )
        self.hex = hex.lowercased()
    }

    var nsColor: NSColor {
        let value = UInt64(hex.dropFirst(), radix: 16)!
        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }
}

struct ThemeColors: Equatable {
    let background: ThemeColorValue
    let foreground: ThemeColorValue
    let border: ThemeColorValue
    let codeBackground: ThemeColorValue
    let codeForeground: ThemeColorValue
    let link: ThemeColorValue
    let blockquoteForeground: ThemeColorValue
    let blockquoteBorder: ThemeColorValue
    let horizontalRule: ThemeColorValue
    let selectionBackground: ThemeColorValue
    let selectionForeground: ThemeColorValue
    let caret: ThemeColorValue
    let activeLine: ThemeColorValue
    let gutterBackground: ThemeColorValue
    let gutterForeground: ThemeColorValue
    let splitter: ThemeColorValue
    let splitterHover: ThemeColorValue
    let searchMatch: ThemeColorValue
    let searchMatchSelected: ThemeColorValue

    subscript(token: ThemeColorToken) -> ThemeColorValue {
        switch token {
        case .background: return background
        case .foreground: return foreground
        case .border: return border
        case .codeBackground: return codeBackground
        case .codeForeground: return codeForeground
        case .link: return link
        case .blockquoteForeground: return blockquoteForeground
        case .blockquoteBorder: return blockquoteBorder
        case .horizontalRule: return horizontalRule
        case .selectionBackground: return selectionBackground
        case .selectionForeground: return selectionForeground
        case .caret: return caret
        case .activeLine: return activeLine
        case .gutterBackground: return gutterBackground
        case .gutterForeground: return gutterForeground
        case .splitter: return splitter
        case .splitterHover: return splitterHover
        case .searchMatch: return searchMatch
        case .searchMatchSelected: return searchMatchSelected
        }
    }

    var webArguments: [String: String] {
        Dictionary(
            uniqueKeysWithValues: ThemeColorToken.allCases.map {
                ($0.rawValue, self[$0].hex)
            }
        )
    }
}

/// Semantic tokens shared by both editions' highlighters and by GitHub alerts.
///
/// Lite renders through the custom Prism build and Full renders through
/// highlight.js, but both map onto exactly these variables so highlighted code
/// and alerts look the same in every palette and in print.
enum ThemeSyntaxToken: String, CaseIterable {
    case keyword
    case string
    case number
    case comment
    case function
    case type
    case variable
    case punctuation
    case alertNote
    case alertTip
    case alertImportant
    case alertWarning
    case alertCaution
}

struct ThemeSyntaxColors: Equatable {
    private let values: [ThemeSyntaxToken: ThemeColorValue]

    init(_ values: [ThemeSyntaxToken: String]) {
        precondition(
            Set(values.keys) == Set(ThemeSyntaxToken.allCases),
            "Every palette must define every syntax token."
        )
        self.values = values.mapValues(ThemeColorValue.init)
    }

    subscript(token: ThemeSyntaxToken) -> ThemeColorValue {
        values[token]!
    }

    var webArguments: [String: String] {
        Dictionary(
            uniqueKeysWithValues: ThemeSyntaxToken.allCases.map {
                ($0.rawValue, self[$0].hex)
            }
        )
    }
}

struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let category: ThemeCategory
    let colors: ThemeColors
    let syntax: ThemeSyntaxColors

    /// Payload handed to the render page's `applyTheme`.
    var webArguments: [String: Any] {
        [
            "id": id,
            "category": category.rawValue,
            "colors": colors.webArguments,
            "syntax": syntax.webArguments
        ]
    }
}

enum ThemeRegistry {
    static let defaultLightThemeID = "github-light"
    static let defaultDarkThemeID = "github-dark"

    static let all: [ThemePalette] = [
        palette(
            "github-light", "GitHub Light", .light,
            [.background: "#ffffff", .foreground: "#24292f", .border: "#d0d7de",
             .codeBackground: "#f6f8fa", .codeForeground: "#24292f", .link: "#0969da",
             .blockquoteForeground: "#656d76", .blockquoteBorder: "#d0d7de",
             .horizontalRule: "#d8dee4", .selectionBackground: "#b6d7ff",
             .selectionForeground: "#24292f", .caret: "#24292f", .activeLine: "#f6f8fa",
             .gutterBackground: "#ffffff", .gutterForeground: "#656d76",
             .splitter: "#d0d7de", .splitterHover: "#0969da",
             .searchMatch: "#fff8c5", .searchMatchSelected: "#b6d7ff"]
        ),
        palette(
            "solarized-light", "Solarized Light", .light,
            [.background: "#fdf6e3", .foreground: "#586e75", .border: "#93a1a1",
             .codeBackground: "#eee8d5", .codeForeground: "#566c73", .link: "#006da8",
             .blockquoteForeground: "#586e75", .blockquoteBorder: "#93a1a1",
             .horizontalRule: "#93a1a1", .selectionBackground: "#d9e2cc",
             .selectionForeground: "#3f555d", .caret: "#586e75", .activeLine: "#eee8d5",
             .gutterBackground: "#fdf6e3", .gutterForeground: "#586e75",
             .splitter: "#93a1a1", .splitterHover: "#006da8",
             .searchMatch: "#e8d7a4", .searchMatchSelected: "#b8d7e8"]
        ),
        palette(
            "sepia", "Sepia", .light,
            [.background: "#f4ecd8", .foreground: "#3e3629", .border: "#d4c4a8",
             .codeBackground: "#e8dcc0", .codeForeground: "#3e3629", .link: "#765200",
             .blockquoteForeground: "#6b5d4f", .blockquoteBorder: "#d4c4a8",
             .horizontalRule: "#cbbfa3", .selectionBackground: "#d9c59e",
             .selectionForeground: "#2f281e", .caret: "#3e3629", .activeLine: "#eee3c9",
             .gutterBackground: "#f4ecd8", .gutterForeground: "#6b5d4f",
             .splitter: "#d4c4a8", .splitterHover: "#765200",
             .searchMatch: "#ead38f", .searchMatchSelected: "#d9c59e"]
        ),
        palette(
            "github-dark", "GitHub Dark", .dark,
            [.background: "#0d1117", .foreground: "#e6edf3", .border: "#30363d",
             .codeBackground: "#161b22", .codeForeground: "#e6edf3", .link: "#58a6ff",
             .blockquoteForeground: "#8b949e", .blockquoteBorder: "#30363d",
             .horizontalRule: "#21262d", .selectionBackground: "#264f78",
             .selectionForeground: "#ffffff", .caret: "#e6edf3", .activeLine: "#161b22",
             .gutterBackground: "#0d1117", .gutterForeground: "#8b949e",
             .splitter: "#30363d", .splitterHover: "#58a6ff",
             .searchMatch: "#4d3e00", .searchMatchSelected: "#264f78"]
        ),
        palette(
            "solarized-dark", "Solarized Dark", .dark,
            [.background: "#002b36", .foreground: "#839496", .border: "#073642",
             .codeBackground: "#073642", .codeForeground: "#93a1a1", .link: "#3aaed8",
             .blockquoteForeground: "#839496", .blockquoteBorder: "#073642",
             .horizontalRule: "#073642", .selectionBackground: "#075b70",
             .selectionForeground: "#eee8d5", .caret: "#93a1a1", .activeLine: "#073642",
             .gutterBackground: "#002b36", .gutterForeground: "#839496",
             .splitter: "#073642", .splitterHover: "#3aaed8",
             .searchMatch: "#5b4b00", .searchMatchSelected: "#075b70"]
        ),
        palette(
            "dracula", "Dracula", .dark,
            [.background: "#282a36", .foreground: "#f8f8f2", .border: "#44475a",
             .codeBackground: "#44475a", .codeForeground: "#f8f8f2", .link: "#bd93f9",
             .blockquoteForeground: "#a8adc0", .blockquoteBorder: "#44475a",
             .horizontalRule: "#44475a", .selectionBackground: "#44475a",
             .selectionForeground: "#f8f8f2", .caret: "#f8f8f2", .activeLine: "#343746",
             .gutterBackground: "#282a36", .gutterForeground: "#a8adc0",
             .splitter: "#44475a", .splitterHover: "#ff79c6",
             .searchMatch: "#6d5a00", .searchMatchSelected: "#44475a"]
        ),
        palette(
            "monokai", "Monokai", .dark,
            [.background: "#272822", .foreground: "#f8f8f2", .border: "#49483e",
             .codeBackground: "#3e3d32", .codeForeground: "#f8f8f2", .link: "#66d9ef",
             .blockquoteForeground: "#a8a590", .blockquoteBorder: "#49483e",
             .horizontalRule: "#49483e", .selectionBackground: "#49483e",
             .selectionForeground: "#f8f8f2", .caret: "#f8f8f2", .activeLine: "#3e3d32",
             .gutterBackground: "#272822", .gutterForeground: "#a8a590",
             .splitter: "#49483e", .splitterHover: "#a6e22e",
             .searchMatch: "#756e00", .searchMatchSelected: "#49483e"]
        ),
        palette(
            "nord", "Nord", .dark,
            [.background: "#2e3440", .foreground: "#eceff4", .border: "#4c566a",
             .codeBackground: "#3b4252", .codeForeground: "#e5e9f0", .link: "#88c0d0",
             .blockquoteForeground: "#d8dee9", .blockquoteBorder: "#4c566a",
             .horizontalRule: "#4c566a", .selectionBackground: "#434c5e",
             .selectionForeground: "#eceff4", .caret: "#eceff4", .activeLine: "#3b4252",
             .gutterBackground: "#2e3440", .gutterForeground: "#81a1c1",
             .splitter: "#4c566a", .splitterHover: "#88c0d0",
             .searchMatch: "#5e5a2f", .searchMatchSelected: "#434c5e"]
        )
    ]

    static let lightThemes = all.filter { $0.category == .light }
    static let darkThemes = all.filter { $0.category == .dark }

    static func theme(id: String, category: ThemeCategory) -> ThemePalette {
        all.first { $0.id == id && $0.category == category }
            ?? defaultTheme(for: category)
    }

    static func validID(_ id: String, category: ThemeCategory) -> String {
        theme(id: id, category: category).id
    }

    static func resolve(
        mode: AppearanceMode,
        systemColorScheme: ColorScheme,
        lightThemeID: String,
        darkThemeID: String
    ) -> ThemePalette {
        let category: ThemeCategory
        switch mode {
        case .system:
            category = systemColorScheme == .dark ? .dark : .light
        case .light:
            category = .light
        case .dark:
            category = .dark
        }
        return theme(
            id: category == .light ? lightThemeID : darkThemeID,
            category: category
        )
    }

    private static func defaultTheme(for category: ThemeCategory) -> ThemePalette {
        let id = category == .light ? defaultLightThemeID : defaultDarkThemeID
        return all.first { $0.id == id }!
    }

    private static func palette(
        _ id: String,
        _ name: String,
        _ category: ThemeCategory,
        _ values: [ThemeColorToken: String]
    ) -> ThemePalette {
        precondition(Set(values.keys) == Set(ThemeColorToken.allCases))
        func color(_ token: ThemeColorToken) -> ThemeColorValue {
            ThemeColorValue(values[token]!)
        }
        return ThemePalette(
            id: id,
            name: name,
            category: category,
            colors: ThemeColors(
                background: color(.background),
                foreground: color(.foreground),
                border: color(.border),
                codeBackground: color(.codeBackground),
                codeForeground: color(.codeForeground),
                link: color(.link),
                blockquoteForeground: color(.blockquoteForeground),
                blockquoteBorder: color(.blockquoteBorder),
                horizontalRule: color(.horizontalRule),
                selectionBackground: color(.selectionBackground),
                selectionForeground: color(.selectionForeground),
                caret: color(.caret),
                activeLine: color(.activeLine),
                gutterBackground: color(.gutterBackground),
                gutterForeground: color(.gutterForeground),
                splitter: color(.splitter),
                splitterHover: color(.splitterHover),
                searchMatch: color(.searchMatch),
                searchMatchSelected: color(.searchMatchSelected)
            ),
            syntax: ThemeSyntaxColors(syntaxValues[id]!)
        )
    }

    /// Curated, accessibility-checked syntax and alert accents per palette.
    /// Values are chosen to stay legible against each palette's code
    /// background in light, dark and printed output.
    private static let syntaxValues: [String: [ThemeSyntaxToken: String]] = [
        "github-light": [
            .keyword: "#cf222e", .string: "#0a3069", .number: "#0550ae",
            .comment: "#6e7781", .function: "#8250df", .type: "#953800",
            .variable: "#24292f", .punctuation: "#57606a",
            .alertNote: "#0969da", .alertTip: "#1a7f37", .alertImportant: "#8250df",
            .alertWarning: "#9a6700", .alertCaution: "#cf222e"
        ],
        "solarized-light": [
            .keyword: "#859900", .string: "#2aa198", .number: "#d33682",
            .comment: "#93a1a1", .function: "#268bd2", .type: "#b58900",
            .variable: "#586e75", .punctuation: "#657b83",
            .alertNote: "#268bd2", .alertTip: "#859900", .alertImportant: "#6c71c4",
            .alertWarning: "#b58900", .alertCaution: "#dc322f"
        ],
        "sepia": [
            .keyword: "#8a3324", .string: "#4a6b3a", .number: "#7a5200",
            .comment: "#8a7b64", .function: "#5b4a8a", .type: "#7a4b12",
            .variable: "#3e3629", .punctuation: "#6b5d4f",
            .alertNote: "#2f5f8a", .alertTip: "#3f6b34", .alertImportant: "#5b4a8a",
            .alertWarning: "#8a6100", .alertCaution: "#8a3324"
        ],
        "github-dark": [
            .keyword: "#ff7b72", .string: "#a5d6ff", .number: "#79c0ff",
            .comment: "#8b949e", .function: "#d2a8ff", .type: "#ffa657",
            .variable: "#e6edf3", .punctuation: "#c9d1d9",
            .alertNote: "#58a6ff", .alertTip: "#3fb950", .alertImportant: "#a371f7",
            .alertWarning: "#d29922", .alertCaution: "#f85149"
        ],
        "solarized-dark": [
            .keyword: "#859900", .string: "#2aa198", .number: "#d33682",
            .comment: "#657b83", .function: "#268bd2", .type: "#b58900",
            .variable: "#93a1a1", .punctuation: "#839496",
            .alertNote: "#268bd2", .alertTip: "#859900", .alertImportant: "#6c71c4",
            .alertWarning: "#b58900", .alertCaution: "#dc322f"
        ],
        "dracula": [
            .keyword: "#ff79c6", .string: "#f1fa8c", .number: "#bd93f9",
            .comment: "#8f96b3", .function: "#50fa7b", .type: "#8be9fd",
            .variable: "#f8f8f2", .punctuation: "#e2e2dc",
            .alertNote: "#8be9fd", .alertTip: "#50fa7b", .alertImportant: "#bd93f9",
            .alertWarning: "#ffb86c", .alertCaution: "#ff5555"
        ],
        "monokai": [
            .keyword: "#f92672", .string: "#e6db74", .number: "#ae81ff",
            .comment: "#9d9a86", .function: "#a6e22e", .type: "#66d9ef",
            .variable: "#f8f8f2", .punctuation: "#e4e4de",
            .alertNote: "#66d9ef", .alertTip: "#a6e22e", .alertImportant: "#ae81ff",
            .alertWarning: "#fd971f", .alertCaution: "#f92672"
        ],
        "nord": [
            .keyword: "#81a1c1", .string: "#a3be8c", .number: "#b48ead",
            .comment: "#9aa5b5", .function: "#88c0d0", .type: "#8fbcbb",
            .variable: "#eceff4", .punctuation: "#d8dee9",
            .alertNote: "#88c0d0", .alertTip: "#a3be8c", .alertImportant: "#b48ead",
            .alertWarning: "#ebcb8b", .alertCaution: "#bf616a"
        ]
    ]
}
