// The Month page's days in Open items (Fernando), as the Habits collections' days to fill: a day of the current
// month with nothing written in it is owed once it has passed, and today once the evening check-in time comes
// (Close the day's time). Derived, never stored. Only the month of today counts, and only from the first day of it
// with something written (a month started late does not owe its first days); with nothing written all month, only
// today (at the check-in time) is owed.
import Foundation

public enum MonthDays {
    public struct Pending: Equatable, Sendable {
        public var month: String
        public var days: Int
        /// The latest day owed (where a tap takes you).
        public var latest: String
    }

    /// `entries`: the whole notebook (ink not needed). A day is written when any entry in its slot has text.
    public static func toWrite(_ entries: [Entry], today: String, todayDue: Bool = true) -> Pending? {
        let ym = Dates.monthOf(today)
        let logId = Period.month(ym).logId
        let written = Set(
            entries.filter { $0.logId == logId && $0.slot.count == 10 && $0.slot.hasPrefix(ym) }
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .map(\.slot))
        let from = min(written.min() ?? today, today)
        let owed = Dates.monthDays(ym).filter { iso in
            iso >= from && (iso < today || (todayDue && iso == today)) && !written.contains(iso)
        }
        guard let latest = owed.last else { return nil }
        return Pending(month: ym, days: owed.count, latest: latest)
    }
}
