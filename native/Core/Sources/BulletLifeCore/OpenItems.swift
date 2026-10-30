// Open items (CLAUDE.md 4), ported from src/data/openItems.ts: a query derived from the entries, never stored.
// It shows what is loose; resolving anything is always the user's own gesture on one entry.
import Foundation


public enum OpenCategory: String, Sendable {
    /// Due today or overdue, on any page.
    case due
    /// A. Still open on a Day, Week or Month that has ended.
    case ended
    /// B. Marked > or < but not yet written at the destination.
    case unplaced
    /// C. A Year item whose month has come.
    case arrived
}

/// The page an entry lives on.
public struct Source: Equatable, Sendable {
    public var logId: String
    public var kind: LogKind
    /// Period key ('2026-10-18', '2026-W43', '2026-10', '2026'); the log id for a collection.
    public var key: String
    public var start: String?
    public var end: String?

    public init(logId: String, firstDay: Weekday) {
        self.logId = logId
        let parts = logId.split(separator: ":", maxSplits: 1).map(String.init)
        let key = parts.count == 2 ? parts[1] : logId
        self.key = key
        switch parts.first {
        case "daily":
            kind = .daily
            start = key
            end = key
        case "weekly":
            kind = .weekly
            start = Dates.weekKeyStart(key, firstDay: firstDay)
            end = Dates.addDays(start!, 6)
        case "monthly":
            kind = .monthly
            start = "\(key)-01"
            end = "\(key)-\(Dates.pad(Dates.daysInMonth(key)))"
        case "future":
            kind = .future
            start = "\(key)-01-01"
            end = "\(key)-12-31"
        default:
            kind = .collection
            self.key = logId
        }
    }

    /// The time page it is, if any.
    public var period: Period? {
        switch kind {
        case .daily: return .day(key)
        case .weekly: return .week(key)
        case .monthly: return .month(key)
        case .future: return .year(key)
        case .collection: return nil
        }
    }
}

public struct OpenItem: Equatable, Sendable {
    public var entry: Entry
    public var category: OpenCategory
    public var source: Source
}

public struct OpenGroup: Equatable, Sendable {
    /// One group per page; Year items are grouped by month; due items together.
    public var id: String
    public var source: Source
    public var slot: String
    public var items: [OpenItem]
}

public enum OpenItems {
    public static func category(_ e: Entry, _ src: Source, eventStates: Bool, today: String) -> OpenCategory? {
        guard States.stateful(e.type, eventStates: eventStates) else { return nil }
        if (e.state == .migrated || e.state == .scheduled) && e.placement?.status == .pending { return .unplaced }
        guard e.state == .open else { return nil }
        if let due = Due.of(e.text), due <= today { return .due }
        if src.kind == .future { return !e.slot.isEmpty && e.slot <= Dates.monthOf(today) ? .arrived : nil }
        if src.kind != .collection, let end = src.end, end < today { return .ended }
        return nil
    }

    /// Everything that is loose, oldest first (due items first, by date).
    public static func items(_ entries: [Entry], eventStates: Bool, firstDay: Weekday, today: String) -> [OpenItem] {
        sorted(entries.compactMap { e in
            let src = Source(logId: e.logId, firstDay: firstDay)
            return category(e, src, eventStates: eventStates, today: today).map { OpenItem(entry: e, category: $0, source: src) }
        })
    }

    /// Close the day: what is still open on today's page.
    public static func openToday(_ entries: [Entry], eventStates: Bool, firstDay: Weekday, today: String) -> [OpenItem] {
        let logId = "daily:\(today)"
        let src = Source(logId: logId, firstDay: firstDay)
        return sorted(entries.filter { $0.logId == logId && $0.state == .open && States.stateful($0.type, eventStates: eventStates) }
            .map { OpenItem(entry: $0, category: .ended, source: src) })
    }

    static let kindRank: [LogKind: Int] = [.future: 0, .monthly: 1, .weekly: 2, .daily: 3, .collection: 4]

