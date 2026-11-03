// Paint in Type mode: a drawing done in Draw mode takes no line, and one picture is often several entries (a
// stroke burst each). Type mode draws all the page's paint as one layer at the Pen page's scale, so the pieces
// of a picture always line up. Each stroke keeps its place over the text through one map from the Pen page's
// height to the Type page's: the same map for every stroke, so the pieces register with each other exactly.
import Foundation

public struct PaintMap: Sendable {
    /// Points on the Pen page (y in page units) paired with the Type page's y (points), nondecreasing in both.
    public var knots: [(pen: Double, type: Double)]
    /// Type points per page unit outside the knots (the Pen page is shown at 75%).
    public var scale: Double

    public init(knots: [(pen: Double, type: Double)], scale: Double = 0.75) {
        self.knots = knots
        self.scale = scale
    }

    /// `blocks`: the Pen page's lines (`InkPage.blocks`). `tops`: where each line shown in Type starts there,
    /// and `ends` where it ends; lines Type leaves out (paint, handwriting erased in Type) stand on the spot.
    public init(blocks: [PlacedBlock], tops: [String: Double], ends: [String: Double], scale: Double = 0.75) {
        var knots: [(pen: Double, type: Double)] = []
        var last = 0.0
        for b in blocks {
            if let t = tops[b.id] {
                let e = max(t, ends[b.id] ?? t)
                knots.append((b.top, max(last, t)))
                knots.append((b.top + b.height, max(last, e)))
                last = max(last, e)
            } else if b.height > 0 {
                knots.append((b.top, last))
                knots.append((b.top + b.height, last))
            }
        }
        self.init(knots: knots, scale: scale)
    }

    public func map(_ y: Double) -> Double {
        guard let first = knots.first, let last = knots.last else { return y * scale }
        if y <= first.pen { return first.type + (y - first.pen) * scale }
        if y >= last.pen { return last.type + (y - last.pen) * scale }
        var i = 0
        while i + 1 < knots.count, knots[i + 1].pen <= y { i += 1 }
        let a = knots[i], b = knots[min(i + 1, knots.count - 1)]
        guard b.pen > a.pen else { return a.type }
        return a.type + (y - a.pen) / (b.pen - a.pen) * (b.type - a.type)
    }
}

extension InkPage {
    /// The strokes of every paint entry (a free drawing without text), in page coordinates and drawing order.
    public static func paintStrokes(_ lines: [Line], blocks: [PlacedBlock]) -> [PageStroke] {
        let paint = Set(lines.filter(isPaint).map(\.id))
        return strokes(blocks.filter { paint.contains($0.id) })
    }
}
