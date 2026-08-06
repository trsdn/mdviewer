import SwiftUI
import XCTest
@testable import MDViewer

final class ThemePaletteTests: XCTestCase {
    func testRegistryExactlyMatchesSharedContract() {
        let expected: [(String, String, ThemeCategory, [String])] = [
            ("github-light", "GitHub Light", .light,
             ["#ffffff", "#24292f", "#d0d7de", "#f6f8fa", "#24292f",
              "#0969da", "#656d76", "#d0d7de", "#d8dee4", "#b6d7ff",
              "#24292f", "#24292f", "#f6f8fa", "#ffffff", "#656d76",
              "#d0d7de", "#0969da", "#fff8c5", "#b6d7ff"]),
            ("solarized-light", "Solarized Light", .light,
             ["#fdf6e3", "#586e75", "#93a1a1", "#eee8d5", "#566c73",
              "#006da8", "#586e75", "#93a1a1", "#93a1a1", "#d9e2cc",
              "#3f555d", "#586e75", "#eee8d5", "#fdf6e3", "#586e75",
              "#93a1a1", "#006da8", "#e8d7a4", "#b8d7e8"]),
            ("sepia", "Sepia", .light,
             ["#f4ecd8", "#3e3629", "#d4c4a8", "#e8dcc0", "#3e3629",
              "#765200", "#6b5d4f", "#d4c4a8", "#cbbfa3", "#d9c59e",
              "#2f281e", "#3e3629", "#eee3c9", "#f4ecd8", "#6b5d4f",
              "#d4c4a8", "#765200", "#ead38f", "#d9c59e"]),
            ("github-dark", "GitHub Dark", .dark,
             ["#0d1117", "#e6edf3", "#30363d", "#161b22", "#e6edf3",
              "#58a6ff", "#8b949e", "#30363d", "#21262d", "#264f78",
              "#ffffff", "#e6edf3", "#161b22", "#0d1117", "#8b949e",
              "#30363d", "#58a6ff", "#4d3e00", "#264f78"]),
            ("solarized-dark", "Solarized Dark", .dark,
             ["#002b36", "#839496", "#073642", "#073642", "#93a1a1",
              "#3aaed8", "#839496", "#073642", "#073642", "#075b70",
              "#eee8d5", "#93a1a1", "#073642", "#002b36", "#839496",
              "#073642", "#3aaed8", "#5b4b00", "#075b70"]),
            ("dracula", "Dracula", .dark,
             ["#282a36", "#f8f8f2", "#44475a", "#44475a", "#f8f8f2",
              "#bd93f9", "#a8adc0", "#44475a", "#44475a", "#44475a",
              "#f8f8f2", "#f8f8f2", "#343746", "#282a36", "#a8adc0",
              "#44475a", "#ff79c6", "#6d5a00", "#44475a"]),
            ("monokai", "Monokai", .dark,
             ["#272822", "#f8f8f2", "#49483e", "#3e3d32", "#f8f8f2",
              "#66d9ef", "#a8a590", "#49483e", "#49483e", "#49483e",
              "#f8f8f2", "#f8f8f2", "#3e3d32", "#272822", "#a8a590",
              "#49483e", "#a6e22e", "#756e00", "#49483e"]),
            ("nord", "Nord", .dark,
             ["#2e3440", "#eceff4", "#4c566a", "#3b4252", "#e5e9f0",
              "#88c0d0", "#d8dee9", "#4c566a", "#4c566a", "#434c5e",
              "#eceff4", "#eceff4", "#3b4252", "#2e3440", "#81a1c1",
              "#4c566a", "#88c0d0", "#5e5a2f", "#434c5e"])
        ]

        XCTAssertEqual(ThemeColorToken.allCases.map(\.rawValue), [
            "background", "foreground", "border", "codeBackground",
            "codeForeground", "link", "blockquoteForeground",
            "blockquoteBorder", "horizontalRule", "selectionBackground",
            "selectionForeground", "caret", "activeLine", "gutterBackground",
            "gutterForeground", "splitter", "splitterHover", "searchMatch",
            "searchMatchSelected"
        ])
        XCTAssertEqual(ThemeRegistry.all.count, expected.count)

        for (theme, expectedTheme) in zip(ThemeRegistry.all, expected) {
            XCTAssertEqual(theme.id, expectedTheme.0)
            XCTAssertEqual(theme.name, expectedTheme.1)
            XCTAssertEqual(theme.category, expectedTheme.2)
            XCTAssertEqual(
                ThemeColorToken.allCases.map { theme.colors[$0].hex },
                expectedTheme.3,
                theme.id
            )
        }
    }

