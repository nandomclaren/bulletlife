// The line model of a page (src/editor/lines.ts): a page is a flat list of lines with an indent level;
// parents are derived (the nearest previous line with a smaller indent), which maps 1:1 to Entry.
import Foundation

public struct Line: Equatable, Identifiable, Sendable {
    public var id: String
    public var type: EntryType
    public var state: EntryState
    public var indent: Int
    public var collapsed: Bool
    public var priority: Bool
    public var inspiration: Bool
    public var explore: Bool
    public var text: String
    public var ink: Ink?

    public init(
        id: String = ULID.make(), type: EntryType = .text, state: EntryState = .open, indent: Int = 0, collapsed: Bool = false,
        priority: Bool = false, inspiration: Bool = false, explore: Bool = false, text: String = "", ink: Ink? = nil
    ) {
        self.id = id
        self.type = type
        self.state = state
        self.indent = indent
        self.collapsed = collapsed
        self.priority = priority
        self.inspiration = inspiration
        self.explore = explore
        self.text = text
        self.ink = ink
    }
}

// MARK: - Rapid logging

public struct Prefixes: Equatable, Sendable {
    public var task = "."
    public var event = "o."
    public var note = "-"
    public var heading = "#"
    public var priority = "*"
    public init() {}
}

public struct PrefixMatch: Equatable, Sendable {
    public var type: EntryType
    public var priority: Bool
    /// Characters consumed, including the trailing space.
    public var length: Int
}

/// Bullet glyphs work as prefixes too: handwriting turns a written dot into "•" or "·", a dash into "–".
let glyphPrefixes: [String: EntryType] = ["•": .task, "·": .task, "●": .task, "○": .event, "◦": .event, "–": .note, "—": .note]

public enum Rapid {
    /// A rapid-logging prefix typed up to and including its trailing space: ". ", "o. ", "- ", "# ", optionally
    /// preceded by "* " for priority. "* " alone marks priority on the current type.
    public static func match(_ textBeforeCaret: String, prefixes: Prefixes = Prefixes()) -> PrefixMatch? {
        guard textBeforeCaret.hasSuffix(" ") else { return nil }
        var rest = textBeforeCaret
        var priority = false
        var consumed = 0
        let prio = "\(prefixes.priority) "
        if rest.hasPrefix(prio) {
            priority = true
            rest = String(rest.dropFirst(prio.count))
            consumed += prio.count
        }
        let kinds: [(EntryType, String)] = [(.event, prefixes.event), (.task, prefixes.task), (.note, prefixes.note), (.heading, prefixes.heading)]
        for (type, p) in kinds where rest == "\(p) " {
            if type == .heading && priority { return nil }
            return PrefixMatch(type: type, priority: priority, length: consumed + p.count + 1)
        }
        if rest.count == 2, let glyph = glyphPrefixes[String(rest.dropLast())] {
            return PrefixMatch(type: glyph, priority: priority, length: consumed + 2)
        }
        if priority && rest.isEmpty { return PrefixMatch(type: .text, priority: true, length: consumed) }
        return nil
    }

    /// A prefix at the start of a whole line of text (not just what was typed so far).
    public static func leading(_ text: String, prefixes: Prefixes = Prefixes()) -> PrefixMatch? {
        let chars = Array(text)
        guard chars.count >= 2 else { return nil }
        for k in 2...min(chars.count, 6) where chars[k - 1] == " " {
            if let m = match(String(chars[0..<k]), prefixes: prefixes), m.length == k { return m }
        }
        return nil
    }
}

// MARK: - States and glyphs

public enum States {
    public static func stateful(_ type: EntryType, eventStates: Bool) -> Bool {
        type == .task || (type == .event && eventStates)
    }

    /// Tap cycle: open → done → cancelled → open. Migrated and scheduled go back to open.
    public static func next(_ state: EntryState) -> EntryState {
        switch state {
        case .open: return .done
        case .done: return .cancelled
        default: return .open
        }
    }

    /// The bullet drawn for a line; "" for plain text and headings. The done mark follows Settings (× or ✓).
    public static func glyph(_ type: EntryType, _ state: EntryState, eventStates: Bool, doneMark: String = "×") -> String {
        switch type {
        case .note: return "–"
        case .text, .heading: return ""
        case .task, .event:
            if stateful(type, eventStates: eventStates) {
                switch state {
                case .done: return doneMark
                case .migrated: return ">"
                case .scheduled: return "<"
                default: break
                }
            }
            return type == .task ? "•" : "○"
        }
    }
}

// MARK: - Tree helpers

