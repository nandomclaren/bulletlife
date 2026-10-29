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
    public var shape: LineShape
    /// Flat [x, y, pressure, ...] per stroke, in writing order.
    public var strokes: [[Double]]
}

public enum Transcription {
    /// One job per line with unread writing, in page order.
    public static func jobs(_ lines: [Line]) -> [TranscriptionJob] {
        pending(lines).map { l in
            let all = l.ink?.strokes ?? []
            let shape = PenRules.readLineShape(all)
            let words = all.enumerated().filter { $0.element.k == .writing && !shape.bullet.contains($0.offset) }.map(\.element)
            let laid = PenRules.onOneLine(words)
            let x0 = laid.map(\.box.x0).min() ?? 0
            let y0 = laid.map(\.box.y0).min() ?? 0
            let strokes = laid.map { s in s.p.enumerated().map { i, v in i % 3 == 0 ? v - x0 : i % 3 == 1 ? v - y0 : v } }
            return TranscriptionJob(id: l.id, n: l.ink?.writingCount ?? 0, shape: shape, strokes: strokes)
        }
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
    public static func apply(id: String, n: Int, text: String, shape: LineShape, to lines: [Line]) -> [Line]? {
        guard let i = lines.firstIndex(where: { $0.id == id }), var ink = lines[i].ink, ink.writingCount == n else { return nil }
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
