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

final class PaintFigureTests: XCTestCase {
    private func paint(_ id: String, _ x: Double, _ y: Double) -> Line {
        Line(id: id, ink: Ink(strokes: [Stroke(k: .drawing, c: "ink", p: [x, y, 0.5, x + 20, y + 20, 0.5])], free: true))
    }

    func testPiecesThatTouchAreOneFigureAndKeepTheirRegistration() {
        let lines = [Line(id: "t", text: "hello"), paint("a", 100, 10), Line(id: "u", text: "world"), paint("b", 110, 30), paint("far", 100, 900)]
        let blocks = InkPage.blocks(lines) { _ in 1 }
        let figures = PaintFigures.figures(lines, blocks: blocks)
        XCTAssertEqual(figures.count, 2)
        XCTAssertEqual(figures[0].primary, "a")
        XCTAssertEqual(figures[0].members, ["a", "b"])
        // "a" sits after the first line (top 40), "b" after the second (top 80): in a's coordinates b is 40 lower.
        XCTAssertEqual(figures[0].ink.strokes.count, 2)
        XCTAssertEqual(figures[0].ink.strokes[1].p[1], 30 + 40, accuracy: 1e-9)
        XCTAssertEqual(figures[1].members, ["far"])
    }

    func testNewStrokeNearPaintJoinsIt() {
        let lines = [Line(id: "t", text: "hello"), paint("a", 100, 40)]
        let blocks = InkPage.blocks(lines) { _ in 1 }
        let near = Stroke(k: .drawing, c: "ink", p: [130, 70, 0.5, 150, 90, 0.5])
        let placed = PenRules.place(blocks, contentEnd: InkPage.contentEnd(blocks), stroke: near, row: 1)
        guard case .join(let id, _, _, _) = placed else { return XCTFail("should join the drawing") }
        XCTAssertEqual(id, "a")
        let apart = Stroke(k: .drawing, c: "ink", p: [600, 500, 0.5, 620, 520, 0.5])
        if case .join = PenRules.place(blocks, contentEnd: InkPage.contentEnd(blocks), stroke: apart, row: 12) { XCTFail("far strokes are a new drawing") }
    }

    func testPaintStartsAtPenSizeAndPlace() {
        let l = Line(id: "a", ink: Ink(strokes: [Stroke(k: .drawing, c: "ink", p: [160, 10, 0.5, 360, 110, 0.5])], free: true))
        let f = InkPreview.frame(l, maxWidth: 700)!
        XCTAssertEqual(f.width, (200 + 2 * InkPreview.pad) * InkPreview.paintScale, accuracy: 1e-6)
        XCTAssertEqual(f.x, (160 - InkPreview.pad - penTextX) * InkPreview.paintScale, accuracy: 1e-6)
    }
}
