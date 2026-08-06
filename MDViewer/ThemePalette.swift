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

struct ThemePalette: Identifiable, Equatable {
    let id: String
    let name: String
    let category: ThemeCategory
    let colors: ThemeColors
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
            )
        )
    }
}
