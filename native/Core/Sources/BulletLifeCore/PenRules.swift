// Where handwriting goes and what it means, by geometry alone (src/ink/structure.ts and myscript.ts):
// which ruled line a stroke is on, which entry it joins, the bullet drawn at a line's start, and how a
// handwritten paragraph is laid out for the recognizer. Rules from Fernando's tests with the pen.
import Foundation

/// Where text starts on an unindented line (sheet x), and how far one indent level moves it by hand.
public let penTextX: Double = 60
public let penStep: Double = 36

public struct LineShape: Equatable, Sendable {
    public var type: EntryType
    /// Indexes (in ink.strokes) of the strokes that form the bullet.
    public var bullet: [Int]
    public var indent: Int

    public init(type: EntryType, bullet: [Int], indent: Int) {
        self.type = type
        self.bullet = bullet
        self.indent = indent
    }
}

public struct PlacedBlock: Sendable {
    public var id: String
    public var top: Double
    public var height: Double
    /// Typed text or a typed bullet: handwriting never goes into it.
    public var typed: Bool
    public var strokes: [Stroke]

    public init(id: String, top: Double, height: Double, typed: Bool, strokes: [Stroke]) {
        self.id = id
        self.top = top
        self.height = height
        self.typed = typed
        self.strokes = strokes
    }
}

public enum InkPlacement: Equatable, Sendable {
    /// Joins an entry, on its ruled line `r`; `absorb`: a blank line written on, taken over by the paragraph above.
    case join(id: String, r: Int, top: Double, absorb: String?)
    /// A new entry after `after` (nil: at the end of the page), after `blanks` empty lines.
    case new(after: String?, blanks: Int, top: Double)

    public var top: Double {
        switch self {
        case .join(_, _, let top, _), .new(_, _, let top): return top
        }
    }
}

/// The stroke written just before: its ruled line, when (seconds), and its box.
public struct LastStroke: Sendable {
    public var row: Int
    public var at: TimeInterval
    public var box: Box
    public init(row: Int, at: TimeInterval, box: Box) {
        self.row = row
        self.at = at
        self.box = box
    }
}

public enum PenRules {
    static func shapeOf(_ s: Stroke, _ b: Box) -> EntryType? {
        let size = max(b.width, b.height)
        let n = s.p.count / 3
        let closed = hypot(s.p[0] - s.p[(n - 1) * 3], s.p[1] - s.p[(n - 1) * 3 + 1]) < max(6, size * 0.45)
        // A dot is a dot: a small loop (a written "o", an "a") is not one (Fernando's test).
        let loop = closed && b.width > 6 && b.height > 6
        if size <= 9 && !loop { return .task }
        if size <= 26 && closed && b.width > 5 && b.height > 5 && b.width / b.height < 2.2 && b.height / b.width < 2.2 { return .event }
        if b.width >= 6 && b.width <= 34 && b.height <= max(5, b.width / 3) { return .note }
        return nil
    }

    /// The leftmost writing stroke of the first ruled line is a bullet when it is small, has a clear gap
    /// before the words, and looks like a dot, a circle or a dash. Lines without one are free text.
    public static func readLineShape(_ strokes: [Stroke]) -> LineShape {
        var writing = strokes.enumerated().filter { $0.element.k == .writing && $0.element.r == 0 }.map { (i: $0.offset, s: $0.element, b: $0.element.box) }
        guard !writing.isEmpty else { return LineShape(type: .text, bullet: [], indent: 0) }
        writing.sort { $0.b.x0 < $1.b.x0 }
        let first = writing[0]
        let rest = writing.dropFirst()
        var type: EntryType = .text
        var bullet: [Int] = []
        var start = first.b.x0
        if !rest.isEmpty, let kind = shapeOf(first.s, first.b) {
            let gap = rest.map(\.b.x0).min()! - first.b.x1
            if gap >= 6 {
                type = kind
                bullet = [first.i]
                // The words start after the bullet; the indent is read from the bullet, which sits in the gutter.
                start = (first.b.x0 + first.b.x1) / 2 + (penTextX - 42)
            }
        }
        let indent = max(0, Int(((start - penTextX + penStep * 0.6) / penStep).rounded(.down)))
        return LineShape(type: type, bullet: bullet, indent: indent)
    }

    /// Whether a stroke right below a handwritten line opens a new item instead of continuing the paragraph:
    /// it looks like a bullet and sits in the margin, left of where the line above starts (as on paper). A
    /// letter at the start of the line, in line with the words above, continues the paragraph.
    static func bulletish(_ s: Stroke, _ b: Box, lineStart: Double?) -> Bool {
        guard let kind = shapeOf(s, b) else { return false }
        if kind == .event && max(b.width, b.height) > 16 { return false }
        guard let lineStart else { return true }
        return b.x1 <= lineStart + 4
    }

    /// Where the last ruled line of a handwritten block starts (its leftmost writing stroke).
    static func lastLineStart(_ block: PlacedBlock) -> (row: Int, x: Double)? {
        let writing = block.strokes.filter { $0.k == .writing }
        guard let row = writing.map(\.r).max() else { return nil }
        return (row, writing.filter { $0.r == row }.map(\.box.x0).min()!)
    }

