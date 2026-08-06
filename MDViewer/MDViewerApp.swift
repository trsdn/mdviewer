import SwiftUI

@main
struct MDViewerApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: String = AppearanceMode.system.rawValue
    @AppStorage("lightThemeID") private var lightThemeID: String = ThemeRegistry.defaultLightThemeID
    @AppStorage("darkThemeID") private var darkThemeID: String = ThemeRegistry.defaultDarkThemeID

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ResolvedThemeDocumentView(
                document: file.document,
                fileURL: file.fileURL,
                appearanceMode: AppearanceMode(rawValue: appearanceMode) ?? .system,
                lightThemeID: lightThemeID,
                darkThemeID: darkThemeID
            )
        }
        .commands {
            DocumentCommands()

            CommandGroup(after: .toolbar) {
                Divider()
                Menu("Appearance") {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Button {
                            appearanceMode = mode.rawValue
                        } label: {
                            if appearanceMode == mode.rawValue {
                                Text("\(mode.label)")
                            } else {
                                Text(mode.label)
                            }
                        }
                        .keyboardShortcut(shortcut(for: mode))
                    }
                }
            }
        }

        Settings {
            ThemeSettingsView(
                appearanceMode: $appearanceMode,
                lightThemeID: $lightThemeID,
                darkThemeID: $darkThemeID
            )
        }
    }

    private struct ResolvedThemeDocumentView: View {
        @Environment(\.colorScheme) private var colorScheme

        let document: MarkdownDocument
        let fileURL: URL?
        let appearanceMode: AppearanceMode
        let lightThemeID: String
        let darkThemeID: String

        var body: some View {
            ContentView(
                document: document,
                fileURL: fileURL,
                palette: ThemeRegistry.resolve(
                    mode: appearanceMode,
                    systemColorScheme: colorScheme,
                    lightThemeID: lightThemeID,
                    darkThemeID: darkThemeID
                )
            )
        }
    }

    private func shortcut(for mode: AppearanceMode) -> KeyboardShortcut {
        switch mode {
        case .system: return KeyboardShortcut("0", modifiers: [.command, .shift])
        case .light: return KeyboardShortcut("1", modifiers: [.command, .shift])
        case .dark: return KeyboardShortcut("2", modifiers: [.command, .shift])
        }
    }
}
