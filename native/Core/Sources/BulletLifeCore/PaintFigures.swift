// Paint in Type mode (Draw mode): a drawing takes no line on the Pen page, and one picture can be several entries
// (a stroke burst each). Type mode shows a picture as one figure: the paint entries whose strokes touch (or lie
// within a margin of each other) on the Pen page are one figure, drawn as one box in the text's flow, which
// takes its own room (so converting handwriting to text never leaves text under it), and which can be sized,
// moved and deleted like any drawing. Display only: the entries stay as they are.
import Foundation

public struct PaintFigure: Sendable {
    /// The first of its entries, in page order: the line the figure sits on in Type mode, and where its size and
    /// place (`Ink.view`) are kept.
    public var primary: String
    public var members: [String]
    /// Every member's strokes, in the primary's coordinates (display only).
    public var ink: Ink
    /// Where the figure is on the Pen page (page coordinates, no margin).
    public var box: Box
    /// The top of the primary's block: `ink` y is from here.
    public var top: Double
}

public enum PaintFigures {
    /// How close (page units) two pieces of paint must be to be one picture.
    public static let margin = 40.0

    public static func figures(_ lines: [Line], blocks: [PlacedBlock]) -> [PaintFigure] {
        let paint = Set(lines.filter(InkPage.isPaint).map(\.id))
        let items = blocks.filter { paint.contains($0.id) && !$0.strokes.isEmpty }
        guard !items.isEmpty else { return [] }
        let boxes = items.map { b -> Box in
            let all = b.strokes.map(\.box)
            let first = all[0]
            let u = all.dropFirst().reduce(first) { Box(x0: min($0.x0, $1.x0), y0: min($0.y0, $1.y0), x1: max($0.x1, $1.x1), y1: max($0.y1, $1.y1)) }
            return Box(x0: u.x0 - margin, y0: u.y0 + b.top - margin, x1: u.x1 + margin, y1: u.y1 + b.top + margin)
        }
        var parent = Array(items.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        for i in items.indices {
            for j in (i + 1)..<max(i + 1, items.count) where boxes[i].x0 <= boxes[j].x1 && boxes[j].x0 <= boxes[i].x1
                && boxes[i].y0 <= boxes[j].y1 && boxes[j].y0 <= boxes[i].y1
            {
                parent[find(j)] = find(i)
            }
        }
        var groups: [Int: [Int]] = [:]
        for i in items.indices { groups[find(i), default: []].append(i) }
        let byId = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return groups.values.sorted { $0[0] < $1[0] }.map { g in
            let first = items[g[0]]
            let strokes = g.flatMap { i -> [Stroke] in
                let shift = items[i].top - first.top
                return items[i].strokes.map { s in
                    var s = s
                    s.p = s.p.enumerated().map { j, v in j % 3 == 1 ? v + shift : v }
                    return s
                }
            }
            let abs = strokes.map { s -> Box in
                var b = s.box
                b.y0 += first.top
                b.y1 += first.top
                return b
            }
            let f = abs[0]
            let box = abs.dropFirst().reduce(f) { Box(x0: min($0.x0, $1.x0), y0: min($0.y0, $1.y0), x1: max($0.x1, $1.x1), y1: max($0.y1, $1.y1)) }
            return PaintFigure(
                primary: first.id, members: g.map { items[$0].id },
                ink: Ink(strokes: strokes, view: byId[first.id]?.ink?.view, free: true), box: box, top: first.top)
        }
    }

    /// The figure a point on the Pen page touches (within `tolerance`), if any: for tapping a drawing to select it.
    public static func hit(_ figures: [PaintFigure], x: Double, y: Double, tolerance: Double) -> PaintFigure? {
        var best: (PaintFigure, Double)?
        for f in figures {
            for s in f.ink.strokes where s.p.count >= 3 {
                var i = 0
                var prev: (Double, Double)?
                while i + 1 < s.p.count {
                    let cur = (s.p[i], s.p[i + 1] + f.top)
                    let d = prev.map { distance(x, y, $0, cur) } ?? hypot(x - cur.0, y - cur.1)
                    if d <= tolerance, best == nil || d < best!.1 { best = (f, d) }
                    prev = cur
                    i += 3
                }
            }
        }
        return best?.0
    }

    private static func distance(_ x: Double, _ y: Double, _ a: (Double, Double), _ b: (Double, Double)) -> Double {
        let dx = b.0 - a.0, dy = b.1 - a.1
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : min(1, max(0, ((x - a.0) * dx + (y - a.1) * dy) / len2))
        return hypot(x - (a.0 + t * dx), y - (a.1 + t * dy))
    }
}

extension InkPage {
    /// The default stroke diameter (a stroke with no `s`).
    public static let defaultStrokeSize = 2.4

    /// Resizes a whole picture by `factor` about its top-left corner (Pen mode: the corner handle). Strokes and their
    /// widths scale together; the pieces of a picture become one entry (the first), so it stays one picture. Paint takes
    /// no line, so nothing else on the page moves. Returns the lines (unchanged if the figure is not on the page).
    public static func resizeFigure(_ lines: [Line], figure fig: PaintFigure, factor: Double) -> [Line] {
        guard let i = lines.firstIndex(where: { $0.id == fig.primary }) else { return lines }
        let k = min(6, max(0.2, factor))
        let ax = fig.box.x0, ay = fig.box.y0
        let scaled = fig.ink.strokes.map { s -> Stroke in
            var s = s
            s.p = s.p.enumerated().map { j, v in
                switch j % 3 {
                case 0: return ax + (v - ax) * k
                case 1: return (ay + (v + fig.top - ay) * k) - fig.top
                default: return v
                }
            }
            s.s = (s.s ?? defaultStrokeSize) * k
            if let w = s.w { s.w = w.enumerated().map { j, v in j % 3 == 2 ? v : v * k } }
            return s
        }
        var out = lines
        out[i].ink = Ink(strokes: scaled, view: out[i].ink?.view, free: true)
        let others = Set(fig.members).subtracting([fig.primary])
        out.removeAll { others.contains($0.id) }
        return out
    }
}
