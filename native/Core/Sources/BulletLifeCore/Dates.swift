// Calendar math on plain ISO strings ('2026-10-18'), in local time, as in the PWA (src/dates.ts).
// Periods: day '2026-10-18', week '2026-W43', month '2026-10', year '2026'.
import Foundation

/// 0 = Sunday … 6 = Saturday (the PWA's numbering).
public typealias Weekday = Int

public enum Dates {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static var isoCalendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    public static func toIso(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(pad(c.month!))-\(pad(c.day!))"
    }

    /// Noon of that day: immune to daylight-saving edges.
    public static func fromIso(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        let c = DateComponents(year: parts[0], month: parts.count > 1 ? parts[1] : 1, day: parts.count > 2 ? parts[2] : 1, hour: 12)
        return calendar.date(from: c)!
    }

    public static func today(_ now: Date = Date()) -> String { toIso(now) }

    public static func addDays(_ iso: String, _ n: Int) -> String {
        toIso(calendar.date(byAdding: .day, value: n, to: fromIso(iso))!)
    }

    public static func monthOf(_ iso: String) -> String { String(iso.prefix(7)) }
    public static func yearOf(_ iso: String) -> String { String(iso.prefix(4)) }

    /// 0 = Sunday.
    public static func weekday(_ iso: String) -> Weekday {
        calendar.component(.weekday, from: fromIso(iso)) - 1
    }

    public static func daysInMonth(_ ym: String) -> Int {
        calendar.range(of: .day, in: .month, for: fromIso("\(ym)-01"))!.count
    }

    public static func addMonths(_ ym: String, _ n: Int) -> String {
        monthOf(toIso(calendar.date(byAdding: .month, value: n, to: fromIso("\(ym)-01"))!))
    }

    public static func monthDays(_ ym: String) -> [String] {
        (1...daysInMonth(ym)).map { "\(ym)-\(pad($0))" }
    }

    public static func weekStart(_ iso: String, firstDay: Weekday) -> String {
        addDays(iso, -((weekday(iso) - firstDay + 7) % 7))
    }

    /// ISO-8601 week number and week-year of a date.
    public static func isoWeek(_ iso: String) -> (year: Int, week: Int) {
        let c = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: fromIso(iso))
        return (c.yearForWeekOfYear!, c.weekOfYear!)
    }

    /// Week key for the week containing `iso`. Weeks are numbered like ISO weeks; a Sunday-first week takes
    /// the number of the Monday that follows its Sunday.
    public static func weekKey(_ iso: String, firstDay: Weekday) -> String {
        let start = weekStart(iso, firstDay: firstDay)
        let monday = addDays(start, (1 - firstDay + 7) % 7)
        let w = isoWeek(monday)
        return "\(w.year)-W\(pad(w.week))"
    }

    /// First day of a week key.
    public static func weekKeyStart(_ key: String, firstDay: Weekday) -> String {
        let parts = key.components(separatedBy: "-W")
        let y = Int(parts[0])!
        let w = Int(parts[1])!
        let jan4 = "\(y)-01-04"
        let mondayW1 = addDays(jan4, -((weekday(jan4) + 6) % 7))
        let monday = addDays(mondayW1, (w - 1) * 7)
        return addDays(monday, -((1 - firstDay + 7) % 7))
    }

    public static func weekDays(_ key: String, firstDay: Weekday) -> [String] {
        let start = weekKeyStart(key, firstDay: firstDay)
        return (0..<7).map { addDays(start, $0) }
    }

    public static func addWeeks(_ key: String, _ n: Int, firstDay: Weekday) -> String {
        weekKey(addDays(weekKeyStart(key, firstDay: firstDay), n * 7), firstDay: firstDay)
    }

    public static func weekNumber(_ key: String) -> Int {
        Int(key.components(separatedBy: "-W")[1]) ?? 0
    }
}

/// A period page of the notebook: what it is called and which days it covers. Time pages need no stored
/// row (the PWA's periodLog): their id is derived from the date, so two offline devices never duplicate one.
public enum Period: Hashable, Sendable {
    case day(String)
    case week(String)
    case month(String)
    case year(String)

    public var logId: String {
        switch self {
        case .day(let k): return "daily:\(k)"
        case .week(let k): return "weekly:\(k)"
        case .month(let k): return "monthly:\(k)"
        case .year(let k): return "future:\(k)"
        }
    }

    public var kind: LogKind {
        switch self {
        case .day: return .daily
        case .week: return .weekly
        case .month: return .monthly
        case .year: return .future
        }
    }

