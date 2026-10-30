// Inline formatting written as Markdown (src/editor/inline.ts): **bold**, *italic*, ==highlight==. The text is
// stored as typed; these read it.
import Foundation

public indirect enum InlineNode: Equatable, Sendable {
    public enum Kind: String, Sendable { case b, i, h }
    case text(String)
    case span(Kind, [InlineNode])
}

public enum InlineText {
    private static let rules: [(InlineNode.Kind, NSRegularExpression)] = [
        (.b, try! NSRegularExpression(pattern: #"\*\*(?=\S)([\s\S]*?\S)\*\*"#)),
        (.h, try! NSRegularExpression(pattern: #"==(?=\S)([\s\S]*?\S)=="#)),
        // A lone "*" next to a word or another "*" is not italic (e.g. "2*3", "**").
        (.i, try! NSRegularExpression(pattern: #"(?<![*\p{L}\p{N}])\*(?=[^\s*])([\s\S]*?[^\s*])\*(?![*\p{L}\p{N}])"#)),
    ]

    public static func mark(_ kind: InlineNode.Kind) -> String {
        switch kind {
        case .b: return "**"
        case .i: return "*"
        case .h: return "=="
        }
    }

    public static func parse(_ text: String) -> [InlineNode] {
        let ns = text as NSString
        var best: (InlineNode.Kind, NSTextCheckingResult)?
        for (kind, re) in rules {
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
                best == nil || m.range.location < best!.1.range.location
            {
                best = (kind, m)
            }
        }
        guard let (kind, m) = best else { return text.isEmpty ? [] : [.text(text)] }
        var out: [InlineNode] = []
        if m.range.location > 0 { out.append(.text(ns.substring(to: m.range.location))) }
        out.append(.span(kind, parse(ns.substring(with: m.range(at: 1)))))
        out += parse(ns.substring(from: m.range.location + m.range.length))
        return out
    }

    /// The text without its markers (plain text export, comparisons).
    public static func strip(_ text: String) -> String {
        func flat(_ nodes: [InlineNode]) -> String {
            nodes.map { if case .span(_, let c) = $0 { return flat(c) } else if case .text(let s) = $0 { return s } else { return "" } }.joined()
        }
        return flat(parse(text))
    }

    /// Rich text: <b>, <i>, <mark>, with the text escaped by `esc`.
    public static func html(_ text: String, esc: (String) -> String) -> String {
        func render(_ nodes: [InlineNode]) -> String {
            nodes.map { node -> String in
                switch node {
                case .text(let s): return esc(s)
                case .span(let k, let c):
                    let tag = k == .h ? "mark" : k.rawValue
                    return "<\(tag)>\(render(c))</\(tag)>"
                }
            }.joined()
        }
        return render(parse(text))
    }

    /// How the editor shows the formatting, as UTF-16 ranges of the text: the formatted words, and the markers
    /// (shown faintly while the caret is in their span, hidden otherwise). Plain text has no run.
    public static func runs(_ text: String) -> [InlineRun] {
        var out: [InlineRun] = []
        func walk(_ nodes: [InlineNode], at start: Int, bold: Bool, italic: Bool, highlight: Bool) -> Int {
            var at = start
            for node in nodes {
                switch node {
                case .text(let s):
                    let n = (s as NSString).length
                    if bold || italic || highlight {
                        out.append(InlineRun(location: at, length: n, bold: bold, italic: italic, highlight: highlight, span: nil))
                    }
                    at += n
                case .span(let kind, let children):
                    let m = (mark(kind) as NSString).length
                    let open = out.count
                    out.append(InlineRun(location: at, length: m, bold: bold, italic: italic, highlight: highlight, span: nil))
                    let end = walk(children, at: at + m, bold: bold || kind == .b, italic: italic || kind == .i, highlight: highlight || kind == .h)
                    let span = (location: at, length: end + m - at)
                    out[open].span = span
                    out.append(InlineRun(location: end, length: m, bold: bold, italic: italic, highlight: highlight, span: span))
                    at = end + m
                }
            }
            return at
        }
        _ = walk(parse(text), at: 0, bold: false, italic: false, highlight: false)
        return out
    }

    /// ⌘B, ⌘I, ⌘⇧H (LineEditor.tsx wrap): the selection [a, b) of one line wrapped in `mark`, or unwrapped
    /// when the marks are already around it. Returns the text and the new selection (UTF-16 offsets).
    public static func toggle(_ text: String, from a: Int, to b: Int, mark: String) -> (text: String, from: Int, to: Int) {
        let t = text as NSString
        let n = (mark as NSString).length
        let len = t.length
        let a = max(0, min(a, len)), b = max(a, min(b, len))
        func sub(_ from: Int, _ count: Int) -> String? {
            from >= 0 && from + count <= len ? t.substring(with: NSRange(location: from, length: count)) : nil
        }
        let before = sub(a - n, n), after = sub(b, n)
        let starNear = sub(a - n - 1, 1) == "*" || sub(b + n, 1) == "*"
        if before == mark && after == mark && (n > 1 || !starNear) {
            let out = t.substring(to: a - n) + t.substring(with: NSRange(location: a, length: b - a)) + t.substring(from: b + n)
            return (out, a - n, b - n)
        }
        let out = t.substring(to: a) + mark + t.substring(with: NSRange(location: a, length: b - a)) + mark + t.substring(from: b)
        return (out, a + n, b + n)
    }
}

/// A piece of a line shown formatted (see InlineText.runs). `span` is set on markers: the whole formatted span.
public struct InlineRun: Equatable, Sendable {
    public var location: Int
    public var length: Int
    public var bold: Bool
    public var italic: Bool
    public var highlight: Bool
    public var span: (location: Int, length: Int)?

    public var isMarker: Bool { span != nil }

    public static func == (l: InlineRun, r: InlineRun) -> Bool {
        l.location == r.location && l.length == r.length && l.bold == r.bold && l.italic == r.italic && l.highlight == r.highlight
            && l.span?.location == r.span?.location && l.span?.length == r.span?.length
    }
}