    static func sortKey(_ i: OpenItem) -> String {
        if i.category == .due {
            return ["0", Due.of(i.entry.text) ?? "", i.source.logId, i.entry.slot, i.entry.order].joined(separator: "|")
        }
        let start = i.source.kind == .future ? "\(i.entry.slot.isEmpty ? i.source.key : i.entry.slot)-01" : (i.source.start ?? "9999")
        return ["1", start, String(kindRank[i.source.kind] ?? 9), i.source.logId, i.entry.slot, i.entry.order].joined(separator: "|")
    }

    public static func sorted(_ items: [OpenItem]) -> [OpenItem] {
        items.map { (sortKey($0), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
    }

    public static func groups(_ items: [OpenItem]) -> [OpenGroup] {
        var out: [OpenGroup] = []
        for item in items {
            let slot = item.source.kind == .future ? item.entry.slot : ""
            let id = item.category == .due ? "due" : "\(item.source.logId)|\(slot)"
            if out.last?.id == id { out[out.count - 1].items.append(item) } else { out.append(OpenGroup(id: id, source: item.source, slot: slot, items: [item])) }
        }
        return out
    }

    /// Items the user acted on while the panel is open stay listed (with their new state) until it closes, so a
    /// second tap can still cancel a completed item.
    public static func withKept(_ items: [OpenItem], kept: [String: OpenItem], byId: [String: Entry]) -> [OpenItem] {
        let listed = Set(items.map(\.entry.id))
        let extra = kept.compactMap { id, item -> OpenItem? in
            guard !listed.contains(id), let entry = byId[id] else { return nil }
            var i = item
            i.entry = entry
            return i
        }
        return extra.isEmpty ? items : sorted(items + extra)
    }

    // MARK: Labels

    /// How long ago a period ended: "yesterday", "last week", "2 weeks ago". Empty while it is still running.
    public static func ageLabel(_ end: String?, today: String) -> String {
        guard let end, end < today else { return "" }
        let days = Int((Dates.fromIso(today).timeIntervalSince(Dates.fromIso(end)) / 86_400).rounded())
        func ago(_ n: Int, _ unit: String) -> String { n == 1 ? (unit == "day" ? "yesterday" : "last \(unit)") : "\(n) \(unit)s ago" }
        if days < 7 { return ago(days, "day") }
        if days < 30 { return ago(Int((Double(days) / 7).rounded()), "week") }
        if days < 365 { return ago(Int((Double(days) / 30.4).rounded()), "month") }
        return ago(Int((Double(days) / 365).rounded()), "year")
    }

    static func format(_ iso: String, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        var c = DateComponents()
        let p = iso.split(separator: "-").compactMap { Int($0) }
        c.year = p[0]
        c.month = p.count > 1 ? p[1] : 1
        c.day = p.count > 2 ? p[2] : 1
        c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return f.string(from: cal.date(from: c)!)
    }

    /// "Due", "Wk 41 · Oct 5 – 11", "Mon, Oct 5", "September 2026", "2026 · October", or the collection title.
    public static func groupLabel(_ g: OpenGroup, collectionTitle: String? = nil) -> String {
        g.id == "due" ? "Due" : sourceLabel(g.source, slot: g.slot, collectionTitle: collectionTitle)
    }

    public static func sourceLabel(_ s: Source, slot: String = "", collectionTitle: String? = nil) -> String {
        switch s.kind {
        case .daily:
            return format(s.key, "EEEMMMd")
        case .weekly:
            let start = s.start!, end = s.end!
            let same = start.prefix(7) == end.prefix(7)
            return "Wk \(Dates.weekNumber(s.key)) · \(format(start, "MMMd")) – \(same ? String(Int(end.suffix(2)) ?? 0) : format(end, "MMMd"))"
        case .monthly:
            return format("\(s.key)-01", "MMMMyyyy")
        case .future:
            return slot.isEmpty ? s.key : "\(s.key) · \(format("\(slot)-01", "MMMM"))"
        case .collection:
            return collectionTitle ?? ""
        }
    }
}
