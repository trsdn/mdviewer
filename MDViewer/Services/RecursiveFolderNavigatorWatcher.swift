import CoreServices
import Foundation

@MainActor
final class RecursiveFolderNavigatorWatcher {
    private final class CallbackContext {
        weak var watcher: RecursiveFolderNavigatorWatcher?
        let generation: Int
        let rootURL: URL

        init(
            watcher: RecursiveFolderNavigatorWatcher,
            generation: Int,
            rootURL: URL
        ) {
            self.watcher = watcher
            self.generation = generation
            self.rootURL = rootURL
        }
    }

    nonisolated static let defaultDebounce: Duration = .milliseconds(250)

    private let debounce: Duration
    private var stream: FSEventStreamRef?
    private var retainedContext: Unmanaged<CallbackContext>?
    private var debounceTask: Task<Void, Never>?
    private var pendingPaths = Set<URL>()
    private var generation = 0
    private var rootURL: URL?
    private var onChange: ((Set<URL>) -> Void)?
    private var onRootUnavailable: (() -> Void)?

    private(set) var activeGeneration: Int?

    init(debounce: Duration = RecursiveFolderNavigatorWatcher.defaultDebounce) {
        self.debounce = debounce
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        retainedContext?.release()
        debounceTask?.cancel()
    }

    @discardableResult
    func start(
        watching root: URL,
        onChange: @escaping (Set<URL>) -> Void,
        onRootUnavailable: @escaping () -> Void
    ) -> Bool {
        stop()
        let canonicalRoot = FolderNavigatorPath.canonical(root)
        guard (try? canonicalRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { return false }

        generation &+= 1
        let streamGeneration = generation
        activeGeneration = streamGeneration
        rootURL = canonicalRoot
        self.onChange = onChange
        self.onRootUnavailable = onRootUnavailable

        let retained = Unmanaged.passRetained(
            CallbackContext(
                watcher: self,
                generation: streamGeneration,
                rootURL: canonicalRoot
            )
        )
        retainedContext = retained
        var context = FSEventStreamContext(
            version: 0,
            info: retained.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, count, paths, eventFlags, _ in
                guard let info else { return }
                let context = Unmanaged<CallbackContext>
                    .fromOpaque(info).takeUnretainedValue()
                guard let watcher = context.watcher else { return }
                let streamGeneration = context.generation
                let pathArray = unsafeBitCast(paths, to: NSArray.self)
                var changed: [URL] = []
                var rootUnavailable = false
                var requiresFullRefresh = false
                for index in 0..<count {
                    if let path = pathArray[index] as? String {
                        changed.append(URL(fileURLWithPath: path))
                    }
                    let flags = eventFlags[index]
                    if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                        || flags & FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount) != 0 {
                        rootUnavailable = true
                    }
                    if RecursiveFolderNavigatorWatcher.requiresFullRefresh(flags) {
                        requiresFullRefresh = true
                    }
                }
                if requiresFullRefresh {
                    // A dropped/coalesced event stream cannot identify every
                    // affected path. The root sentinel refreshes all and only
                    // directories already loaded by navigator state.
                    changed.append(context.rootURL)
                }
                Task { @MainActor in
                    watcher.receive(
                        changed,
                        rootUnavailable: rootUnavailable,
                        streamGeneration: streamGeneration
                    )
                }
            },
            &context,
            [canonicalRoot.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            retained.release()
            retainedContext = nil
            activeGeneration = nil
            rootURL = nil
            self.onChange = nil
            self.onRootUnavailable = nil
            return false
        }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        generation &+= 1
        debounceTask?.cancel()
        debounceTask = nil
        pendingPaths.removeAll()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        retainedContext?.release()
        retainedContext = nil
        rootURL = nil
        activeGeneration = nil
        onChange = nil
        onRootUnavailable = nil
    }

    func receive(
        _ paths: [URL],
        rootUnavailable: Bool,
        streamGeneration: Int
    ) {
        guard stream != nil, streamGeneration == generation else { return }
        if rootUnavailable {
            let callback = onRootUnavailable
            stop()
            callback?()
            return
        }
        pendingPaths.formUnion(paths.map(FolderNavigatorPath.canonical))
        let eventGeneration = streamGeneration
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.debounce ?? Self.defaultDebounce)
            guard !Task.isCancelled, let self, self.generation == eventGeneration else {
                return
            }
            let paths = self.pendingPaths
            self.pendingPaths.removeAll()
            self.onChange?(paths)
        }
    }

    nonisolated static func requiresFullRefresh(
        _ flags: FSEventStreamEventFlags
    ) -> Bool {
        let fullRefreshFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
        )
        return flags & fullRefreshFlags != 0
    }
}
