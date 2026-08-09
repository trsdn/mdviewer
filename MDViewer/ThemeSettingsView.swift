import SwiftUI

struct ThemeSettingsView: View {
    @Binding var appearanceMode: String
    @Binding var lightThemeID: String
    @Binding var darkThemeID: String

    var body: some View {
        Form {
            Section {
                LabeledContent("Edition", value: AppVersion.edition.displayName)
                LabeledContent("Version", value: AppVersion.marketingVersion)
                LabeledContent("Build", value: AppVersion.buildVersion)
            } header: {
                Text(AppVersion.summary)
            }

            Picker("Appearance", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearanceModePicker")

            themePicker(
                title: "Light theme",
                themes: ThemeRegistry.lightThemes,
                selection: lightThemeBinding,
                identifier: "lightThemePicker"
            )

            themePicker(
                title: "Dark theme",
                themes: ThemeRegistry.darkThemes,
                selection: darkThemeBinding,
                identifier: "darkThemePicker"
            )
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceMode)?.rawValue ?? AppearanceMode.system.rawValue },
            set: { appearanceMode = $0 }
        )
    }

    private var lightThemeBinding: Binding<String> {
        Binding(
            get: { ThemeRegistry.validID(lightThemeID, category: .light) },
            set: { lightThemeID = $0 }
        )
    }

    private var darkThemeBinding: Binding<String> {
        Binding(
            get: { ThemeRegistry.validID(darkThemeID, category: .dark) },
            set: { darkThemeID = $0 }
        )
    }

    private func themePicker(
        title: String,
        themes: [ThemePalette],
        selection: Binding<String>,
        identifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(themes) { theme in
                HStack(spacing: 8) {
                    ThemeSwatch(theme: theme)
                    Text(theme.name)
                }
                .tag(theme.id)
            }
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct ThemeSwatch: View {
    let theme: ThemePalette

    var body: some View {
        HStack(spacing: 2) {
            swatch(theme.colors.background)
            swatch(theme.colors.foreground)
            swatch(theme.colors.link)
            swatch(theme.colors.codeBackground)
        }
        .accessibilityHidden(true)
    }

    private func swatch(_ color: ThemeColorValue) -> some View {
        Circle()
            .fill(color.swiftUIColor)
            .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
            .frame(width: 10, height: 10)
    }
}
