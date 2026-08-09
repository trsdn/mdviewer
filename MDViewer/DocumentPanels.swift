import SwiftUI

@MainActor
final class PendingDocumentNavigation {
    static let shared = PendingDocumentNavigation()

    private var fragments: [URL: String] = [:]

    func store(fragment: String?, for url: URL) {
        guard let fragment, !fragment.isEmpty else { return }
        fragments[MarkdownFileCatalog.canonical(url)] =
            fragment.removingPercentEncoding ?? fragment
    }

    func consumeFragment(for url: URL) -> String? {
        fragments.removeValue(forKey: MarkdownFileCatalog.canonical(url))
    }
}

struct DocumentFindBar: View {
    @Binding var query: String
    let status: String
    let findNext: () -> Void
    let findPrevious: () -> Void
    let queryChanged: () -> Void
    let close: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($isFocused)
                .accessibilityIdentifier("documentFindField")
                .onSubmit(findNext)
                .onChange(of: query) { _ in queryChanged() }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)
                .accessibilityIdentifier("documentFindStatus")

            Button(action: findPrevious) {
                Image(systemName: "chevron.up")
            }
            .help("Find Previous")
            .disabled(query.isEmpty)

            Button(action: findNext) {
                Image(systemName: "chevron.down")
            }
            .help("Find Next")
            .disabled(query.isEmpty)

            Button(action: close) {
                Image(systemName: "xmark")
            }
            .help("Close Find")
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .onAppear { isFocused = true }
        .onExitCommand(perform: close)
    }
}

struct QuickOpenPalette: View {
    let items: [QuickOpenItem]
    let open: (QuickOpenItem) -> Void
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selection: QuickOpenItem.ID?
    @FocusState private var isFocused: Bool

    private var filteredItems: [QuickOpenItem] {
        QuickOpenMatcher.filter(items, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Open Markdown file", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($isFocused)
                .accessibilityIdentifier("quickOpenField")
                .onSubmit(openSelection)

            Divider()

            if filteredItems.isEmpty {
                emptyState(
                    title: "No Markdown Files",
                    systemImage: "doc.text.magnifyingglass",
                    message: "No current-folder file matches your search."
                )
            } else {
                List(filteredItems, selection: $selection) { item in
                    Text(item.name)
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open(item) }
                }
            }
        }
        .frame(width: 480, height: 360)
        .onAppear {
            selection = filteredItems.first?.id
            isFocused = true
        }
        .onChange(of: query) { _ in
            selection = filteredItems.first?.id
        }
        .onExitCommand(perform: dismiss)
    }

    private func emptyState(
        title: String,
        systemImage: String,
        message: String
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSelection() {
        guard let item = filteredItems.first(where: { $0.id == selection })
                ?? filteredItems.first else {
            return
        }
        open(item)
    }
}

struct DocumentOutlinePopover: View {
    let entries: [OutlineEntry]
    let select: (OutlineEntry) -> Void

    @State private var query = ""
    @State private var selection: OutlineEntry.ID?
    @FocusState private var isFocused: Bool

    private var filteredEntries: [OutlineEntry] {
        OutlineFilter.filter(entries, query: query)
    }

    private var indentation: [OutlineEntry.ID: Int] {
        Dictionary(
            uniqueKeysWithValues: zip(
                filteredEntries.map(\.id),
                OutlineFilter.indentationLevels(for: filteredEntries)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter headings", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .focused($isFocused)
                .accessibilityIdentifier("documentOutlineField")
                .onSubmit(selectCurrent)

            Divider()

            if filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet.indent")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Headings").font(.headline)
                    Text("This document has no matching headings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredEntries, selection: $selection) { entry in
                    Text(entry.title)
                        .padding(.leading, CGFloat(indentation[entry.id] ?? 0) * 14)
                        .tag(entry.id)
                        .contentShape(Rectangle())
                        .onTapGesture { select(entry) }
                }
            }
        }
        .frame(width: 360, height: 420)
        .onAppear {
            selection = filteredEntries.first?.id
            isFocused = true
        }
        .onChange(of: query) { _ in
            selection = filteredEntries.first?.id
        }
    }

    private func selectCurrent() {
        guard let entry = filteredEntries.first(where: { $0.id == selection })
                ?? filteredEntries.first else {
            return
        }
        select(entry)
    }
}