    public func start(firstDay: Weekday) -> String {
        switch self {
        case .day(let k): return k
        case .week(let k): return Dates.weekKeyStart(k, firstDay: firstDay)
        case .month(let k): return "\(k)-01"
        case .year(let k): return "\(k)-01-01"
        }
    }

    public func end(firstDay: Weekday) -> String {
        switch self {
        case .day(let k): return k
        case .week: return Dates.addDays(start(firstDay: firstDay), 6)
        case .month(let k): return "\(k)-\(Dates.pad(Dates.daysInMonth(k)))"
        case .year(let k): return "\(k)-12-31"
        }
    }

    /// The period before (-1) or after (+1) at the same level.
    public func moved(_ n: Int, firstDay: Weekday) -> Period {
        switch self {
        case .day(let k): return .day(Dates.addDays(k, n))
        case .week(let k): return .week(Dates.addWeeks(k, n, firstDay: firstDay))
        case .month(let k): return .month(Dates.addMonths(k, n))
        case .year(let k): return .year(String((Int(k) ?? 2026) + n))
        }
    }

    /// The period at this level that contains a day.
    public static func containing(_ iso: String, like level: Period, firstDay: Weekday) -> Period {
        switch level {
        case .day: return .day(iso)
        case .week: return .week(Dates.weekKey(iso, firstDay: firstDay))
        case .month: return .month(Dates.monthOf(iso))
        case .year: return .year(Dates.yearOf(iso))
        }
    }

    /// The day the page is looked at from (CLAUDE.md 5.1): today when the period holds it, else its first day.
    /// Changing level goes to the period that holds it.
    public func anchor(today: String, firstDay: Weekday) -> String {
        let a = start(firstDay: firstDay)
        return today >= a && today <= end(firstDay: firstDay) ? today : a
    }

    /// The navigation trail from the anchor, coarsest first: Year › Month › Week › Day (a week can span two
    /// months; the month shown is the anchor's). Levels turned off are left out (the Year is always on).
    public static func trail(anchor: String, firstDay: Weekday, active: ActiveLogs = ActiveLogs()) -> [Period] {
        var out: [Period] = [.year(Dates.yearOf(anchor))]
        if active.monthly { out.append(.month(Dates.monthOf(anchor))) }
        if active.weekly { out.append(.week(Dates.weekKey(anchor, firstDay: firstDay))) }
        if active.daily { out.append(.day(anchor)) }
        return out
    }

    /// Same level as another period (Day and Day, Week and Week…).
    public func sameLevel(_ other: Period) -> Bool {
        switch (self, other) {
        case (.day, .day), (.week, .week), (.month, .month), (.year, .year): return true
        default: return false
        }
    }
}

/// The time logs turned on (CLAUDE.md 3.2): Year and Index are always on, and at least one of Month, Week and
/// Day stays on (migrating needs a source and a destination).
public struct ActiveLogs: Equatable, Sendable {
    public var monthly: Bool
    public var weekly: Bool
    public var daily: Bool

    public init(monthly: Bool = true, weekly: Bool = true, daily: Bool = true) {
        self.monthly = monthly
        self.weekly = weekly
        self.daily = daily
        if !monthly && !weekly && !daily { self.daily = true }
    }

    /// Whether this one can be turned off (it isn't the last one on).
    public func canTurnOff(_ kind: LogKind) -> Bool {
        let on = [monthly, weekly, daily].filter { $0 }.count
        switch kind {
        case .monthly: return !monthly || on > 1
        case .weekly: return !weekly || on > 1
        case .daily: return !daily || on > 1
        default: return false
        }
    }

    /// The finest log on, holding a day: where the app opens and where Today goes.
    public func finest(_ iso: String, firstDay: Weekday) -> Period {
        if daily { return .day(iso) }
        if weekly { return .week(Dates.weekKey(iso, firstDay: firstDay)) }
        return .month(Dates.monthOf(iso))
    }

    /// Going down from a Month's day number: the Day, or the Week when days are off.
    public func below(month day: String, firstDay: Weekday) -> Period? {
        daily ? .day(day) : weekly ? .week(Dates.weekKey(day, firstDay: firstDay)) : nil
    }

    /// Going down from a Year's month name: the Month, or the Week of its first day when months are off.
    public func below(year ym: String, firstDay: Weekday) -> Period {
        monthly ? .month(ym) : finest("\(ym)-01", firstDay: firstDay)
    }

    /// Whether a period's level is on (Year always).
    public func isOn(_ p: Period) -> Bool {
        switch p {
        case .day: return daily
        case .week: return weekly
        case .month: return monthly
        case .year: return true
        }
    }
}
