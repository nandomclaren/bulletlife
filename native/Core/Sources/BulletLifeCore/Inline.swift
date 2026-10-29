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
}