public enum Outline {
    public static func parentIds(_ lines: [Line]) -> [String?] {
        var stack: [(indent: Int, id: String)] = []
        return lines.map { l in
            while let top = stack.last, top.indent >= l.indent { stack.removeLast() }
            let parent = stack.last?.id
            stack.append((l.indent, l.id))
            return parent
        }
    }

    public static func hasChildren(_ lines: [Line], _ i: Int) -> Bool {
        i + 1 < lines.count && lines[i + 1].indent > lines[i].indent
    }

    /// Index just past the subtree of line i.
    public static func subtreeEnd(_ lines: [Line], _ i: Int) -> Int {
        var j = i + 1
        while j < lines.count && lines[j].indent > lines[i].indent { j += 1 }
        return j
    }

    /// Lines hidden because an ancestor is collapsed.
    public static func hidden(_ lines: [Line]) -> [Bool] {
        var out = Array(repeating: false, count: lines.count)
        for i in lines.indices where !out[i] && lines[i].collapsed {
            for j in (i + 1)..<subtreeEnd(lines, i) { out[j] = true }
        }
        return out
    }

    /// A leading list number ("1." or "2)") followed by a space.
    public static func numberPrefix(_ text: String) -> String? {
        var digits = ""
        for ch in text {
            if ch.isASCII, ch.isNumber, digits.count < 3 {
                digits.append(ch)
                continue
            }
            if !digits.isEmpty, ch == "." || ch == ")" {
                let rest = text.dropFirst(digits.count + 1)
                return rest.first.map { $0.isWhitespace } == true ? digits + String(ch) : nil
            }
            return nil
        }
        return nil
    }

    /// The color group of each line: inherited from the outermost bulleted ancestor (children take the
    /// color of their root, keeping their own glyph); a numbered plain line colors like a task.
    public static func colorTypes(_ lines: [Line]) -> [EntryType] {
        var stack: [(indent: Int, color: EntryType)] = []
        return lines.map { l in
            while let top = stack.last, top.indent >= l.indent { stack.removeLast() }
            let root = stack.first { $0.color == .task || $0.color == .event || $0.color == .note }
            let own: EntryType = l.type == .text && numberPrefix(l.text) != nil ? .task : l.type
            let color = root?.color ?? own
            stack.append((l.indent, color))
            return color
        }
    }

    /// A page's entries as lines, in order, with indents from the parent links (src/data/convert.ts).
    public static func lines(from entries: [Entry]) -> [Line] {
        var depth: [String: Int] = [:]
        return entries.sorted { $0.order < $1.order }.map { e in
            let d = e.parentId.flatMap { depth[$0] }.map { $0 + 1 } ?? 0
            depth[e.id] = d
            return Line(
                id: e.id, type: e.type, state: e.state, indent: d, collapsed: e.collapsed,
                priority: e.signifiers.contains(.priority), inspiration: e.signifiers.contains(.inspiration),
                explore: e.signifiers.contains(.explore), text: e.text, ink: (e.ink?.strokes.isEmpty == false) ? e.ink : nil
            )
        }
    }

    /// What to write so storage matches a page's lines: changed or new entries, and ids to remove.
    /// Existing order keys are kept while still in order, so only moved or new lines are written.
    public static func diff(
        lines: [Line], existing: [Entry], logId: String, slot: String, now: String
    ) -> (put: [Entry], remove: [String]) {
        let byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let parents = parentIds(lines)
        let orders = OrderKey.assign(ids: lines.map(\.id), existing: byId.mapValues(\.order))
        var put: [Entry] = []
        for (i, l) in lines.enumerated() {
            var signifiers: [Signifier] = []
            if l.priority { signifiers.append(.priority) }
            if l.inspiration { signifiers.append(.inspiration) }
            if l.explore { signifiers.append(.explore) }
            var e = byId[l.id] ?? Entry(id: l.id, logId: logId, slot: slot, order: orders[i], createdAt: now, updatedAt: now)
            let before = e
            e.parentId = parents[i]
            e.order = orders[i]
            e.type = l.type
            e.state = l.state
            e.text = l.text
            e.signifiers = signifiers
            e.collapsed = l.collapsed
            e.ink = l.ink
            // Marked > or <: pending until the user confirms they wrote it at the destination (CLAUDE.md 4.3).
            if l.state == .migrated || l.state == .scheduled {
                e.placement = before.placement ?? Placement(status: .pending)
            } else {
                e.placement = nil
            }
            // The date written as "due:YYYY-MM-DD" in the text, kept as a field for queries.
            e.dueDate = Due.of(l.text)
            if byId[l.id] == nil || e != before {
                e.updatedAt = now
                put.append(e)
            }
        }
        let kept = Set(lines.map(\.id))
        return (put, existing.map(\.id).filter { !kept.contains($0) })
    }
}
