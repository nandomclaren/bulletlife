// Pasting entries back into a page (src/editor/paste.ts). What the app copies (the exact lines, alongside rich
// and plain text) or exports (Markdown, plain text with glyphs) is read back as entries with their type, state,
// signifiers and indentation, instead of literal glyphs. Pasting is the user's own gesture onto the page they
// are on, so it creates entries as typing would (CLAUDE.md 2).
import Foundation

public enum Paste {
    /// The pasteboard type that carries the exact lines copied from an editor.
    public static let linesType = "app.bulletlife.lines"

    struct Copied: Codable {
        var type: EntryType
        var state: EntryState
        var indent: Int
        var collapsed: Bool
        var priority: Bool
        var inspiration: Bool
        var explore: Bool
        var text: String
    }

    public static func json(_ lines: [Line]) -> Data {
        let copied = lines.map {
            Copied(
                type: $0.type, state: $0.state, indent: $0.indent, collapsed: $0.collapsed, priority: $0.priority,
                inspiration: $0.inspiration, explore: $0.explore, text: $0.text)
        }
        return (try? JSONEncoder().encode(copied)) ?? Data()
    }

    /// Exact lines from the editor, with fresh ids.
    public static func fromJSON(_ data: Data) -> [Line]? {
        guard let copied = try? JSONDecoder().decode([Copied].self, from: data), !copied.isEmpty else { return nil }
        return copied.map {
            Line(
                type: $0.type, state: $0.state, indent: max(0, $0.indent), collapsed: $0.collapsed, priority: $0.priority,
                inspiration: $0.inspiration, explore: $0.explore, text: $0.text)
        }
    }

    // MARK: Text

