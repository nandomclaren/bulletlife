// A pen stroke of our own (prototype): the geometry of an ink line whose width follows the pressure with a curve
// we can tune. PencilKit still receives the Pencil; this only turns the points into an outline to fill. Pure
// math, no UIKit, so it is tested here and shared by the lab and, if approved, the pen page and the PDF.
import Foundation

public struct BrushParams: Equatable, Sendable, Codable {
    /// Width (pt) at zero pressure and at full pressure.
    public var minWidth: Double
    public var maxWidth: Double
    /// Pressure response: width = min + (max - min) * pressure^gamma. Below 1 the line swells with a light touch;
    /// above 1 it needs a firmer press.
    public var gamma: Double
    /// 0...0.95: how much of the previous pressure is kept (0 follows every sample, higher is softer).
    public var smoothing: Double
    /// Length (pt) over which the line grows from a thin start to its width, and shrinks at the end.
    public var taper: Double
    /// 0...0.8: how much a fast stroke thins (like ink thinning when the hand moves quickly).
    public var velocityThinning: Double

    public init(
        minWidth: Double = 0.8, maxWidth: Double = 3.2, gamma: Double = 0.8, smoothing: Double = 0.55, taper: Double = 6,
        velocityThinning: Double = 0.15
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.gamma = gamma
        self.smoothing = smoothing
        self.taper = taper
        self.velocityThinning = velocityThinning
    }

    public static let flat = BrushParams(minWidth: 2, maxWidth: 2, gamma: 1, smoothing: 0, taper: 0, velocityThinning: 0)
}

public struct BrushPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// 0...1 (a finger or mouse reports 0 or 1: use `defaultForce`).
    public var force: Double

    public init(x: Double, y: Double, force: Double) {
        self.x = x
        self.y = y
        self.force = force
    }
}

public enum PenBrush {
    public static let defaultForce = 0.45

    /// The width at a pressure.
    public static func width(force: Double, _ p: BrushParams) -> Double {
        let f = min(1, max(0, force))
        return p.minWidth + (p.maxWidth - p.minWidth) * pow(f, max(0.05, p.gamma))
    }

    /// The line's centre points (a Catmull-Rom curve through the samples, about `step` pt apart) with the width at
    /// each one: pressure smoothed, tapered at both ends, thinned by speed.
    public static func centerline(_ points: [BrushPoint], _ p: BrushParams, step: Double = 1.5) -> [(x: Double, y: Double, w: Double)] {
        guard let first = points.first else { return [] }
        let pts = points.map { BrushPoint(x: $0.x, y: $0.y, force: $0.force > 0 ? $0.force : defaultForce) }
        if pts.count == 1 { return [(first.x, first.y, width(force: pts[0].force, p))] }
        // Pressure, smoothed forward then backward so the line does not lag behind the hand.
        var f = pts.map(\.force)
        let k = min(0.95, max(0, p.smoothing))
        if k > 0 {
            for i in 1..<f.count { f[i] = k * f[i - 1] + (1 - k) * f[i] }
            for i in stride(from: f.count - 2, through: 0, by: -1) { f[i] = k * f[i + 1] + (1 - k) * f[i] }
        }
        // The curve.
        var out: [(x: Double, y: Double, force: Double)] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(pts.count - 1, i + 2)]
            let dist = hypot(p2.x - p1.x, p2.y - p1.y)
            let n = max(1, Int((dist / step).rounded(.up)))
            for s in 0..<n {
                let t = Double(s) / Double(n), t2 = t * t, t3 = t2 * t
                func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                out.append((cr(p0.x, p1.x, p2.x, p3.x), cr(p0.y, p1.y, p2.y, p3.y), f[i] + (f[i + 1] - f[i]) * t))
            }
        }
        out.append((pts[pts.count - 1].x, pts[pts.count - 1].y, f[f.count - 1]))
        // Length along the line, for the tapers and the speed.
        var along = [0.0]
        for i in 1..<out.count { along.append(along[i - 1] + hypot(out[i].x - out[i - 1].x, out[i].y - out[i - 1].y)) }
        let total = along[along.count - 1]
        // Speed is how far the hand moved between samples: the sample spacing around each curve point.
        let spacing = averageSpacing(pts)
        return out.enumerated().map { i, c in
            var w = width(force: c.force, p)
            if p.taper > 0 {
                let edge = min(along[i], total - along[i])
                let u = min(1, edge / p.taper)
                w *= 0.35 + 0.65 * (u * u * (3 - 2 * u))
            }
            if p.velocityThinning > 0 {
                // Fast strokes have far-apart samples: more than ~8 pt apart counts as quick.
                let quick = min(1, max(0, (spacing[min(i / max(1, out.count / pts.count), spacing.count - 1)] - 2) / 10))
                w *= 1 - p.velocityThinning * quick
            }
            return (c.x, c.y, max(0.2, w))
        }
    }

    private static func averageSpacing(_ pts: [BrushPoint]) -> [Double] {
        guard pts.count > 1 else { return [0] }
        var s = [Double](repeating: 0, count: pts.count)
        for i in 0..<pts.count {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            s[i] = hypot(b.x - a.x, b.y - a.y) / Double(max(1, min(pts.count - 1, i + 1) - max(0, i - 1)))
        }
        return s
    }

    /// The outline to fill: left edge forward, a round cap, right edge back, a round cap. Flat [x, y, ...].
    public static func outline(_ points: [BrushPoint], _ p: BrushParams) -> [Double] {
        let c = centerline(points, p)
        guard !c.isEmpty else { return [] }
        if c.count == 1 { return circle(c[0].x, c[0].y, c[0].w / 2) }
        var left: [Double] = [], right: [Double] = []
        for i in 0..<c.count {
            let a = c[max(0, i - 1)], b = c[min(c.count - 1, i + 1)]
            var dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            if len < 1e-9 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
            let r = c[i].w / 2
            left += [c[i].x - dy * r, c[i].y + dx * r]
            right += [c[i].x + dy * r, c[i].y - dx * r]
        }
        var result = left
        result += cap(c[c.count - 1], from: c[c.count - 2], forward: true)
        var i = right.count - 2
        while i >= 0 {
            result += [right[i], right[i + 1]]
            i -= 2
        }
        result += cap(c[0], from: c[1], forward: false)
        return result
    }

    private static func cap(_ end: (x: Double, y: Double, w: Double), from other: (x: Double, y: Double, w: Double), forward: Bool) -> [Double] {
        var dx = end.x - other.x, dy = end.y - other.y
        let len = hypot(dx, dy)
        if len < 1e-9 { dx = 1; dy = 0 } else { dx /= len; dy /= len }
        if !forward { dx = -dx; dy = -dy }
        // Half a circle from the left side round to the right side, bulging along (dx, dy).
        let r = end.w / 2
        let base = atan2(dx, -dy)  // angle of the left normal (-dy, dx) is atan2(dx, -dy)
        _ = base
        var pts: [Double] = []
        let steps = 6
        for s in 1..<steps {
            let a = Double.pi * Double(s) / Double(steps)
            // Rotating the left normal (-dy, dx) towards the direction (dx, dy), then to the right normal.
            let nx = -dy * cos(a) + dx * sin(a), ny = dx * cos(a) + dy * sin(a)
            pts += [end.x + nx * r, end.y + ny * r]
        }
        return pts
    }

    private static func circle(_ x: Double, _ y: Double, _ r: Double) -> [Double] {
        (0..<12).flatMap { i -> [Double] in
            let a = Double.pi * 2 * Double(i) / 12
            return [x + cos(a) * r, y + sin(a) * r]
        }
    }
}
