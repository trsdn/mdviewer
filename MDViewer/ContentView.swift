import SwiftUI

enum ZoomAction {
    case zoomIn
    case zoomOut
    case zoomReset
}

struct MarkdownDocumentLoader {
    static func load(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

struct ZoomPreference {
    static let key = "zoomLevel"
    static let minimum = 0.5
    static let maximum = 3.0
    static let standard = 1.0

    static func current(in defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: key) != nil else { return standard }
        return clamped(defaults.double(forKey: key))
    }

    static func value(after action: ZoomAction, current: Double) -> Double {
        switch action {
        case .zoomIn:
            return clamped((current * 10 + 1).rounded() / 10)
        case .zoomOut:
            return clamped((current * 10 - 1).rounded() / 10)
        case .zoomReset:
            return standard
        }
    }

    static func save(_ value: Double, in defaults: UserDefaults = .standard) {
        defaults.set(clamped(value), forKey: key)
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

private enum DocumentAlert: Identifiable {
    case error(title: String, message: String)

    var id: String {
        switch self {
        case .error(let title, let message):
            return "\(title):\(message)"
        }
    }
}

struct ContentView: View {
    @Environment(\.openDocument) private var openDocument

    let document: MarkdownDocument
    let fileURL: URL?
    let palette: ThemePalette
    @State private var text: String
    @State private var zoomLevel: Double
    @State private var documentAlert: DocumentAlert?
    @State private var folderAccess: FolderAccessLease?
    @State private var relativeImagesRequested = false
    @State private var resourceAccessDeclined = false
    @State private var isRequestingResourceAccess = false
    @State private var didRestoreFolderAccess = false
    @State private var resourceAccessGeneration = 0
    @State private var resourceDocumentURL: URL?
    @State private var siblingTargets = SiblingNavigationTargets.none
    @State private var navigationFolderAccess: FolderAccessLease?
    @State private var navigationNeedsFolderAccess = false
    @State private var isNavigating = false
    @StateObject private var windowState = DocumentWindowState()

    init(document: MarkdownDocument, fileURL: URL?, palette: ThemePalette) {
        self.document = document
        self.fileURL = fileURL
        self.palette = palette
        self._text = State(initialValue: document.text)
        self._zoomLevel = State(initialValue: ZoomPreference.current())
        self._resourceDocumentURL = State(initialValue: fileURL)
    }

    var body: some View {
        MarkdownWebView(
            text: text,
            palette: palette,
            zoomLevel: zoomLevel,
            resourceRoot: folderAccess?.rootURL,
            onError: showRenderError,
            onRelativeImages: handleRelativeImages
        )
        .background(palette.colors.background.swiftUIColor)
        .background(DocumentWindowAccessor(state: windowState))
        .overlay(alignment: .topTrailing) {
            resourceAccessNotice
        }
        .focusedSceneValue(\.documentCommandActions, commandActions)
        .task(id: fileURL) {
            resetFolderAccess()
            prepareSiblingNavigation()
        }
        .alert(item: $documentAlert) { alert in
            switch alert {
            case .error(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var commandActions: DocumentCommandActions {
        DocumentCommandActions(
            canReload: fileURL != nil,
            canNavigatePrevious: !isNavigating && siblingTargets.previous != nil,
            canNavigateNext: !isNavigating && siblingTargets.next != nil,
            canRefreshSiblingNavigation: !isNavigating && fileURL != nil,
            reload: reload,
            navigatePrevious: { navigate(to: .previous) },
            navigateNext: { navigate(to: .next) },
            refreshSiblingNavigation: refreshSiblingNavigation,
            zoomIn: { handleZoom(.zoomIn) },
            zoomOut: { handleZoom(.zoomOut) },
            zoomReset: { handleZoom(.zoomReset) }
        )
    }

    @ViewBuilder
    private var resourceAccessNotice: some View {
        if relativeImagesRequested, folderAccess == nil {
            HStack(spacing: 8) {
                Text(
                    fileURL == nil
                        ? "Open a saved document to load relative images."
                        : "Read-only folder access is required for relative images."
                )
                .font(.caption)

                if fileURL != nil {
                    Button(resourceAccessDeclined ? "Grant Access" : "Choose Folder") {
                        resourceAccessDeclined = false
                        requestFolderAccess()
                    }
                    .disabled(isRequestingResourceAccess)
                }
            }
            .padding(8)
            .background(.regularMaterial)
            .cornerRadius(6)
            .padding(8)
        }
    }

    private func handleZoom(_ action: ZoomAction) {
        let value = ZoomPreference.value(after: action, current: zoomLevel)
        zoomLevel = value
        ZoomPreference.save(value)
    }

    private func reload() {
        guard let fileURL else { return }

        do {
            text = try MarkdownDocumentLoader.load(from: fileURL)
            refreshSiblingTargetsAfterReload(for: fileURL)
        } catch {
            documentAlert = .error(
                title: "Couldn’t Reload Document",
                message: error.localizedDescription
            )
        }
    }

    private func prepareSiblingNavigation() {
        siblingTargets = .none
        navigationFolderAccess = nil
        navigationNeedsFolderAccess = false
        guard let fileURL else { return }

        do {
            navigationFolderAccess = try FolderAccessStore.shared.restoredAccess(
                for: fileURL
            )
            try SiblingMarkdownNavigation.refresh(
                &siblingTargets,
                for: fileURL
            )
        } catch {
            siblingTargets = .none
            navigationNeedsFolderAccess = true
        }
    }

    private func refreshSiblingTargetsAfterReload(for fileURL: URL) {
        navigationNeedsFolderAccess = !SiblingMarkdownNavigation.refreshAfterReload(
            &siblingTargets,
            for: fileURL
        )
    }

    private func refreshSiblingNavigation() {
        guard !isNavigating,
              let fileURL else { return }
        isNavigating = true

        Task { @MainActor in
            defer { isNavigating = false }

            do {
                if navigationNeedsFolderAccess {
                    guard let access = try await FolderAccessStore.shared.requestAccess(
                        for: fileURL,
                        attachedTo: windowState.window,
                        purpose: .siblingNavigation
                    ) else {
                        return
                    }
                    guard self.fileURL == fileURL else { return }
                    navigationFolderAccess = access
                }

                try SiblingMarkdownNavigation.refresh(
                    &siblingTargets,
                    for: fileURL
                )
                navigationNeedsFolderAccess = false
            } catch {
                siblingTargets = .none
                navigationNeedsFolderAccess = true
                showNavigationError(
                    title: "Couldn’t Refresh Sibling Navigation",
                    error: error
                )
            }
        }
    }

    private func navigate(to direction: SiblingNavigationDirection) {
        guard !isNavigating, let fileURL else { return }
        isNavigating = true

        Task { @MainActor in
            defer { isNavigating = false }

            do {
                try SiblingMarkdownNavigation.refresh(
                    &siblingTargets,
                    for: fileURL
                )
            } catch {
                siblingTargets = .none
                navigationNeedsFolderAccess = true
                showNavigationError(
                    title: "Couldn’t Read Folder",
                    error: error
                )
                return
            }

            guard let target = siblingTargets.target(for: direction) else {
                return
            }

            do {
                try await openDocument(at: target)
                windowState.window?.performClose(nil)
            } catch {
                showNavigationError(
                    title: "Couldn’t Open Document",
                    error: error
                )
            }
        }
    }

    private func showNavigationError(title: String, error: Error) {
        documentAlert = .error(
            title: title,
            message: error.localizedDescription
        )
    }

    private func showRenderError(_ message: String) {
        documentAlert = .error(
            title: "Couldn’t Render Document",
            message: message
        )
    }

    private func handleRelativeImages(_ images: [String]) {
        guard !images.isEmpty else {
            resourceAccessGeneration += 1
            folderAccess = nil
            relativeImagesRequested = false
            resourceAccessDeclined = false
            isRequestingResourceAccess = false
            didRestoreFolderAccess = false
            return
        }
        relativeImagesRequested = true

        guard folderAccess == nil,
              let fileURL,
              !resourceAccessDeclined else { return }

        if !didRestoreFolderAccess {
            do {
                folderAccess = try FolderAccessStore.shared.restoredAccess(for: fileURL)
            } catch {
                showResourceError(error)
            }
            didRestoreFolderAccess = true
        }

        guard folderAccess == nil else { return }
        requestFolderAccess()
    }

    private func resetFolderAccess() {
        let documentChanged = resourceDocumentURL != fileURL
        resourceDocumentURL = fileURL
        resourceAccessGeneration += 1
        folderAccess = nil
        if documentChanged {
            relativeImagesRequested = false
        }
        resourceAccessDeclined = false
        isRequestingResourceAccess = false
        didRestoreFolderAccess = false
    }

    private func requestFolderAccess() {
        guard !isRequestingResourceAccess, let fileURL else { return }
        isRequestingResourceAccess = true
        let generation = resourceAccessGeneration

        Task { @MainActor in
            do {
                let access = try await FolderAccessStore.shared.requestAccess(
                    for: fileURL,
                    attachedTo: windowState.window
                )
                guard generation == resourceAccessGeneration,
                      self.fileURL == fileURL else { return }
                folderAccess = access
                resourceAccessDeclined = access == nil
            } catch {
                guard generation == resourceAccessGeneration,
                      self.fileURL == fileURL else { return }
                resourceAccessDeclined = true
                showResourceError(error)
            }
            if generation == resourceAccessGeneration {
                isRequestingResourceAccess = false
            }
        }
    }

    private func showResourceError(_ error: Error) {
        documentAlert = .error(
            title: "Couldn’t Access Relative Images",
            message: error.localizedDescription
        )
    }
}

private final class DocumentWindowState: ObservableObject {
    weak var window: NSWindow?
}

private struct DocumentWindowAccessor: NSViewRepresentable {
    let state: DocumentWindowState

    func makeNSView(context: Context) -> WindowReaderView {
        let view = WindowReaderView()
        view.state = state
        return view
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.state = state
        state.window = nsView.window
    }

    final class WindowReaderView: NSView {
        weak var state: DocumentWindowState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            state?.window = window
        }
    }
}
