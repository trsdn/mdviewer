import Foundation

/// One rendered heading, produced by the render pipeline so outline anchors and
/// rendered heading IDs always come from exactly the same slugging contract.
struct OutlineEntry: Identifiable, Equatable {
    let id: String
    let level: Int
    let title: String

    init(id: String, level: Int, title: String) {
        self.id = id
        self.level = max(1, min(6, level))
        self.title = title
    }

    /// Best-effort construction from the render page payload.
    init?(payload: [String: Any]) {
        guard let id = payload["id"] as? String, !id.isEmpty,
              let title = payload["title"] as? String else {
            return nil
        }
        let level = (payload["level"] as? NSNumber)?.intValue ?? 1
        self.init(id: id, level: level, title: title)
    }
}

/// Search-as-you-type filtering for the outline popover.
///
/// Deterministic, dependency-free and order-preserving: entries always appear
/// in document order so hierarchy stays readable while filtering.
enum OutlineFilter {
    static func filter(_ entries: [OutlineEntry], query: String) -> [OutlineEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let needle = trimmed.lowercased()
        return entries.filter { entry in
            entry.title.lowercased().contains(needle)
        }
    }

    /// Indentation depth relative to the shallowest heading present, so a
    /// document that starts at `##` is not indented for no reason.
    static func indentationLevels(for entries: [OutlineEntry]) -> [Int] {
        guard let minimum = entries.map(\.level).min() else { return [] }
        return entries.map { $0.level - minimum }
    }
}
