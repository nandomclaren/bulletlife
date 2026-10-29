// A page in Pen mode, as data (the PWA's PenSheet and repo.ts ink operations, without the screen): how the
// page's lines stack on the ruled sheet, and what writing or erasing a stroke does to them. The screen
// (PencilKit) draws what this computes and reports what the pen did.
import Foundation

/// A stroke as the sheet sees it: where it is on the page (its owner and index), and its points in page
/// coordinates (y from the top of the sheet, not of its entry).
public struct PageStroke: Equatable, Sendable {
    public var entryId: String
    public var index: Int
    public var stroke: Stroke

    public init(entryId: String, index: Int, stroke: Stroke) {
        self.entryId = entryId
        self.index = index
        self.stroke = stroke
    }
}

public enum InkPage {
    /// A line shown as typed text in Pen mode. Handwriting that has been transcribed stays handwriting (the
    /// ink is the original, the text its transcription), even after its text was corrected in Type mode.
    public static func isTyped(_ l: Line) -> Bool {
        if let ink = l.ink, ink.hasWriting, ink.tx != nil { return false }
        if !l.text.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return l.type != .text && !(l.ink?.hasWriting ?? false)
    }

    /// Handwritten lines whose transcription was deleted in Type mode: Type mode leaves them out (from the next
    /// time the page opens); Pen mode still shows their ink.
    public static func erasedInType(_ lines: [Line]) -> Set<String> {
        Set(lines.filter { l in
            guard let ink = l.ink, ink.hasWriting, ink.tx != nil else { return false }
            return l.text.trimmingCharacters(in: .whitespaces).isEmpty
        }.map(\.id))
    }

    /// How the visible lines stack on the sheet: each takes whole ruled rows, as many as its typed text needs
    /// (`typedRows`, measured by the screen) or its ink covers, at least one.
    public static func blocks(_ lines: [Line], typedRows: (Line) -> Int) -> [PlacedBlock] {
        let hidden = Outline.hidden(lines)
        var top: Double = 0
        var out: [PlacedBlock] = []
        for (i, l) in lines.enumerated() where !hidden[i] {
            let typed = isTyped(l)
            let rows = max(1, typed ? typedRows(l) : 0, l.ink?.rows ?? 0)
            out.append(PlacedBlock(id: l.id, top: top, height: Double(rows) * inkRow, typed: typed, strokes: l.ink?.strokes ?? []))
            top += Double(rows) * inkRow
        }
        return out
    }

    public static func contentEnd(_ blocks: [PlacedBlock]) -> Double {
        blocks.last.map { $0.top + $0.height } ?? 0
    }

    /// Every stroke of the page in page coordinates, in drawing order (the order the screen draws them).
    public static func strokes(_ blocks: [PlacedBlock]) -> [PageStroke] {
        blocks.flatMap { b in
            b.strokes.enumerated().map { i, s in
                var moved = s
                moved.p = s.p.enumerated().map { j, v in j % 3 == 1 ? v + b.top : v }
                return PageStroke(entryId: b.id, index: i, stroke: moved)
            }
        }
    }

    /// Files a new stroke (page coordinates) the way `placement` says: on an entry's ruled line, or in a new
    /// entry (after blank lines for ruled lines skipped, as on paper). Returns the lines and the entry written.
    public static func add(_ stroke: Stroke, placement: InkPlacement, to lines: [Line]) -> (lines: [Line], entryId: String) {
        var local = stroke
        local.p = stroke.p.enumerated().map { i, v in i % 3 == 1 ? v - placement.top : v }
        var lines = lines
        switch placement {
        case .join(let id, let r, _, let absorb):
            local.r = stroke.k == .writing ? r : 0
            if let i = lines.firstIndex(where: { $0.id == id }) {
                // Keeps what the transcription knew (tx, n) and a drawing's view.
                var ink = lines[i].ink ?? Ink(strokes: [])
                ink.strokes.append(local)
                lines[i].ink = ink
            }
            // The blank line written on goes: the paragraph above took that ruled line.
            if let absorb, let j = lines.firstIndex(where: { $0.id == absorb }),
                lines[j].text.trimmingCharacters(in: .whitespaces).isEmpty, lines[j].ink == nil, !Outline.hasChildren(lines, j)
            {
                lines.remove(at: j)
            }
            return (lines, id)
        case .new(let after, let blanks, _):
            local.r = 0
            let fresh = Line(ink: Ink(strokes: [local]))
            let added = (0..<blanks).map { _ in Line() } + [fresh]
            let at = after.flatMap { a in lines.firstIndex { $0.id == a } }.map { $0 + 1 } ?? lines.count
            lines.insert(contentsOf: added, at: at)
            return (lines, fresh.id)
        }
    }

    /// The eraser took these strokes (entry id → stroke indexes). A transcription goes with the handwriting it
    /// came from (a typed correction stays); an emptied line stays as a blank ruled line, so nothing below
    /// moves up, except the last line of the page, which goes.
    public static func erase(_ hits: [String: Set<Int>], from lines: [Line]) -> [Line] {
        var lines = lines
        for (id, gone) in hits {
            guard let i = lines.firstIndex(where: { $0.id == id }), var ink = lines[i].ink else { continue }
            let transcribed = ink.tx != nil && lines[i].text == ink.tx
            ink.strokes = ink.strokes.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            if !ink.hasWriting && transcribed {
                lines[i].text = ""
                lines[i].type = .text
                lines[i].state = .open
            }
            lines[i].ink = ink.strokes.isEmpty ? nil : ink
        }
        while let last = lines.last, last.ink == nil, last.type == .text, last.text.trimmingCharacters(in: .whitespaces).isEmpty,
            hits[last.id] != nil
        {
            lines.removeLast()
        }
        return lines
    }
}
