// What the page editor does to the line model when the structure changes (src/editor/LineEditor.tsx and
// lines.ts): Enter, Backspace at a line start, deleting across lines, inserting text with line breaks,
// indenting, and numbered lists. Pure functions on [Line], so the native editor behaves like the PWA's and
// the rules are tested here. Offsets are UTF-16 units, as in the PWA and UIKit (NSRange).
import Foundation

/// A place in the page: a line and an offset in its text (UTF-16 units).
public struct Caret: Equatable, Sendable {
    public var index: Int
    public var offset: Int
    public init(index: Int, offset: Int) {
        self.index = index
        self.offset = offset
    }
}

/// The page after an edit, and where the caret goes.
public struct Edited: Equatable, Sendable {
    public var lines: [Line]
    public var caret: Caret
    public init(lines: [Line], caret: Caret) {
        self.lines = lines
        self.caret = caret
    }
}

extension String {
    /// Length in UTF-16 units.
    var u16: Int { (self as NSString).length }
    func u16Prefix(_ n: Int) -> String { (self as NSString).substring(to: Swift.max(0, Swift.min(n, u16))) }
    func u16Suffix(from n: Int) -> String { (self as NSString).substring(from: Swift.max(0, Swift.min(n, u16))) }
}

// MARK: - Lists and indentation (lines.ts)

extension Outline {
    /// The list number that follows: "2." → "3.", "9)" → "10)".
    public static func nextNumber(_ prefix: String) -> String {
        "\((Int(prefix.dropLast()) ?? 0) + 1)\(prefix.last.map(String.init) ?? ".")"
    }

    /// Items that open a list or were typed out of sequence (e.g. "10." after "2."): the user chose these
    /// numbers, so renumbering keeps them and counts on from them. Computed on the lines before an edit.
    public static func listRestarts(_ lines: [Line]) -> Set<String> {
        var restarts = Set<String>()
        var last: [Int: Int?] = [:]
        for l in lines {
            for d in last.keys where d > l.indent { last[d] = nil }
            guard let num = numberPrefix(l.text) else {
                last[l.indent] = .some(nil)
                continue
            }
            let n = Int(num.dropLast()) ?? 0
            let prev = last[l.indent] ?? nil
            if prev == nil || n != prev! + 1 { restarts.insert(l.id) }
            last[l.indent] = .some(n)
        }
        return restarts
    }

    /// Renumbers numbered lists after a structural edit (Fernando's exception to "the app never changes
    /// entries by itself", CLAUDE.md 2.1): each item of a run of numbered siblings gets the previous number + 1,
    /// except items in `keep` (numbers the user chose), which stay and the count goes on from them. A sibling
    /// without a number ends the run. Returns the indexes it changed.
    @discardableResult
    public static func renumberLists(_ lines: inout [Line], keep: Set<String> = []) -> [Int] {
        var changed: [Int] = []
        var last: [Int: (n: Int, sep: String)?] = [:]
        for i in lines.indices {
            let l = lines[i]
            for d in last.keys where d > l.indent { last[d] = nil }
            guard let num = numberPrefix(l.text) else {
                last[l.indent] = .some(nil)
                continue
            }
            if let prevEntry = last[l.indent], let prev = prevEntry, !keep.contains(l.id) {
                let want = "\(prev.n + 1)\(prev.sep)"
                if want != num {
                    lines[i].text = want + l.text.u16Suffix(from: num.u16)
                    changed.append(i)
                }
                last[l.indent] = .some((prev.n + 1, prev.sep))
            } else {
                last[l.indent] = .some((Int(num.dropLast()) ?? 0, String(num.last!)))
            }
        }
        return changed
    }

    /// After an indent/outdent: an item that now opens a list among its siblings starts at 1.
    public static func restartIfFirst(_ lines: inout [Line], _ i: Int) {
        guard let num = numberPrefix(lines[i].text) else { return }
        var j = i - 1
        while j >= 0 && lines[j].indent >= lines[i].indent {
            if lines[j].indent == lines[i].indent {
                if numberPrefix(lines[j].text) != nil { return }  // continues an existing list
                break
            }
            j -= 1
        }
        lines[i].text = "1\(num.last!)" + lines[i].text.u16Suffix(from: num.u16)
    }

