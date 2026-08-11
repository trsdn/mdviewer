import Foundation

struct PendingFolderNavigatorContext: Equatable {
    let rootURL: URL
    let isVisible: Bool
    let expandedRelativePaths: Set<String>
    let selectedRelativePath: String?
    let width: Double
}

@MainActor
final class FolderNavigatorContextStore {
    static let shared = FolderNavigatorContextStore()

    private struct Entry {
        let context: PendingFolderNavigatorContext
        let storedAt: Date
    }

    /// Long enough for slow document-window creation, while bounding abandoned
    /// contexts from opens that never create a destination window.
    nonisolated static let defaultExpiration: TimeInterval = 10 * 60
    nonisolated static let defaultMaximumEntries = 64

    private var contexts: [URL: Entry] = [:]
    private let expiration: TimeInterval
    private let maximumEntries: Int
    private let now: () -> Date

    init(
        expiration: TimeInterval = FolderNavigatorContextStore.defaultExpiration,
        maximumEntries: Int = FolderNavigatorContextStore.defaultMaximumEntries,
        now: @escaping () -> Date = Date.init
    ) {
        self.expiration = expiration
        self.maximumEntries = max(1, maximumEntries)
        self.now = now
    }

    func store(_ context: PendingFolderNavigatorContext, for destination: URL) {
        let currentTime = now()
        prune(at: currentTime)
        contexts[FolderNavigatorPath.canonical(destination)] = Entry(
            context: context,
            storedAt: currentTime
        )
        if contexts.count > maximumEntries {
            for key in contexts.sorted(by: { $0.value.storedAt < $1.value.storedAt })
                .prefix(contexts.count - maximumEntries)
                .map(\.key) {
                contexts.removeValue(forKey: key)
            }
        }
    }

    func consume(for destination: URL) -> PendingFolderNavigatorContext? {
        prune(at: now())
        return contexts.removeValue(
            forKey: FolderNavigatorPath.canonical(destination)
        )?.context
    }

    func clear(for destination: URL) {
        contexts.removeValue(forKey: FolderNavigatorPath.canonical(destination))
    }

    private func prune(at currentTime: Date) {
        contexts = contexts.filter {
            currentTime.timeIntervalSince($0.value.storedAt) <= expiration
        }
    }
}
