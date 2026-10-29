// Export formats (CLAUDE.md 7; contract in docs/export-format.md), ported from src/export/format.ts. Built from
// the line model, so collapsed children are always included: collapsing never changes what is exported.
import Foundation

public enum GlyphStyle: String, Sendable { case checkboxes, dots }

public struct ExportSection: Sendable {
    /// Fixed layout label (a Month day, a Year month, "Month tasks"); nil for a plain page.
    public var heading: String?
    public var lines: [Line]
    public init(heading: String? = nil, lines: [Line]) {
        self.heading = heading
        self.lines = lines
    }
}

public struct ExportDoc: Sendable {
    public var title: String
    public var sections: [ExportSection]
    public init(title: String, sections: [ExportSection]) {
        self.title = title
        self.sections = sections
    }

    /// Selected lines as a title-less document, shifted so the shallowest line sits at level 0.
    public static func selection(_ lines: [Line]) -> ExportDoc {
        let min = lines.map(\.indent).min() ?? 0
        return ExportDoc(title: "", sections: [ExportSection(lines: lines.map { var l = $0; l.indent -= min; return l })])
    }
}

public enum Export {
    static let indent = "  "

    /// Signifiers written before the text: * priority, ! inspiration, 👁 explore.
    static func signifiers(_ l: Line) -> String {
        let s = (l.priority ? "*" : "") + (l.inspiration ? "!" : "") + (l.explore ? "👁" : "")
        return s.isEmpty ? "" : s + " "
    }

    /// Pen mode ink not transcribed yet is exported as a marker, so the line isn't lost silently.
    static func withInkText(_ l: Line) -> Line {
        guard l.text.trimmingCharacters(in: .whitespaces).isEmpty, let ink = l.ink, !ink.strokes.isEmpty else { return l }
        var out = l
        out.text = ink.strokes.allSatisfy { $0.k == .drawing } ? "(drawing)" : "(handwriting)"
        return out
    }

    static func markdownLine(_ line: Line, style: GlyphStyle, headingLevel: Int) -> String {
        let l = withInkText(line)
        let pad = String(repeating: indent, count: l.indent)
        let text = signifiers(l) + l.text
        switch l.type {
        case .heading: return String(repeating: "#", count: headingLevel) + " " + l.text
        case .text: return pad + l.text
        case .note: return "\(pad)- \(style == .dots ? "- " : "")\(text)"
        case .task, .event: break
        }
        let event = l.type == .event
        if style == .dots {
            let mark = [EntryState.done: "x ", .migrated: "> ", .scheduled: "< "][l.state] ?? ""
            let glyph = event ? "o" : "."
            if l.state == .cancelled { return "\(pad)- ~~\(glyph) \(text)~~" }
            return "\(pad)- \(mark)\(event && !mark.isEmpty ? "o " : mark.isEmpty ? "\(glyph) " : "")\(text)"
        }
        if l.state == .cancelled { return "\(pad)- ~~\(event ? "○ " : "")\(text)~~" }
        let box = [EntryState.open: "[ ] ", .done: "[x] ", .migrated: "[>] ", .scheduled: "[<] "][l.state] ?? ""
        if event { return "\(pad)- \(l.state == .open ? "" : box)○ \(text)" }
        return "\(pad)- \(box)\(text)"
    }

    public static func markdown(_ doc: ExportDoc, style: GlyphStyle = .checkboxes) -> String {
        var out = doc.title.isEmpty ? [] : ["# \(doc.title)"]
        for s in doc.sections where !s.lines.isEmpty {
            if !out.isEmpty { out.append("") }
            if let h = s.heading { out += ["## \(h)", ""] }
            out += s.lines.map { markdownLine($0, style: style, headingLevel: s.heading == nil ? 2 : 3) }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Combining long stroke: strikethrough that survives as plain text (Notes, Messages).
    static func strike(_ s: String) -> String {
        s.unicodeScalars.map { String($0) + "\u{0336}" }.joined()
    }

    static func glyph(_ l: Line, html: Bool = false) -> String {
        if l.type == .note { return "–" }
        switch l.state {
        case .done: return "×"
        case .migrated: return html ? "&gt;" : ">"
        case .scheduled: return html ? "&lt;" : "<"
        default: return l.type == .event ? "○" : "•"
        }
    }

    static func plainLine(_ line: Line) -> String {
        let l = withInkText(line)
        let pad = String(repeating: indent, count: l.indent)
        if l.type == .heading { return InlineText.strip(l.text).uppercased() }
        if l.type == .text { return pad + InlineText.strip(l.text) }
        let text = signifiers(l) + InlineText.strip(l.text)
        return "\(pad)\(glyph(l)) \(l.state == .cancelled && l.type != .note ? strike(text) : text)"
    }

    public static func plain(_ doc: ExportDoc) -> String {
        var out = doc.title.isEmpty ? [] : [doc.title]
        for s in doc.sections where !s.lines.isEmpty {
            if !out.isEmpty { out.append("") }
            if let h = s.heading { out.append(h) }
            out += s.lines.map(plainLine)
        }
        return out.joined(separator: "\n") + "\n"
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Bullet colors in Rich Text: the palette in use, light version (Classic unless the app passes another).
    public struct Colors: Sendable {
        public var task = "#E0533D", event = "#3B82C4", note = "#2A9D8F", muted = "#8A857C"
        public init() {}
    }

    /// Rich text for pasting into Notes, Mail, Docs: nested lists, colored bullets, struck-through cancellations.
    public static func html(_ doc: ExportDoc, colors: Colors = Colors()) -> String {
        var parts = doc.title.isEmpty ? [] : ["<h1>\(esc(doc.title))</h1>"]
        for s in doc.sections where !s.lines.isEmpty {
            if let h = s.heading { parts.append("<h2>\(esc(h))</h2>") }
            parts.append(listHtml(s.lines, inSection: s.heading != nil, colors: colors))
        }
        return "<meta charset=\"utf-8\">" + parts.joined()
    }

    static func listHtml(_ lines: [Line], inSection: Bool, colors: Colors) -> String {
        var html = ""
        var depth = -1
        let close = { (n: Int) in String(repeating: "</li></ul>", count: max(0, n)) }
        for l in lines {
            if l.type == .heading {
                html += close(depth + 1)
                depth = -1
                let h = inSection ? 3 : 2
                html += "<h\(h)>\(InlineText.html(l.text, esc: esc))</h\(h)>"
                continue
            }
            if l.indent > depth {
                html += String(repeating: "<ul style=\"list-style:none;padding-left:1.2em;margin:0\">", count: l.indent - depth)
            } else {
                html += "</li>" + String(repeating: "</ul></li>", count: depth - l.indent)
            }
            depth = l.indent
            html += "<li>\(itemHtml(l, colors: colors))"
        }
        return html + close(depth + 1)
    }

    static func itemHtml(_ line: Line, colors: Colors) -> String {
        let l = withInkText(line)
        if l.type == .text { return InlineText.html(l.text, esc: esc) }
        let color = l.type == .note ? colors.note : l.type == .event ? colors.event : colors.task
        let text = esc(signifiers(l)) + InlineText.html(l.text, esc: esc)
        let muted = l.type != .note && l.state != .open
        let body = l.state == .cancelled && l.type != .note ? "<s>\(text)</s>" : text
        return "<span style=\"color:\(color);font-weight:600\">\(glyph(l, html: true))</span> "
            + (muted ? "<span style=\"color:\(colors.muted)\">\(body)</span>" : body)
    }
}