    /// Indent (+1) or outdent (-1) lines from...to together with the subtree of the last one. Returns the new
    /// indents, or nil when not allowed.
    public static func shiftIndent(_ lines: [Line], from: Int, to: Int, delta: Int) -> [Int]? {
        let end = subtreeEnd(lines, to)
        var indents = lines.map(\.indent)
        if delta == 1 && lines[from].indent + 1 > maxIndent(lines, from) { return nil }
        if delta == -1 && lines[from].indent == 0 { return nil }
        for i in from..<end { indents[i] = Swift.max(0, indents[i] + delta) }
        return indents
    }

    /// Type of a new line created by Enter at the end of a line of this type.
    public static func continuationType(_ from: EntryType) -> EntryType {
        from == .heading ? .text : from
    }
}

// MARK: - Structural edits (LineEditor.tsx)

public enum PageEdit {
    /// Handwriting is never deleted from Type mode: only the Pen eraser removes strokes.
    static func handwritten(_ l: Line) -> Bool { l.ink?.hasWriting ?? false }

    /// Renumbers lists, keeping the numbers the user chose before the edit (`before`).
    static func commit(_ lines: [Line], before: [Line], caret: Caret) -> Edited {
        var out = lines
        Outline.renumberLists(&out, keep: Outline.listRestarts(before))
        return Edited(lines: out, caret: caret)
    }

    /// Deletes text from `start` to `end`. Lines in the range holding handwriting stay (their text cleared),
    /// and a last line holding some keeps its remaining text instead of joining the first.
    public static func deleteRange(_ lines: [Line], from start: Caret, to end: Caret) -> Edited {
        var lines = lines
        let b = lines[end.index]
        let keepB = end.index > start.index && handwritten(b)
        let tail = b.text.u16Suffix(from: end.offset)
        lines[start.index].text = lines[start.index].text.u16Prefix(start.offset) + (keepB ? "" : tail)
        var kept = lines[(start.index + 1)..<end.index].filter(handwritten).map { l -> Line in
            var l = l
            l.text = ""
            return l
        }
        if keepB {
            var last = b
            last.text = tail
            kept.append(last)
        }
        lines.replaceSubrange((start.index + 1)...end.index, with: kept)
        return Edited(lines: lines, caret: start)
    }

    /// Inserts text (which may hold line breaks: each starts a new line like the one it is typed in).
    public static func insertText(_ lines: [Line], at: Caret, _ text: String) -> Edited {
        var lines = lines
        let parts = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let line = lines[at.index]
        let tail = line.text.u16Suffix(from: at.offset)
        lines[at.index].text = line.text.u16Prefix(at.offset) + parts[0]
        var caret = Caret(index: at.index, offset: lines[at.index].text.u16)
        for part in parts.dropFirst() {
            let fresh = Line(type: Outline.continuationType(line.type), indent: line.indent, text: part)
            lines.insert(fresh, at: caret.index + 1)
            caret = Caret(index: caret.index + 1, offset: part.u16)
        }
        lines[caret.index].text += tail
        return commit(lines, before: lines, caret: caret)
    }

