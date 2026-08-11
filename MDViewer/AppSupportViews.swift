import AppKit
import SwiftUI

enum AppWindow {
    static let about = "about"
    static let help = "help"
}

struct SupportCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MDViewer") {
                openWindow(id: AppWindow.about)
            }
        }

        CommandGroup(replacing: .help) {
            Button("MDViewer Help") {
                openWindow(id: AppWindow.help)
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("MDViewer Website") {
                NSWorkspace.shared.open(AppInformation.websiteURL)
            }

            Button("Report an Issue…") {
                NSWorkspace.shared.open(AppInformation.issueURL)
            }
        }
    }
}

struct AboutMDViewerView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .accessibilityHidden(true)

            Text("MDViewer")
                .font(.title.bold())

            Text(AppVersion.summary)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text(AppInformation.copyright)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Link("Project Website", destination: AppInformation.websiteURL)
                Link("GitHub", destination: AppInformation.sourceURL)
                Link("Report an Issue", destination: AppInformation.issueURL)
            }
        }
        .padding(28)
        .frame(width: 440)
        .accessibilityIdentifier("aboutMDViewer")
    }
}

struct MDViewerHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MDViewer Help")
                        .font(.largeTitle.bold())
                    Text(AppVersion.summary)
                        .foregroundStyle(.secondary)
                }

                helpSection("Open and navigate") {
                    helpRow("Open Markdown", "Use File > Open or drag a Markdown file onto MDViewer.")
                    helpRow("Folder Navigator", "Press ⇧⌘B or use the toolbar to show the optional read-only sidebar. File > Open Folder… authorizes the document folder or an ancestor.")
                    helpRow("Navigator limits", "Folders load only when expanded. Hidden items, packages, and symbolic links are excluded; loading is limited to 12 levels, 500 items per folder, and 5,000 items total.")
                    helpRow("Quick Open", "Press ⌘K to choose another Markdown file in the current folder.")
                    helpRow("Document outline", "Press ⇧⌘O to jump to a heading.")
                    helpRow("Sibling files", "Use ⌥⌘← and ⌥⌘→ to move between Markdown files.")
                }

                helpSection("Read and inspect") {
                    helpRow("Find", "Press ⌘F, then use ⌘G and ⇧⌘G for the next or previous match.")
                    helpRow("Zoom", "Use ⌘+, ⌘−, and ⌘0 for document zoom.")
                    helpRow("Images and code", "Click local images to inspect them. Code blocks provide copy, wrap, and line-number controls.")
                    if AppVersion.edition == .full {
                        helpRow("Full edition", "Mermaid diagrams, broad syntax highlighting, SVG pan and zoom, and YAML frontmatter load only when needed.")
                    }
                }

                helpSection("Support") {
                    HStack(spacing: 18) {
                        Link("Project Website", destination: AppInformation.websiteURL)
                        Link("View Source", destination: AppInformation.sourceURL)
                        Link("Report an Issue", destination: AppInformation.issueURL)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620, height: 560)
        .accessibilityIdentifier("mdViewerHelp")
    }

    private func helpSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func helpRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .fontWeight(.semibold)
            Text(detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
