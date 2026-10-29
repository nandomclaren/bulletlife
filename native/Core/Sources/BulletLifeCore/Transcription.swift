// What a transcription does to a page (repo.ts pendingTranscriptions / applyTranscription), without the
// recognizer: which lines to read, and how what was read is stored. The ink stays the original; the text is
// its transcription, and a correction typed in Type mode is never overwritten.
import Foundation

public enum Transcription {
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
