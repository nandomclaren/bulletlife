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

    /// Days still to fill: for each habit row, each day of its month up to today, from the day the habit was
    /// written (a habit added mid-month does not owe the days before it), without a mark.
    public static func toFill(_ rows: [Entry], today: String) -> [String] {
        var days = Set<String>()
        for row in rows where !row.slot.isEmpty && !row.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let ym = row.slot
            guard ym.count == 7, ym <= Dates.monthOf(today) else { continue }
            let since = String(row.createdAt.prefix(10))
            for (i, iso) in Dates.monthDays(ym).enumerated() where iso <= today && iso >= since {
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

    public static func pending(_ entries: [Entry], habitLogIds: Set<String>, today: String) -> [Pending] {
        let byLog = Dictionary(grouping: entries.filter { habitLogIds.contains($0.logId) }, by: \.logId)
        return byLog.compactMap { logId, rows in
            let days = toFill(rows, today: today)
            guard let latest = days.last else { return nil }
            return Pending(logId: logId, days: days.count, latest: latest)
        }.sorted { $0.latest > $1.latest }
    }
}
