// A Habits collection (Fernando): a month of habits, as on paper. Each habit is a row the user writes (an entry
// in the collection, its slot the month 'YYYY-MM'); the days of the month are columns, derived from the date like
// the Month's days. Each day of a habit takes one mark: done (× or ✓, as Settings say), not done (a dot) or
// skipped (a dash, no penalty). Nothing is carried to the next month: its habits are written again by hand.
import Foundation

public enum HabitMark: Character, CaseIterable, Sendable {
    case empty = " "
    case done = "x"
    case missed = "."
    case skipped = "-"

    /// A tap on a day moves the mark on: done, not done, skipped, and back to empty.
    public var next: HabitMark {
        switch self {
        case .empty: return .done
        case .done: return .missed
        case .missed: return .skipped
        case .skipped: return .empty
        }
    }
}

public enum Habits {
    public static let template = "habits"

    /// The mark of day `day` (1-based) in a row's marks.
    public static func mark(_ marks: String?, day: Int) -> HabitMark {
        guard let marks, day >= 1 else { return .empty }
        let chars = Array(marks)
        guard day <= chars.count else { return .empty }
        return HabitMark(rawValue: chars[day - 1]) ?? .empty
    }

    /// The marks with day `day` set to `mark` (trailing empty days are left off).
    public static func setting(_ marks: String?, day: Int, to mark: HabitMark) -> String {
        var chars = Array(marks ?? "")
        while chars.count < day { chars.append(HabitMark.empty.rawValue) }
        chars[day - 1] = mark.rawValue
        while chars.last == HabitMark.empty.rawValue { chars.removeLast() }
        return String(chars)
    }

    /// Days still to fill: for each habit row, each day of its month before today (and today too once
    /// `todayDue`: from the evening check-in, Close the day), from the day the habit was written (a habit added
    /// mid-month does not owe the days before it), without a mark.
    public static func toFill(_ rows: [Entry], today: String, todayDue: Bool = true) -> [String] {
        var days = Set<String>()
        for row in rows where !row.slot.isEmpty && !row.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let ym = row.slot
            guard ym.count == 7, ym <= Dates.monthOf(today) else { continue }
            let since = String(row.createdAt.prefix(10))
            for (i, iso) in Dates.monthDays(ym).enumerated() where (iso < today || (todayDue && iso == today)) && iso >= since {
                if mark(row.marks, day: i + 1) == .empty { days.insert(iso) }
            }
        }
        return days.sorted()
    }

    /// For Open items, one line per Habits collection with days still to fill: how many days, and the latest
    /// one (where a tap takes you).
    public struct Pending: Equatable, Sendable {
        public var logId: String
        public var days: Int
        public var latest: String
    }

    public static func pending(_ entries: [Entry], habitLogIds: Set<String>, today: String, todayDue: Bool = true) -> [Pending] {
        let byLog = Dictionary(grouping: entries.filter { habitLogIds.contains($0.logId) }, by: \.logId)
        return byLog.compactMap { logId, rows in
            let days = toFill(rows, today: today, todayDue: todayDue)
            guard let latest = days.last else { return nil }
            return Pending(logId: logId, days: days.count, latest: latest)
        }.sorted { $0.latest > $1.latest }
    }

    /// A mark written with the pen on a day: a dot is not done, a short flat line is skipped, anything else (a
    /// check, a cross or one of its strokes) is done.
    public static func mark(written s: Stroke) -> HabitMark {
        let b = s.box
        if max(b.width, b.height) <= 8 { return .missed }
        if b.width >= 6 && b.height <= max(4, b.width / 3) { return .skipped }
        return .done
    }

    // MARK: Notes on a period

    /// A note on the habits of some days ("liver crisis + late vet"), as written under those days on paper. It is an
    /// entry of the collection whose slot names its days: 'YYYY-MM-DD..YYYY-MM-DD' (never a month, so it is never
    /// taken for a habit).
    public static func noteSlot(from start: String, to end: String) -> String {
        let (a, b) = start <= end ? (start, end) : (end, start)
        return "\(a)..\(b)"
    }

    /// The days a note's slot names, or nil for any other slot.
    public static func noteDays(_ slot: String) -> (start: String, end: String)? {
        let parts = slot.components(separatedBy: "..")
        guard parts.count == 2, parts[0].count == 10, parts[1].count == 10 else { return nil }
        return (parts[0], parts[1])
    }

    /// The notes of month `ym` (they start in it), by first day.
    public static func notes(_ entries: [Entry], month ym: String) -> [Entry] {
        entries.filter { e in noteDays(e.slot).map { Dates.monthOf($0.start) == ym } ?? false }
            .sorted { ($0.slot, $0.order) < ($1.slot, $1.order) }
    }

    /// Lanes for notes under the days, so none covers another: each note takes the columns from its first day
    /// for `columns` days (its days, or more when its text is wider), and goes on the first lane free there.
    public static func lanes(_ spans: [(id: String, first: Int, columns: Int)]) -> [String: Int] {
        var ends: [Int] = []
        var out: [String: Int] = [:]
        for s in spans.sorted(by: { ($0.first, $0.id) < ($1.first, $1.id) }) {
            let last = s.first + max(1, s.columns) - 1
            if let lane = ends.firstIndex(where: { $0 < s.first }) {
                ends[lane] = last
                out[s.id] = lane
            } else {
                ends.append(last)
                out[s.id] = ends.count - 1
            }
        }
        return out
    }
}
