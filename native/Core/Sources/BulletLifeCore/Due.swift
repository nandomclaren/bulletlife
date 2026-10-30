// Due dates written in the text (CLAUDE.md 3.7, src/editor/due.ts): "due:" followed by a date the user types
// (2026-10-23, 23/10, today, tomorrow, fri, next monday, in 3 days…). Once the word is finished it is stored as
// "due:YYYY-MM-DD" (a written "tomorrow" must not drift) and shown as a small pill.
import Foundation

/// Settings › Date format: how a short date is typed and shown (day or month first).
public enum DateOrder: String, Sendable { case dmy, mdy }

public enum DueStatus: Sendable { case overdue, today, future }

public enum Due {
    static let token = try! NSRegularExpression(pattern: #"\bdue:(\d{4}-\d{2}-\d{2})(?![\w-])"#)

    /// The first due date written in a text.
    public static func of(_ text: String) -> String? {
        let ns = text as NSString
        guard let m = token.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    /// Every stored due token in a text, as (range, date): what the editor draws as a pill.
    public static func tokens(_ text: String) -> [(range: NSRange, iso: String)] {
        let ns = text as NSString
        return token.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ($0.range, ns.substring(with: $0.range(at: 1))) }
    }

    static func valid(_ y: Int, _ m: Int, _ d: Int) -> String? {
        guard (1...12).contains(m), d >= 1 else { return nil }
        let ym = "\(y)-\(Dates.pad(m))"
        guard d <= Dates.daysInMonth(ym) else { return nil }
        return "\(ym)-\(Dates.pad(d))"
    }

    static let days = ["sun(?:day)?", "mon(?:day)?", "tue(?:s|sday)?", "wed(?:nesday)?", "thu(?:r|rs|rsday)?", "fri(?:day)?", "sat(?:urday)?"]
    static let end = #"(?=$|[\s,.;:!?)\]])"#

    static func re(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern, options: .caseInsensitive) }

    typealias Rule = (NSRegularExpression, ([String], String, DateOrder, Weekday) -> String?)

