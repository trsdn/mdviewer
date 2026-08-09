import Combine
import Foundation

/// Debounced native watcher for a single folder.
///
/// Uses a folder file descriptor plus `DispatchSourceFileSystemObject`, so
/// there is no polling, no timer loop while idle and no third-party
/// dependency. Only directory-level events are observed; the open document is
/// never reloaded or overwritten by this type.
@MainActor
final class MarkdownFolderWatcher: ObservableObject {
    /// Coalescing window for bursts of filesystem events.
    nonisolated static let defaultDebounce: Duration = .milliseconds(250)

    private let debounce: Duration
    private var descriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var generation = 0
    private var onChange: (() -> Void)?

    private(set) var watchedFolder: URL?

    init(debounce: Duration = MarkdownFolderWatcher.defaultDebounce) {
        self.debounce = debounce
    }

    deinit {
        // `stop()` is main-actor isolated; tear the primitives down directly.
        source?.cancel()
        debounceTask?.cancel()
    }

    var isWatching: Bool { source != nil }

    /// Starts watching `folderURL`, replacing any previous watch.
    ///
    /// - Returns: `true` when the folder could be opened for watching.
    @discardableResult
    func start(watching folderURL: URL, onChange: @escaping () -> Void) -> Bool {
        stop()

        let path = MarkdownFileCatalog.canonical(folderURL).path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return false }

        generation &+= 1
        let watchGeneration = generation
        descriptor = fd
        watchedFolder = MarkdownFileCatalog.canonical(folderURL)
        self.onChange = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .revoke, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.revoke)
                || events.contains(.rename) {
                // The folder itself moved or vanished. Report once, then stop:
                // the descriptor no longer refers to a usable location.
                self.scheduleNotification(for: watchGeneration, thenStop: true)
                return
            }
            self.scheduleNotification(for: watchGeneration, thenStop: false)
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        self.source = source
        source.resume()
        return true
    }

    /// Cancels the watcher and releases the descriptor, debouncer and callback.
    func stop() {
        generation &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        descriptor = -1
        watchedFolder = nil
        onChange = nil
    }

    private func scheduleNotification(for watchGeneration: Int, thenStop: Bool) {
        guard watchGeneration == generation else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.debounce ?? Self.defaultDebounce)
            guard !Task.isCancelled,
                  let self,
                  watchGeneration == self.generation else { return }
            self.debounceTask = nil
            let callback = self.onChange
            if thenStop {
                self.stop()
            }
            callback?()
        }
    }
}
