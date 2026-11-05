// What a transcription does to a page (repo.ts pendingTranscriptions / applyTranscription), without the
// recognizer: which lines to read, and how what was read is stored. The ink stays the original; the text is
// its transcription, and a correction typed in Type mode is never overwritten.
import Foundation

/// What to read on one handwritten line: its writing without the hand-drawn bullet, laid out on one line
/// from the origin (a paragraph over several ruled lines reads left to right), and what to store it with.
public struct TranscriptionJob: Equatable, Sendable {
    public var id: String
    /// Writing strokes the line had when the job was made (Transcription.apply skips it if that changed).
    public var n: Int
    /// Highlighter strokes it had then (same).
    public var h: Int = 0
    public var shape: LineShape
    /// Flat [x, y, pressure, ...] per stroke, in writing order.
    public var strokes: [[Double]]
    /// Only when the highlighter covers some words: the line as consecutive stretches, each read on its own, those the
    /// highlighter covers (`covered`) to be put between `==` (see `Transcription.text(of:)`). Empty otherwise: the whole
    /// line is read at once from `strokes`, as always.
    public var runs: [TranscriptionRun] = []
}

public struct TranscriptionRun: Equatable, Sendable {
    public var covered: Bool
    public var strokes: [[Double]]
}

public enum Transcription {
    /// One job per line with unread writing, in page order.
    public static func jobs(_ lines: [Line]) -> [TranscriptionJob] {
        pending(lines).map { l in
            let all = l.ink?.strokes ?? []
            let shape = PenRules.readLineShape(all)
            let words = all.enumerated().filter { $0.element.k == .writing && !shape.bullet.contains($0.offset) }.map(\.element)
            let ordered = PenRules.onOneLineOrdered(words)
            let laid = ordered.map(\.stroke)
            let x0 = laid.map(\.box.x0).min() ?? 0
            let y0 = laid.map(\.box.y0).min() ?? 0
            let strokes = laid.map { s in s.p.enumerated().map { i, v in i % 3 == 0 ? v - x0 : i % 3 == 1 ? v - y0 : v } }
            let marks = all.filter { $0.k == .highlight }
            return TranscriptionJob(
                id: l.id, n: l.ink?.writingCount ?? 0, h: marks.count, shape: shape, strokes: strokes,
                runs: marks.isEmpty ? [] : runs(words: words, ordered: ordered, marks: marks))
        }
    }

    /// A gap wider than this (page units, on the line laid out in one row) between strokes starts a new word.
    static let wordGap = 12.0

    /// Whether a word's strokes lie under the highlighter: the centre of the stroke within the band the marking draws.
    static func covered(_ s: Stroke, by marks: [Stroke]) -> Bool {
        let b = s.box
        let c = (x: (b.x0 + b.x1) / 2, y: (b.y0 + b.y1) / 2)
        for m in marks where m.p.count >= 3 {
            let half = max(6, (m.s ?? 12) / 2)
            var i = 0
            var prev: (x: Double, y: Double)?
            while i + 1 < m.p.count {
                let cur = (x: m.p[i], y: m.p[i + 1])
                if distance(c, from: prev ?? cur, to: cur) <= half { return true }
                prev = cur
                i += 3
            }
        }
        return false
    }

    private static func distance(_ p: (x: Double, y: Double), from a: (x: Double, y: Double), to b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// The line's words (strokes grouped by the gaps between them, in reading order), each covered by the highlighter or
    /// not (more than half of its strokes under it), as consecutive stretches of the same kind. Empty when no word is
    /// covered (the line is then read whole, as without a marking).
    static func runs(words: [Stroke], ordered: [(source: Int, stroke: Stroke)], marks: [Stroke]) -> [TranscriptionRun] {
        var groups: [[Int]] = []
        var right = -Double.infinity
        for (k, item) in ordered.enumerated() {
            let b = item.stroke.box
            if groups.isEmpty || b.x0 > right + wordGap {
                groups.append([k])
                right = b.x1
            } else {
                groups[groups.count - 1].append(k)
                right = max(right, b.x1)
            }
        }
        let flags = groups.map { g in g.filter { covered(words[ordered[$0].source], by: marks) }.count * 2 > g.count }
        guard flags.contains(true) else { return [] }
        var out: [(covered: Bool, strokes: [Stroke])] = []
        for (g, flag) in zip(groups, flags) {
            let strokes = g.map { ordered[$0].stroke }
            if let last = out.last, last.covered == flag { out[out.count - 1].strokes += strokes } else { out.append((flag, strokes)) }
        }
        return out.map { run in
            let x0 = run.strokes.map(\.box.x0).min() ?? 0
            let y0 = run.strokes.map(\.box.y0).min() ?? 0
            return TranscriptionRun(
                covered: run.covered,
                strokes: run.strokes.map { s in s.p.enumerated().map { i, v in i % 3 == 0 ? v - x0 : i % 3 == 1 ? v - y0 : v } })
        }
    }

    /// The text of a job read in stretches: each stretch's reading in order, the covered ones between `==`, joined by
    /// spaces (empty readings left out).
    public static func text(of runs: [TranscriptionRun], readings: [String]) -> String {
        zip(runs, readings).compactMap { run, text in
            let t = text.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : run.covered ? "==\(t)==" : t
        }.joined(separator: " ")
    }

    /// The total of writing strokes on the page: changes with every stroke written or erased, not with a
    /// transcription (the screen waits for a pause in writing by watching it).
    public static func writingTotal(_ lines: [Line]) -> Int {
        lines.reduce(0) { $0 + ($1.ink?.writingCount ?? 0) }
    }

    /// Lines with writing the last transcription did not read, in page order.
    public static func pending(_ lines: [Line]) -> [Line] {
        lines.filter { $0.ink?.needsTranscription ?? false }
    }

    /// Stores what the recognizer read on line `id` (from `n` writing strokes). Returns nil when there is
    /// nothing to do: the line is gone, or it was written on again meanwhile (the next pass reads it).
    /// Type and indentation come from the drawing only the first time, and only where the line has none.
    public static func apply(id: String, n: Int, h: Int = 0, text: String, shape: LineShape, to lines: [Line]) -> [Line]? {
        guard let i = lines.firstIndex(where: { $0.id == id }), var ink = lines[i].ink, ink.writingCount == n, ink.highlightCount == h
        else { return nil }
        var line = lines[i]
        let first = ink.tx == nil
        // Text already there on the first pass (a transcription whose record was lost, or a correction) is
        // adopted as the transcription: the ink stays on its line, never split off into another.
        let ours = first ? line.text.trimmingCharacters(in: .whitespaces).isEmpty : line.text == ink.tx
        let bullet = Set(shape.bullet)
        ink.strokes = ink.strokes.enumerated().map { j, s in
            var s = s
            s.b = bullet.contains(j) ? true : nil
            return s
        }
        ink.n = n
        ink.h = h
        ink.tx = ours ? text : (ink.tx ?? line.text)
        line.ink = ink
        if ours { line.text = text }
        if first && line.type == .text && shape.type != .text { line.type = shape.type }
        if first && line.indent == 0 { line.indent = min(shape.indent, Outline.maxIndent(lines, i)) }
        var out = lines
        out[i] = line
        return out
    }
}

extension Outline {
    /// Max indent a line can take: one deeper than the line above it.
    public static func maxIndent(_ lines: [Line], _ i: Int) -> Int {
        i == 0 ? 0 : lines[i - 1].indent + 1
    }
}