    func testCategoryFilteringAndPersistenceRawValues() {
        XCTAssertEqual(AppearanceMode.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(
            ThemeRegistry.lightThemes.map(\.id),
            ["github-light", "solarized-light", "sepia"]
        )
        XCTAssertEqual(
            ThemeRegistry.darkThemes.map(\.id),
            ["github-dark", "solarized-dark", "dracula", "monokai", "nord"]
        )
        XCTAssertTrue(ThemeRegistry.lightThemes.allSatisfy { $0.category == .light })
        XCTAssertTrue(ThemeRegistry.darkThemes.allSatisfy { $0.category == .dark })
    }

    func testInvalidAndWrongCategoryIDsFallBackWithoutChangingInput() {
        let suiteName = "ThemePreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("old-custom-theme", forKey: "lightThemeID")
        let obsoleteID = defaults.string(forKey: "lightThemeID")!

        XCTAssertEqual(
            ThemeRegistry.theme(id: obsoleteID, category: .light).id,
            ThemeRegistry.defaultLightThemeID
        )
        XCTAssertEqual(
            ThemeRegistry.theme(id: "sepia", category: .dark).id,
            ThemeRegistry.defaultDarkThemeID
        )
        XCTAssertEqual(defaults.string(forKey: "lightThemeID"), "old-custom-theme")
    }

    func testModeResolutionUsesSelectedPalettesAndSystemColorScheme() {
        XCTAssertEqual(
            resolve(.system, .light).id,
            "sepia"
        )
        XCTAssertEqual(
            resolve(.system, .dark).id,
            "nord"
        )
        XCTAssertEqual(
            resolve(.light, .dark).id,
            "sepia"
        )
        XCTAssertEqual(
            resolve(.dark, .light).id,
            "nord"
        )
    }

    func testThemeApplicationStateReconcilesRapidAtoBtoA() throws {
        let themeA = ThemeRegistry.theme(id: "github-light", category: .light)
        let themeB = ThemeRegistry.theme(id: "sepia", category: .light)
        var state = ThemeApplicationState(desiredPalette: themeA)

        let initialA = try XCTUnwrap(state.beginNextApplication())
        XCTAssertNil(state.appliedPalette)
        XCTAssertEqual(state.inFlightRequest, initialA)
        XCTAssertTrue(state.complete(requestID: initialA.id, succeeded: true))
        XCTAssertEqual(state.appliedPalette, themeA)

        state.setDesiredPalette(themeB)
        let requestB = try XCTUnwrap(state.beginNextApplication())
        state.setDesiredPalette(themeA)
        XCTAssertNil(state.beginNextApplication(), "B must remain the sole in-flight request")
        XCTAssertEqual(state.appliedPalette, themeA, "requesting B must not mark it applied")

        XCTAssertTrue(state.complete(requestID: requestB.id, succeeded: true))
        XCTAssertEqual(state.appliedPalette, themeB)
        let finalA = try XCTUnwrap(state.beginNextApplication())
        XCTAssertEqual(finalA.palette, themeA)
        XCTAssertTrue(state.complete(requestID: finalA.id, succeeded: true))
        XCTAssertEqual(state.appliedPalette, themeA)
        XCTAssertNil(state.inFlightRequest)
    }

    func testThemeApplicationFailureKeepsAppliedPaletteAndAllowsRetry() throws {
        let themeA = ThemeRegistry.theme(id: "github-light", category: .light)
        let themeB = ThemeRegistry.theme(id: "sepia", category: .light)
        var state = ThemeApplicationState(desiredPalette: themeA)

        let requestA = try XCTUnwrap(state.beginNextApplication())
        XCTAssertTrue(state.complete(requestID: requestA.id, succeeded: true))
        state.setDesiredPalette(themeB)

        let failedB = try XCTUnwrap(state.beginNextApplication())
        XCTAssertEqual(state.appliedPalette, themeA)
        XCTAssertTrue(state.complete(requestID: failedB.id, succeeded: false))
        XCTAssertEqual(state.appliedPalette, themeA)
        XCTAssertNil(state.inFlightRequest)

        let retryB = try XCTUnwrap(state.beginNextApplication())
        XCTAssertEqual(retryB.palette, themeB)
        XCTAssertNotEqual(retryB.id, failedB.id)
        XCTAssertFalse(
            state.complete(requestID: failedB.id, succeeded: true),
            "a stale completion must not mark a palette applied"
        )
        XCTAssertEqual(state.appliedPalette, themeA)
        XCTAssertTrue(state.complete(requestID: retryB.id, succeeded: true))
        XCTAssertEqual(state.appliedPalette, themeB)
    }

    func testTextColorsMeetWCAGAAContrast() {
        let pairs: [(String, (ThemeColors) -> ThemeColorValue, (ThemeColors) -> ThemeColorValue)] = [
            ("foreground", { $0.foreground }, { $0.background }),
            ("link", { $0.link }, { $0.background }),
            ("blockquote/muted", { $0.blockquoteForeground }, { $0.background }),
            ("code", { $0.codeForeground }, { $0.codeBackground }),
            ("gutter", { $0.gutterForeground }, { $0.gutterBackground }),
            ("selection", { $0.selectionForeground }, { $0.selectionBackground }),
            ("search match", { $0.selectionForeground }, { $0.searchMatch }),
            ("selected search match", { $0.selectionForeground }, { $0.searchMatchSelected })
        ]

        for theme in ThemeRegistry.all {
            for (label, foreground, background) in pairs {
                let ratio = contrastRatio(
                    foreground(theme.colors).hex,
                    background(theme.colors).hex
                )
                XCTAssertGreaterThanOrEqual(
                    ratio,
                    4.5,
                    "\(theme.id) \(label) contrast is \(ratio):1"
                )
            }
        }
    }

    private func resolve(_ mode: AppearanceMode, _ colorScheme: ColorScheme) -> ThemePalette {
        ThemeRegistry.resolve(
            mode: mode,
            systemColorScheme: colorScheme,
            lightThemeID: "sepia",
            darkThemeID: "nord"
        )
    }

    private func contrastRatio(_ first: String, _ second: String) -> Double {
        let luminances = [first, second].map(relativeLuminance).sorted(by: >)
        return (luminances[0] + 0.05) / (luminances[1] + 0.05)
    }

    private func relativeLuminance(_ hex: String) -> Double {
        let value = UInt64(hex.dropFirst(), radix: 16)!
        let components = [
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255
        ]
        let linear = components.map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