    /// Enter. On an empty bulleted line: outdents it, or at level 0 takes its bullet away. On an empty list
    /// item ("3. " alone): ends the list. At the start of a line: a new line above. Otherwise splits the line;
    /// an open parent gets a new first child, a collapsed one a next sibling after its hidden children; a
    /// numbered item's new sibling gets the next number.
    public static func enter(_ lines: [Line], at: Caret) -> Edited {
        let before = lines
        var lines = lines
        let i = at.index
        let line = lines[i]
        if line.text.isEmpty && line.type != .text {
            if line.indent > 0 {
                if let shifted = shift(lines, from: i, to: i, delta: -1) { lines = shifted }
            } else {
                lines[i].type = .text
                lines[i].state = .open
                clearSignifiers(&lines[i])
            }
            return commit(lines, before: before, caret: at)
        }
        let num = Outline.numberPrefix(line.text)
        if let num, line.text.trimmingCharacters(in: .whitespaces) == num {
            lines[i].text = ""
            return commit(lines, before: before, caret: Caret(index: i, offset: 0))
        }
        if at.offset == 0 && !line.text.isEmpty {
            lines.insert(Line(type: Outline.continuationType(line.type), indent: line.indent), at: i)
            return commit(lines, before: before, caret: Caret(index: i + 1, offset: 0))
        }
        let kids = Outline.hasChildren(lines, i)
        let asChild = kids && !line.collapsed
        let at2 = asChild ? i + 1 : kids ? Outline.subtreeEnd(lines, i) : i + 1
        var fresh =
            asChild
            ? Line(type: lines[i + 1].type == .heading ? .text : lines[i + 1].type, indent: line.indent + 1)
            : Line(type: Outline.continuationType(line.type), indent: line.indent)
        let prefix = num != nil && !asChild ? "\(Outline.nextNumber(num!)) " : ""
        fresh.text = prefix + line.text.u16Suffix(from: at.offset)
        lines[i].text = line.text.u16Prefix(at.offset)
        lines.insert(fresh, at: at2)
        return commit(lines, before: before, caret: Caret(index: at2, offset: prefix.u16))
    }

    /// Backspace at a line start: drops a stray priority mark, outdents, drops the bullet, then joins the line
    /// to the one above. Nil when there is nothing to do (the first line, or a handwritten line, which is
    /// never joined into the one above: its strokes would go).
    public static func backspaceAtStart(_ lines: [Line], at: Caret) -> Edited? {
        let before = lines
        var lines = lines
        let i = at.index
        let line = lines[i]
        if (line.type == .text || line.type == .heading) && line.priority {
            lines[i].priority = false
            return commit(lines, before: before, caret: at)
        }
        if line.indent > 0 {
            if let shifted = shift(lines, from: i, to: i, delta: -1) { lines = shifted }
            return commit(lines, before: before, caret: at)
        }
        if line.type != .text {
            lines[i].type = .text
            lines[i].state = .open
            clearSignifiers(&lines[i])
            return commit(lines, before: before, caret: at)
        }
        if i == 0 || handwritten(line) { return nil }
        let offset = lines[i - 1].text.u16
        let joined = deleteRange(lines, from: Caret(index: i - 1, offset: offset), to: Caret(index: i, offset: 0))
        return commit(joined.lines, before: before, caret: joined.caret)
    }

    /// Indents (+1) or outdents (-1) lines from...to with the subtree of the last; an item that now opens a
    /// list starts at 1, and both lists are renumbered. Nil when not allowed.
    public static func shift(_ lines: [Line], from: Int, to: Int, delta: Int) -> [Line]? {
        guard let indents = Outline.shiftIndent(lines, from: from, to: to, delta: delta) else { return nil }
        var out = lines
        for i in out.indices { out[i].indent = indents[i] }
        Outline.restartIfFirst(&out, from)
        Outline.renumberLists(&out, keep: Outline.listRestarts(lines))
        return out
    }

    /// Deletes one line (from its bullet menu); its children move up one level. A page keeps one line.
    public static func deleteLine(_ lines: [Line], id: String) -> [Line] {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return lines }
        var out = lines
        let end = Outline.subtreeEnd(out, i)
        for j in (i + 1)..<end { out[j].indent = max(0, out[j].indent - 1) }
        out.remove(at: i)
        if out.isEmpty { out.append(Line()) }
        Outline.renumberLists(&out, keep: Outline.listRestarts(lines))
        return out
    }

    static func clearSignifiers(_ l: inout Line) {
        l.priority = false
        l.inspiration = false
        l.explore = false
    }
}
