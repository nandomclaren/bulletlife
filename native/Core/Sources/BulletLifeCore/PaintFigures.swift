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
            return PaintFigure(
                primary: first.id, members: g.map { items[$0].id },
                ink: Ink(strokes: strokes, view: byId[first.id]?.ink?.view, free: true))
        }
    }
}
