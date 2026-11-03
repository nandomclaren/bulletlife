import XCTest

@testable import BulletLifeCore

final class PenBrushTests: XCTestCase {
    func testWidthFollowsPressureCurve() {
        let p = BrushParams(minWidth: 1, maxWidth: 5, gamma: 1)
        XCTAssertEqual(PenBrush.width(force: 0, p), 1, accuracy: 1e-9)
        XCTAssertEqual(PenBrush.width(force: 1, p), 5, accuracy: 1e-9)
        XCTAssertEqual(PenBrush.width(force: 0.5, p), 3, accuracy: 1e-9)
        let soft = BrushParams(minWidth: 1, maxWidth: 5, gamma: 0.5)
        XCTAssertGreaterThan(PenBrush.width(force: 0.25, soft), PenBrush.width(force: 0.25, p))
        let firm = BrushParams(minWidth: 1, maxWidth: 5, gamma: 2)
        XCTAssertLessThan(PenBrush.width(force: 0.5, firm), PenBrush.width(force: 0.5, p))
    }

    func testFlatBrushKeepsOneWidthAndHeavierPressureWidens() {
        let line = (0..<20).map { BrushPoint(x: Double($0) * 4, y: 0, force: 0.3) }
        let flat = PenBrush.centerline(line, .flat)
        XCTAssertTrue(flat.allSatisfy { abs($0.w - 2) < 1e-6 })
        let p = BrushParams(smoothing: 0, taper: 0, velocityThinning: 0)
        let light = PenBrush.centerline(line, p)
        let heavy = PenBrush.centerline(line.map { BrushPoint(x: $0.x, y: $0.y, force: 0.9) }, p)
        XCTAssertGreaterThan(heavy[5].w, light[5].w)
    }

    func testTaperThinsTheEnds() {
        let line = (0..<40).map { BrushPoint(x: Double($0) * 2, y: 0, force: 0.6) }
        let c = PenBrush.centerline(line, BrushParams(smoothing: 0, taper: 10, velocityThinning: 0))
        XCTAssertLessThan(c[0].w, c[c.count / 2].w)
        XCTAssertLessThan(c[c.count - 1].w, c[c.count / 2].w)
    }

    func testOutlineSpansTheStrokeAndHandlesOnePoint() {
        let line = (0..<10).map { BrushPoint(x: Double($0) * 5, y: 3, force: 0.5) }
        let o = PenBrush.outline(line, BrushParams(minWidth: 2, maxWidth: 2, gamma: 1, smoothing: 0, taper: 0, velocityThinning: 0))
        XCTAssertEqual(o.count % 2, 0)
        let ys = stride(from: 1, to: o.count, by: 2).map { o[$0] }
        XCTAssertEqual(ys.min()!, 2, accuracy: 0.05)
        XCTAssertEqual(ys.max()!, 4, accuracy: 0.05)
        XCTAssertFalse(PenBrush.outline([BrushPoint(x: 1, y: 1, force: 0.5)], BrushParams()).isEmpty)
        XCTAssertTrue(PenBrush.outline([], BrushParams()).isEmpty)
    }
}

final class PaintMapTests: XCTestCase {
    func testSameMapForEveryStrokeAndExtrapolation() {
        // Two lines of 40 on the Pen page; in Type the first is 27 tall and the second 54.
        let blocks = [
            PlacedBlock(id: "a", top: 0, height: 40, typed: true, strokes: []),
            PlacedBlock(id: "p", top: 40, height: 0, typed: false, strokes: []),
            PlacedBlock(id: "b", top: 40, height: 40, typed: true, strokes: []),
        ]
        let m = PaintMap(blocks: blocks, tops: ["a": 10, "b": 37], ends: ["a": 37, "b": 91])
        XCTAssertEqual(m.map(0), 10, accuracy: 1e-9)
        XCTAssertEqual(m.map(20), 23.5, accuracy: 1e-9)
        XCTAssertEqual(m.map(40), 37, accuracy: 1e-9)
        XCTAssertEqual(m.map(60), 64, accuracy: 1e-9)
        XCTAssertEqual(m.map(80), 91, accuracy: 1e-9)
        // Above and below the page it continues at the Pen page's scale.
        XCTAssertEqual(m.map(-20), 10 - 15, accuracy: 1e-9)
        XCTAssertEqual(m.map(120), 91 + 30, accuracy: 1e-9)
        // Monotonic.
        var prev = -Double.infinity
        for y in stride(from: -30.0, through: 130, by: 5) {
            XCTAssertGreaterThanOrEqual(m.map(y), prev)
            prev = m.map(y)
        }
    }

    func testLinesLeftOutOfTypeStandOnASpot() {
        let blocks = [
            PlacedBlock(id: "a", top: 0, height: 40, typed: true, strokes: []),
            PlacedBlock(id: "gone", top: 40, height: 80, typed: false, strokes: []),
            PlacedBlock(id: "b", top: 120, height: 40, typed: true, strokes: []),
        ]
        let m = PaintMap(blocks: blocks, tops: ["a": 0, "b": 30], ends: ["a": 30, "b": 60])
        XCTAssertEqual(m.map(80), 30, accuracy: 1e-9)
        XCTAssertEqual(m.map(140), 45, accuracy: 1e-9)
    }

    func testPaintStrokesOnlyFromPaintEntries() {
        let draw = Stroke(k: .drawing, c: "ink", p: [1, 2, 0.5, 3, 4, 0.5])
        let paint = Line(id: "p", ink: Ink(strokes: [draw], free: true))
        let old = Line(id: "o", ink: Ink(strokes: [draw]))
        let text = Line(id: "t", text: "hello")
        let lines = [text, paint, old]
        let blocks = InkPage.blocks(lines) { _ in 1 }
        let got = InkPage.paintStrokes(lines, blocks: blocks)
        XCTAssertEqual(got.map(\.entryId), ["p"])
        // In page coordinates: the paint sits after the first line (40 units down).
        XCTAssertEqual(got[0].stroke.p[1], 2 + 40, accuracy: 1e-9)
    }
}