    static let rules: [Rule] = [
        (re(#"^(\d{4})-(\d{1,2})-(\d{1,2})"# + end), { m, _, _, _ in valid(Int(m[1])!, Int(m[2])!, Int(m[3])!) }),
        // A short date, this year. A day/month that only makes sense the other way round is read that way.
        (re(#"^(\d{1,2})[-/.](\d{1,2})"# + end), { m, today, order, _ in
            let y = Int(Dates.yearOf(today))!
            let a = Int(m[1])!, b = Int(m[2])!
            return order == .dmy ? (valid(y, b, a) ?? valid(y, a, b)) : (valid(y, a, b) ?? valid(y, b, a))
        }),
        (re("^(?:today|tod)" + end), { _, today, _, _ in today }),
        (re("^(?:tomorrow|tmrw|tmr|tom)" + end), { _, today, _, _ in Dates.addDays(today, 1) }),
        (re("^(?:yesterday|yday)" + end), { _, today, _, _ in Dates.addDays(today, -1) }),
        (re(#"^next\s+week"# + end), { _, today, _, firstDay in Dates.addDays(Dates.weekStart(today, firstDay: firstDay), 7) }),
        (re(#"^next\s+month"# + end), { _, today, _, _ in "\(Dates.addMonths(Dates.monthOf(today), 1))-01" }),
        (re(#"^in\s+(\d{1,3})\s+(days?|weeks?|months?)"# + end), { m, today, _, _ in
            let n = Int(m[1])!
            let unit = m[2].lowercased()
            if unit.hasPrefix("day") { return Dates.addDays(today, n) }
            if unit.hasPrefix("week") { return Dates.addDays(today, n * 7) }
            let ym = Dates.addMonths(Dates.monthOf(today), n)
            return "\(ym)-\(Dates.pad(min(Int(today.suffix(2))!, Dates.daysInMonth(ym))))"
        }),
        // "fri": the coming Friday (today if it is Friday); "next fri": strictly after today.
        (re(#"^(next\s+)?("# + days.joined(separator: "|") + ")" + end), { m, today, _, _ in
            guard let target = days.firstIndex(where: { re("^\($0)$").firstMatch(in: m[2], range: NSRange(location: 0, length: (m[2] as NSString).length)) != nil })
            else { return nil }
            let diff = (target - Dates.weekday(today) + 7) % 7
            return Dates.addDays(today, diff == 0 && !m[1].isEmpty ? 7 : diff)
        }),
    ]

    /// Reads the date expression at the start of `rest`; nil when it is not (yet) a whole date.
    public static func parse(_ rest: String, today: String, order: DateOrder = .dmy, firstDay: Weekday = 1) -> (iso: String, length: Int)? {
        let ns = rest as NSString
        for (re, date) in rules {
            guard let m = re.firstMatch(in: rest, range: NSRange(location: 0, length: ns.length)) else { continue }
            let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            if let iso = date(groups, today, order, firstDay) { return (iso, m.range.length) }
        }
        return nil
    }

    static let start = try! NSRegularExpression(pattern: #"\bdue:"#, options: .caseInsensitive)
    static let stored = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}(?![\w-])"#)

    /// Turns every finished "due:<expression>" ending at or before `upTo` (UTF-16) into "due:YYYY-MM-DD". Returns
    /// the new text and how far `upTo` moved, or nil if nothing changed.
    public static func resolve(
        _ text: String, today: String, order: DateOrder = .dmy, firstDay: Weekday = 1, upTo: Int? = nil
    ) -> (text: String, shift: Int)? {
        let ns = text as NSString
        let limit = upTo ?? ns.length
        var out = ""
        var last = 0
        var shift = 0
        for m in start.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let from = m.range.location + m.range.length
            let rest = ns.substring(from: from)
            let already = stored.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)) != nil
            if already && ns.substring(with: m.range) == "due:" { continue }
            guard let parsed = parse(rest, today: today, order: order, firstDay: firstDay), from + parsed.length <= limit else { continue }
            let token = "due:\(parsed.iso)"
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + token
            let replacedEnd = from + parsed.length
            shift += (token as NSString).length - (replacedEnd - m.range.location)
            last = replacedEnd
        }
        guard last > 0 else { return nil }
        return (out + ns.substring(from: last), shift)
    }

    public static func status(_ iso: String, today: String) -> DueStatus {
        iso < today ? .overdue : iso == today ? .today : .future
    }

    /// "Today", "Tomorrow", "Yesterday", else "23 Oct" / "Oct 23" (+ the year when it isn't this year).
    public static func label(_ iso: String, today: String, order: DateOrder = .dmy) -> String {
        if iso == today { return "Today" }
        if iso == Dates.addDays(today, 1) { return "Tomorrow" }
        if iso == Dates.addDays(today, -1) { return "Yesterday" }
        let day = String(Int(iso.suffix(2)) ?? 0)
        let month = OpenItems.format(iso, "MMM")
        let base = order == .dmy ? "\(day) \(month)" : "\(month) \(day)"
        return Dates.yearOf(iso) == Dates.yearOf(today) ? base : "\(base) \(Dates.yearOf(iso))"
    }

    // MARK: Sorting a list by date (on request)

    /// A run of sibling bullets (two or more, with two or more dates) that can be sorted by date.
    public struct Run: Equatable, Sendable {
        /// Indexes of the sibling items, in page order.
        public var items: [Int]
        public var sorted: Bool
    }

    static func bulleted(_ l: Line) -> Bool { l.type == .task || l.type == .event || l.type == .note }

    public static func runs(_ lines: [Line]) -> [Run] {
        let parents = Outline.parentIds(lines)
        var seen = Set<Int>()
        var out: [Run] = []
        for (i, l) in lines.enumerated() where !seen.contains(i) && bulleted(l) {
            var items = [i]
            var k = Outline.subtreeEnd(lines, i)
            while k < lines.count && lines[k].indent == l.indent && parents[k] == parents[i] && bulleted(lines[k]) {
                items.append(k)
                k = Outline.subtreeEnd(lines, k)
            }
            items.forEach { seen.insert($0) }
            let dated = items.compactMap { of(lines[$0].text) }
            guard items.count >= 2, dated.count >= 2 else { continue }
            // Offered only when dated items are out of order among themselves; undated ones don't count.
            out.append(Run(items: items, sorted: zip(dated, dated.dropFirst()).allSatisfy { $0 <= $1 }))
        }
        return out
    }

    /// The run sorted by date, nearest first; items without a date last, in their order. Children move with
    /// their item. Only on the user's request (the app never reorders by itself).
    public static func sort(_ lines: [Line], _ run: Run) -> [Line] {
        let blocks = run.items.map { Array(lines[$0..<Outline.subtreeEnd(lines, $0)]) }
        let key = { (b: [Line]) in of(b[0].text) ?? "\u{FFFF}" }
        let sorted = blocks.enumerated().sorted { a, b in
            key(a.element) != key(b.element) ? key(a.element) < key(b.element) : a.offset < b.offset
        }.flatMap(\.element)
        let start = run.items[0]
        let end = Outline.subtreeEnd(lines, run.items[run.items.count - 1])
        return Array(lines[..<start]) + sorted + Array(lines[end...])
    }
}
