// Global search (CLAUDE.md 5, ⌘K; src/data/search.ts): every entry on every page, collapsed or not, and
// collection names. Accent- and case-insensitive; every word typed must appear.
import Foundation

public struct SearchHit<T> {
    public var item: T
    /// Where the words were found in the text (UTF-16), for highlighting.
    public var ranges: [NSRange]
}

public enum Search {
    public static func words(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func match(_ text: String, _ words: [String]) -> [NSRange]? {
        let ns = text as NSString
        var ranges: [NSRange] = []
        for w in words {
            let r = ns.range(of: w, options: [.caseInsensitive, .diacriticInsensitive])
            if r.location == NSNotFound { return nil }
            ranges.append(r)
        }
        return ranges.sorted { $0.location < $1.location }
    }

    /// Entries containing every word, most recently changed first. Blank lines never match.
    public static func entries(_ entries: [Entry], query: String, limit: Int = 60) -> [SearchHit<Entry>] {
        let words = words(query)
        guard !words.isEmpty else { return [] }
        var hits: [SearchHit<Entry>] = []
        for e in entries where !e.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if let ranges = match(e.text, words) { hits.append(SearchHit(item: e, ranges: ranges)) }
        }
        return Array(hits.sorted { $0.item.updatedAt > $1.item.updatedAt }.prefix(limit))
    }

    public static func collections(_ logs: [Log], query: String) -> [SearchHit<Log>] {
        let words = words(query)
        guard !words.isEmpty else { return [] }
        return logs.compactMap { l in
            guard l.kind == .collection, let ranges = match(l.title, words) else { return nil }
            return SearchHit(item: l, ranges: ranges)
        }
    }
}