    static func groups(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// Leading signifiers as the exporter writes them: "*", "!", "👁", then a space.
    static func item(_ type: EntryType, _ state: EntryState, _ indent: Int, _ body: String) -> Line {
        var rest = body
        var p = false, i = false, e = false
        if let sig = groups("^((?:[*!]|👁)+) ", body)?[1] {
            p = sig.contains("*")
            i = sig.contains("!")
            e = sig.contains("👁")
            rest = String(body.dropFirst(sig.count + 1))
        }
        return Line(type: type, state: state, indent: indent, priority: p, inspiration: i, explore: e, text: rest)
    }

    static let box: [String: EntryState] = [" ": .open, "x": .done, "X": .done, ">": .migrated, "<": .scheduled]
    static let dot: [String: EntryState] = ["x": .done, ">": .migrated, "<": .scheduled]
    static let glyph: [String: (EntryType, EntryState)] = [
        "•": (.task, .open), "○": (.event, .open), "–": (.note, .open), "×": (.task, .done), ">": (.task, .migrated), "<": (.task, .scheduled),
    ]

    static func parseLine(_ raw: String, glyphs: Bool) -> (line: Line, known: Bool) {
        // Notes apps leave hidden markers; a folded item is marked <!-- {"fold":true} -->.
        let folded = groups(#"<!--[^>]*"fold"\s*:\s*true[^>]*-->"#, raw) != nil
        let cleaned = (try? NSRegularExpression(pattern: #"\s*<!--.*?-->"#))
            .map { $0.stringByReplacingMatches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length), withTemplate: "") } ?? raw
        var r = parseOne(cleaned, glyphs: glyphs)
        if folded { r.line.collapsed = true }
        return r
    }

    static func parseOne(_ raw: String, glyphs: Bool) -> (line: Line, known: Bool) {
        let lead = String(raw.prefix { $0 == " " || $0 == "\t" })
        let indent = lead.replacingOccurrences(of: "\t", with: "  ").count / 2
        var s = String(raw.dropFirst(lead.count))

        if let h = groups("^#{1,6} (.*)$", s) { return (Line(type: .heading, text: h[1]), true) }

        if s.hasPrefix("- ") {
            s = String(s.dropFirst(2))
            // Cancelled: "~~text~~", "~~○ text~~", "~~. text~~", "~~o text~~"
            if let c = groups("^~~(.*)~~$", s) {
                if let m = groups("^(○|o|\\.) (.*)$", c[1]) {
                    return (item(m[1] != "." ? .event : .task, .cancelled, indent, m[2]), true)
                }
                return (item(.task, .cancelled, indent, c[1]), true)
            }
            if let b = groups("^\\[([ xX<>])\\] (.*)$", s) {
                if let ev = groups("^○ (.*)$", b[2]) { return (item(.event, box[b[1]] ?? .open, indent, ev[1]), true) }
                return (item(.task, box[b[1]] ?? .open, indent, b[2]), true)
            }
            if let ev = groups("^○ (.*)$", s) { return (item(.event, .open, indent, ev[1]), true) }
            // Dot notation: "x t", "x o t", "> t", ". t", "o t", "- note"
            if let d = groups("^([x<>]) (?:(o) )?(.*)$", s) {
                return (item(d[2].isEmpty ? .task : .event, dot[d[1]] ?? .done, indent, d[3]), true)
            }
            if let d = groups("^(\\.|o|-) (.*)$", s) {
                return (item(d[1] == "." ? .task : d[1] == "o" ? .event : .note, .open, indent, d[2]), true)
            }
            return (item(.note, .open, indent, s), true)
        }

        // Arrows written as text: "-> item" migrated, "<- item" scheduled.
        if let a = groups("^(->|→|<-|←) (.*)$", s) {
            return (item(.task, a[1] == "->" || a[1] == "→" ? .migrated : .scheduled, indent, a[2]), true)
        }

        if let g = groups("^([•○–×<>]) (.*)$", s), glyphs || !"<>".contains(g[1]), let (type, state) = glyph[g[1]] {
            let struck = g[2].contains("\u{0336}")
            let text = g[2].replacingOccurrences(of: "\u{0336}", with: "")
            return (item(type, struck && type != .note ? .cancelled : state, indent, text), true)
        }
        return (Line(indent: indent, text: s), false)
    }

    /// Pasted text read as entries when it looks like something the app exported (or a notes app's Markdown).
    /// Nil for ordinary text, which keeps the plain paste.
    public static func fromText(_ text: String) -> [Line]? {
        var rows = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        while rows.last?.isEmpty == true { rows.removeLast() }
        // ">" and "<" alone (email quotes) only count next to the other glyphs.
        let glyphs = rows.contains { groups("^[ \\t]*[•○–×] ", $0) != nil }
        var kept = rows.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // A pasted page starts with its title ("# Sunday, October 18"); the page here has its own.
        if kept.count > 1, groups("^# \\S", kept[0]) != nil { kept.removeFirst() }
        let parsed = kept.map { parseLine($0, glyphs: glyphs) }
        guard parsed.contains(where: \.known) else { return nil }
        // A heading starts a section: what follows is indented relative to the section, not nested under it.
        var out: [Line] = []
        var section: [Line] = []
        func flush() {
            let min = section.map(\.indent).min() ?? 0
            out += section.map { var l = $0; l.indent -= min; return l }
            section = []
        }
        for (line, _) in parsed {
            if line.type == .heading {
                flush()
                out.append(line)
            } else {
                section.append(line)
            }
        }
        flush()
        return out
    }
}

extension PageEdit {
    /// Pastes entries at the caret, indented from the line they land on: an empty line is replaced, at a line's
    /// start they go before it, in its middle the line is split around them. The caret ends on the last one.
    public static func paste(_ lines: [Line], at: Caret, _ pasted: [Line]) -> Edited {
        guard !pasted.isEmpty else { return Edited(lines: lines, caret: at) }
        var lines = lines
        let line = lines[at.index]
        let fresh = pasted.map { p -> Line in
            var l = p
            l.indent += line.indent
            return l
        }
        let head = line.text.u16Prefix(at.offset)
        let tail = line.text.u16Suffix(from: at.offset)
        var lastIndex: Int
        if line.text.isEmpty && line.ink == nil {
            lines.replaceSubrange(at.index...at.index, with: fresh)
            lastIndex = at.index + fresh.count - 1
        } else if head.isEmpty {
            lines.insert(contentsOf: fresh, at: at.index)
            lastIndex = at.index + fresh.count - 1
        } else {
            lines[at.index].text = head
            let rest = tail.isEmpty ? [] : [Line(type: line.type, indent: line.indent, text: tail)]
            lines.insert(contentsOf: fresh + rest, at: at.index + 1)
            lastIndex = at.index + fresh.count
        }
        // The last pasted line that is not folded away.
        let hidden = Outline.hidden(lines)
        while lastIndex > 0 && hidden[lastIndex] { lastIndex -= 1 }
        return commit(lines, before: lines, caret: Caret(index: lastIndex, offset: lines[lastIndex].text.u16))
    }
}