    /// The ruled line a writing stroke belongs to. Letters sit on the rule and descenders reach into the line
    /// below, so the line is read from the top part of the stroke. Two corrections use the stroke just
    /// before (within 2.5 s): a stroke right after it (or a small mark a little before it: a comma, a
    /// cedilla) that is not wholly below it stays on its line; a small mark poking into the line above, over
    /// or before it (an accent, an i-dot), stays with it.
    public static func strokeRow(_ box: Box, kind: StrokeKind, last: LastStroke?, now: TimeInterval) -> Int {
        if kind == .drawing { return Int((box.y0 / inkRow).rounded(.down)) }
        let ay = box.y0 + min(box.height, inkRow * 0.6) * 0.5
        let row = Int((ay / inkRow).rounded(.down))
        guard let recent = last, now - recent.at < 2.5 else { return row }
        let small = box.height < inkRow * 0.35
        let sameLine = box.x0 >= recent.box.x0 - (small ? 200 : 8) && box.x0 <= recent.box.x1 + 60
        let notBelow = Int((box.y0 / inkRow).rounded(.down)) == recent.row || box.y0 <= recent.box.y1 + 6
        if row == recent.row + 1 && sameLine && notBelow { return recent.row }
        if small && row == recent.row - 1 && box.x0 <= recent.box.x1 + 4 { return recent.row }
        return row
    }

    /// A writing stroke's ruled line within an entry starting at `top` (see strokeRow).
    public static func rowWithin(_ box: Box, top: Double) -> Int {
        max(0, Int(((box.y0 - top + min(box.height, inkRow * 0.6) * 0.5) / inkRow).rounded(.down)))
    }

    /// Which entry a stroke goes into:
    /// - typed entries never take ink: writing on or next to one starts a new entry right after it;
    /// - a handwritten line takes more writing on its own lines, and the line right below it (also a blank
    ///   line there) continues it as a paragraph, unless it opens with a bullet or starts clearly further right;
    /// - a blank line takes what is written on it;
    /// - drawings get their own entry, except over another drawing or a blank line; writing over a drawing joins it;
    /// - below the last line, skipped lines become blank entries, as on paper.
    public static func place(_ blocks: [PlacedBlock], contentEnd: Double, stroke s: Stroke, row: Int, lastId: String? = nil) -> InkPlacement {
        let box = s.box
        let y = Double(row) * inkRow
        let drawingOnly = { (b: PlacedBlock) in !b.strokes.isEmpty && b.strokes.allSatisfy { $0.k == .drawing } }
        if let i = blocks.firstIndex(where: { y >= $0.top && y < $0.top + $0.height }) {
            let b = blocks[i]
            let blank = !b.typed && b.strokes.isEmpty
            if blank, s.k == .writing, i > 0, !blocks[i - 1].typed, !drawingOnly(blocks[i - 1]),
                let start = lastLineStart(blocks[i - 1]),
                y == blocks[i - 1].top + Double(start.row + 1) * inkRow,
                !bulletish(s, box, lineStart: start.x), box.x0 <= start.x + penStep * 0.8
            {
                return .join(id: blocks[i - 1].id, r: start.row + 1, top: blocks[i - 1].top, absorb: b.id)
            }
            if b.typed {
                if i + 1 < blocks.count, blocks[i + 1].id == lastId, !blocks[i + 1].typed {
                    return .join(id: blocks[i + 1].id, r: 0, top: blocks[i + 1].top, absorb: nil)
                }
                return .new(after: b.id, blanks: 0, top: b.top + b.height)
            }
            if s.k == .drawing {
                return drawingOnly(b) || blank ? .join(id: b.id, r: 0, top: b.top, absorb: nil) : .new(after: b.id, blanks: 0, top: b.top + b.height)
            }
            return .join(id: b.id, r: Int(((y - b.top) / inkRow).rounded()), top: b.top, absorb: nil)
        }
        let blanks = max(0, Int(((y - contentEnd) / inkRow).rounded()))
        if s.k == .writing, blanks == 0, let last = blocks.last, !last.typed, !drawingOnly(last),
            let start = lastLineStart(last), !bulletish(s, box, lineStart: start.x), box.x0 <= start.x + penStep * 0.8
        {
            return .join(id: last.id, r: start.row + 1, top: last.top, absorb: nil)
        }
        return .new(after: nil, blanks: blanks, top: contentEnd + Double(blanks) * inkRow)
    }

    /// A paragraph written over several ruled lines, laid out as one long line in reading order (each ruled
    /// line to the right of the one before), so the recognizer does not have to find the lines itself.
    public static func onOneLine(_ strokes: [Stroke]) -> [Stroke] {
        let rows = Dictionary(grouping: strokes, by: \.r)
        guard rows.count > 1 else { return strokes }
        var out: [Stroke] = []
        var right: Double?
        for r in rows.keys.sorted() {
            let row = rows[r]!
            let x0 = row.map(\.box.x0).min()!
            let x1 = row.map(\.box.x1).max()!
            let dx = right.map { $0 + 40 - x0 } ?? 0
            let dy = -Double(r) * inkRow
            for s in row {
                var moved = s
                moved.p = s.p.enumerated().map { i, v in i % 3 == 0 ? v + dx : i % 3 == 1 ? v + dy : v }
                out.append(moved)
            }
            right = x1 + dx
        }
        return out
    }
}
