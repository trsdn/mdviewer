import AppKit
import SwiftUI

struct FolderNavigatorSidebar: View {
    @ObservedObject var state: FolderNavigatorState
    let chooseRoot: () -> Void
    let openFile: (FolderNavigatorNode) -> Void
    @FocusState private var isTreeFocused: Bool

    private var rows: [FolderNavigatorNode] {
        visibleChildren(of: "")
    }

    private var rootNode: FolderNavigatorNode {
        FolderNavigatorNode(
            id: "",
            name: state.rootName,
            relativePath: "",
            kind: .directory,
            depth: 0,
            isExpandable: true,
            isTruncated: false
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Folder Navigator")
                    .font(.headline)
                Spacer()
                Button(action: chooseRoot) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open Folder…")
                .accessibilityLabel("Open folder in navigator")
            }
            .padding(10)

            Divider()

            switch state.rootStatus {
            case .unavailable:
                statusView(
                    title: "No Folder Available",
                    detail: "Choose this document’s folder or an ancestor to grant read-only access.",
                    button: "Open Folder…"
                )
            case .moved:
                statusView(
                    title: "Folder Moved or Removed",
                    detail: "Choose the folder again to restore access.",
                    button: "Choose Folder…"
                )
            case .accessDenied(let message):
                statusView(
                    title: "Folder Unavailable",
                    detail: message,
                    button: "Choose Folder…"
                )
            case .ready:
                tree
            }
        }
        .frame(minWidth: FolderNavigatorLayout.minimumWidth,
               idealWidth: state.width,
               maxWidth: FolderNavigatorLayout.maximumWidth)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { state.updateWidth(geometry.size.width) }
                    .onChange(of: geometry.size.width) {
                        state.updateWidth($0)
                    }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Folder Navigator")
        .accessibilityIdentifier("folderNavigator")
    }

    private var tree: some View {
        List(selection: Binding(
            get: { state.selectedRelativePath },
            set: { state.selectedRelativePath = $0 }
        )) {
            navigatorRow(rootNode)
            ForEach(rows) { node in
                navigatorRow(node)
            }
            if let rootChildren = state.childrenByDirectory[""],
               rootChildren.nodes.isEmpty {
                Label("Empty folder", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Empty folder")
            }
        }
        .listStyle(.sidebar)
        .focusable()
        .focused($isTreeFocused)
        .onMoveCommand(perform: moveSelection)
        .background {
            FolderNavigatorKeyboardMonitor(
                isActive: isTreeFocused,
                selectFirst: { state.select("") },
                selectLast: { state.select(rows.last?.relativePath ?? "") },
                activate: activateSelection
            )
        }
    }

    private struct FolderNavigatorKeyboardMonitor: NSViewRepresentable {
        let isActive: Bool
        let selectFirst: () -> Void
        let selectLast: () -> Void
        let activate: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> NSView {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown
            ) { [weak coordinator = context.coordinator] event in
                guard let coordinator, coordinator.isActive else { return event }
                switch event.keyCode {
                case 115: // Home
                    coordinator.selectFirst()
                case 119: // End
                    coordinator.selectLast()
                case 36, 76, 49: // Return, keypad Enter, Space
                    coordinator.activate()
                default:
                    return event
                }
                return nil
            }
            return NSView(frame: .zero)
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.isActive = isActive
            context.coordinator.selectFirst = selectFirst
            context.coordinator.selectLast = selectLast
            context.coordinator.activate = activate
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            if let monitor = coordinator.monitor {
                NSEvent.removeMonitor(monitor)
            }
            coordinator.monitor = nil
        }

        final class Coordinator {
            var monitor: Any?
            var isActive = false
            var selectFirst: () -> Void = {}
            var selectLast: () -> Void = {}
            var activate: () -> Void = {}

            deinit {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
        }
    }

    @ViewBuilder
    private func navigatorRow(_ node: FolderNavigatorNode) -> some View {
        HStack(spacing: 4) {
            if node.kind == .directory {
                Button {
                    isTreeFocused = true
                    state.select(node.relativePath)
                    state.toggleDirectory(node.relativePath)
                } label: {
                    Image(systemName: state.expandedRelativePaths.contains(node.relativePath)
                          ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!node.isExpandable)
                .accessibilityLabel(
                    state.expandedRelativePaths.contains(node.relativePath)
                        ? "Collapse \(node.name)" : "Expand \(node.name)"
                )
                .accessibilityIdentifier(
                    "folderNavigator.disclosure.\(node.relativePath)"
                )
            } else {
                Color.clear.frame(width: 12)
            }

            Button {
                isTreeFocused = true
                state.select(node.relativePath)
                if node.kind == .directory {
                    state.toggleDirectory(node.relativePath)
                } else {
                    openFile(node)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: node.kind == .directory ? "folder" : "doc.text")
                        .accessibilityHidden(true)
                    Text(node.name)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if node.relativePath == state.currentRelativePath {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .accessibilityLabel("Current document")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(accessibilityLabel(for: node))
            .accessibilityIdentifier(
                "folderNavigator.item.\(node.relativePath)"
            )

            if state.loadingDirectories.contains(node.relativePath) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading \(node.name)")
            }
        }
        .padding(.leading, CGFloat(node.depth) * 14)
        .tag(node.relativePath)
        .help(node.relativePath.isEmpty ? state.rootName : node.relativePath)

        if let children = state.childrenByDirectory[node.relativePath],
           children.isTruncated {
            Text("\(children.omittedCount) more items not shown")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, CGFloat(node.depth + 1) * 14)
                .accessibilityLabel("Folder truncated. \(children.omittedCount) more items not shown.")
        }
    }

    private func visibleChildren(of directory: String) -> [FolderNavigatorNode] {
        guard state.expandedRelativePaths.contains(directory),
              let children = state.childrenByDirectory[directory] else { return [] }
        var result: [FolderNavigatorNode] = []
        for node in children.nodes {
            result.append(node)
            if node.kind == .directory {
                result.append(contentsOf: visibleChildren(of: node.relativePath))
            }
        }
        return result
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let paths = [""] + rows.map(\.relativePath)
        guard !paths.isEmpty else { return }
        let current = paths.firstIndex(of: state.selectedRelativePath ?? "") ?? 0
        switch direction {
        case .up:
            state.select(paths[max(0, current - 1)])
        case .down:
            state.select(paths[min(paths.count - 1, current + 1)])
        case .left:
            let selected = paths[current]
            if state.expandedRelativePaths.contains(selected) {
                state.toggleDirectory(selected)
            } else if let slash = selected.lastIndex(of: "/") {
                state.select(String(selected[..<slash]))
            } else {
                state.select("")
            }
        case .right:
            let selected = paths[current]
            if node(for: selected)?.kind == .directory,
               !state.expandedRelativePaths.contains(selected) {
                state.toggleDirectory(selected)
            }
        @unknown default:
            break
        }
    }

    private func activateSelection() {
        let selected = state.selectedRelativePath ?? ""
        guard let node = node(for: selected) else { return }
        if node.kind == .directory {
            state.toggleDirectory(selected)
        } else {
            openFile(node)
        }
    }

    private func node(for relativePath: String) -> FolderNavigatorNode? {
        relativePath.isEmpty
            ? rootNode
            : rows.first { $0.relativePath == relativePath }
    }

    private func accessibilityLabel(for node: FolderNavigatorNode) -> String {
        var parts = [node.name, node.kind == .directory ? "folder" : "Markdown file"]
        if node.relativePath == state.currentRelativePath {
            parts.append("current document")
        }
        return parts.joined(separator: ", ")
    }

    private func statusView(title: String, detail: String, button: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(button, action: chooseRoot)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
