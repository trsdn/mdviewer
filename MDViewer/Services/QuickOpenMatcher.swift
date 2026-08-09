import Foundation

struct QuickOpenItem: Identifiable, Equatable {
    let url: URL
    var name: String { url.lastPathComponent }
    var id: String { url.path }
}

/// Dependency-free deterministic matching for the Quick Open palette.
///
/// Ordering is fully determined by the query and the candidate names, so the
/// same query always produces the same list. No index is retained: the palette
/// enumerates the authorized folder while it is open and discards the result
/// when it closes.
enum QuickOpenMatcher {
    /// Upper bound on presented results. Keeps the palette responsive in very
    /// large folders without a background index.
    static let resultLimit = 200

    private enum Rank: Int {
        case exact = 0
        case prefix = 1
        case wordPrefix = 2
        case substring = 3
        case subsequence = 4
    }

    private struct Scored {
        let item: QuickOpenItem
        let rank: Rank
        let offset: Int
    }

    static func filter(_ items: [QuickOpenItem], query: String) -> [QuickOpenItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(items.prefix(resultLimit))
        }

        let needle = Array(trimmed.lowercased())
        var scored: [Scored] = []
        scored.reserveCapacity(items.count)

        for item in items {
            let haystack = Array(item.name.lowercased())
            guard let match = score(haystack: haystack, needle: needle) else {
                continue
            }
            scored.append(
                Scored(item: item, rank: match.rank, offset: match.offset)
            )
        }

        scored.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank.rawValue < rhs.rank.rawValue }
            if lhs.offset != rhs.offset { return lhs.offset < rhs.offset }
            if lhs.item.name.count != rhs.item.name.count {
                return lhs.item.name.count < rhs.item.name.count
            }
            return MarkdownFileCatalog.filenamePrecedes(lhs.item.url, rhs.item.url)
        }

        return scored.prefix(resultLimit).map(\.item)
    }

    private static func score(
        haystack: [Character],
        needle: [Character]
    ) -> (rank: Rank, offset: Int)? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }

        if haystack == needle { return (.exact, 0) }
        if haystack.starts(with: needle) { return (.prefix, 0) }

        if let offset = firstIndex(of: needle, in: haystack) {
            let isWordStart = offset == 0 || isSeparator(haystack[offset - 1])
            return (isWordStart ? .wordPrefix : .substring, offset)
        }

        // Ordered subsequence, e.g. "rme" matches "readme.md".
        var needleIndex = 0
        var firstMatch: Int?
        for (index, character) in haystack.enumerated() {
            if character == needle[needleIndex] {
                if firstMatch == nil { firstMatch = index }
                needleIndex += 1
                if needleIndex == needle.count {
                    return (.subsequence, firstMatch ?? index)
                }
            }
        }
        return nil
    }

    private static func firstIndex(
        of needle: [Character],
        in haystack: [Character]
    ) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        let limit = haystack.count - needle.count
        var start = 0
        while start <= limit {
            var offset = 0
            while offset < needle.count, haystack[start + offset] == needle[offset] {
                offset += 1
            }
            if offset == needle.count { return start }
            start += 1
        }
        return nil
    }

    private static func isSeparator(_ character: Character) -> Bool {
        character == " " || character == "-" || character == "_"
            || character == "." || character == "/"
    }
}
