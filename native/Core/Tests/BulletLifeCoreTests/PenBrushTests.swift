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

final class MisreadBulletTests: XCTestCase {
    private func circle(cx: Double, cy: Double, r: Double) -> Stroke {
        let pts = (0...12).flatMap { i -> [Double] in
            let a = Double.pi * 2 * Double(i) / 12
            return [cx + cos(a) * r, cy + sin(a) * r, 0.5]
        }
        return Stroke(k: .writing, c: "ink", p: pts)
    }

    func testACircleAboutInLineWithTheWordsAboveIsALetter() {
        let o = circle(cx: 100, cy: 10, r: 6)  // x1 = 106
        XCTAssertFalse(PenRules.bulletish(o, o.box, lineStart: 100))
        XCTAssertFalse(PenRules.bulletish(o, o.box, lineStart: 110))  // used to count as a bullet (106 <= 114)
        let margin = circle(cx: 60, cy: 10, r: 6)  // x1 = 66, clearly left of 100
        XCTAssertTrue(PenRules.bulletish(margin, margin.box, lineStart: 100))
    }

    func testErasingTheDrawnBulletTakesTheTypeWithIt() {
        var bullet = circle(cx: 40, cy: 10, r: 6)
        bullet.b = true
        let word = Stroke(k: .writing, c: "ink", p: [80, 5, 0.5, 120, 20, 0.5])
        let line = Line(id: "a", type: .event, state: .done, text: "ping", ink: Ink(strokes: [bullet, word], tx: "ping", n: 1))
        let out = InkPage.erase(["a": [0]], from: [line])
        XCTAssertEqual(out[0].type, .text)
        XCTAssertEqual(out[0].state, .open)
        XCTAssertEqual(out[0].ink?.strokes.count, 1)
        XCTAssertNil(out[0].ink?.n)  // read again
        XCTAssertEqual(out[0].text, "ping")  // the words stay
    }

    func testBackspaceOnAHandwrittenEventTurnsItsBulletIntoLetters() {
        var bullet = circle(cx: 40, cy: 10, r: 6)
        bullet.b = true
        let word = Stroke(k: .writing, c: "ink", p: [80, 5, 0.5, 120, 20, 0.5])
        let lines = [Line(id: "t", text: "above"), Line(id: "a", type: .event, text: "ping", ink: Ink(strokes: [bullet, word], tx: "ping", n: 2))]
        let edited = PageEdit.backspaceAtStart(lines, at: Caret(index: 1, offset: 0))!
        XCTAssertEqual(edited.lines[1].type, .text)
        XCTAssertFalse(edited.lines[1].ink!.strokes.contains { $0.b == true })
        XCTAssertNil(edited.lines[1].ink?.n)
    }
}

final class MonthDaysTests: XCTestCase {
    private func day(_ iso: String, _ text: String) -> Entry {
        Entry(id: iso + text, logId: Period.month(Dates.monthOf(iso)).logId, slot: iso, order: "a0", createdAt: "", updatedAt: "")
            .withText(text)
    }

    func testPastEmptyDaysAndTodayOnlyAtCheckInTime() {
        let entries = [day("2026-11-01", "a"), day("2026-11-02", "b"), day("2026-11-04", "d")]
        // Today is the 6th: the 3rd and the 5th are owed; today only once it is time.
        let early = MonthDays.toWrite(entries, today: "2026-11-06", todayDue: false)
        XCTAssertEqual(early, MonthDays.Pending(month: "2026-11", days: 2, latest: "2026-11-05"))
        let late = MonthDays.toWrite(entries, today: "2026-11-06", todayDue: true)
        XCTAssertEqual(late, MonthDays.Pending(month: "2026-11", days: 3, latest: "2026-11-06"))
    }

    func testNothingOwedWhenTodayIsWrittenAndNoDayBeforeTheFirstWrittenOne() {
        let entries = [day("2026-11-04", "d"), day("2026-11-05", "  ")]
        // The 1st-3rd are before the first written day: not owed; the 5th holds only blanks.
        let p = MonthDays.toWrite(entries, today: "2026-11-05", todayDue: false)
        XCTAssertNil(p)
        XCTAssertEqual(MonthDays.toWrite(entries, today: "2026-11-05", todayDue: true)?.days, 1)
        XCTAssertNil(MonthDays.toWrite([day("2026-11-05", "x")], today: "2026-11-05", todayDue: true))
    }

    func testAnEmptyMonthOwesOnlyToday() {
        XCTAssertNil(MonthDays.toWrite([], today: "2026-11-09", todayDue: false))
        XCTAssertEqual(MonthDays.toWrite([], today: "2026-11-09", todayDue: true), MonthDays.Pending(month: "2026-11", days: 1, latest: "2026-11-09"))
        // Other months' entries do not count.
        XCTAssertEqual(MonthDays.toWrite([day("2026-10-30", "z")], today: "2026-11-09", todayDue: true)?.days, 1)
    }
}

private extension Entry {
    func withText(_ t: String) -> Entry {
        var e = self
        e.text = t
        return e
    }
}

final class PaintResizeTests: XCTestCase {
    private func draw(_ id: String, _ pts: [Double], size: Double? = nil) -> Line {
        Line(id: id, ink: Ink(strokes: [Stroke(k: .drawing, c: "ink", p: pts, s: size)], free: true))
    }

    func testResizeScalesAboutTheTopLeftAndMergesThePieces() {
        // Two touching pieces after different lines: tops 40 and 80.
        let lines = [Line(id: "t", text: "hello"), draw("a", [100, 10, 0.5, 200, 60, 0.5], size: 3), Line(id: "u", text: "world"), draw("b", [150, 10, 0.5, 250, 30, 0.5])]
        let blocks = InkPage.blocks(lines) { _ in 1 }
        let fig = PaintFigures.figures(lines, blocks: blocks)[0]
        XCTAssertEqual(fig.members, ["a", "b"])
        let out = InkPage.resizeFigure(lines, figure: fig, factor: 2)
        XCTAssertEqual(out.map(\.id), ["t", "a", "u"])  // the second piece went into the first; nothing else moved
        let ink = out[1].ink!
        XCTAssertEqual(ink.strokes.count, 2)
        XCTAssertEqual(ink.free, true)
        // Page coordinates: the top-left corner stays, distances double.
        let ax = fig.box.x0, ay = fig.box.y0
        let p0 = ink.strokes[0].p
        XCTAssertEqual(p0[0], ax + (100 - ax) * 2, accuracy: 1e-9)
        XCTAssertEqual(p0[1] + fig.top, ay + (10 + fig.top - ay) * 2, accuracy: 1e-9)
        XCTAssertEqual(p0[3], ax + (200 - ax) * 2, accuracy: 1e-9)
        XCTAssertEqual(ink.strokes[0].s ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(ink.strokes[1].s ?? 0, 2.4 * 2, accuracy: 1e-9)
        // Pressure is untouched.
        XCTAssertEqual(p0[2], 0.5, accuracy: 1e-9)
    }

    func testFactorIsClampedAndUnknownFigureIsANoop() {
        let lines = [draw("a", [100, 10, 0.5, 200, 60, 0.5])]
        let blocks = InkPage.blocks(lines) { _ in 1 }
        let fig = PaintFigures.figures(lines, blocks: blocks)[0]
        let big = InkPage.resizeFigure(lines, figure: fig, factor: 100)
        XCTAssertEqual(big[0].ink!.strokes[0].p[3] - big[0].ink!.strokes[0].p[0], 100 * 6, accuracy: 1e-6)
        var missing = fig
        missing.primary = "nobody"
        XCTAssertEqual(InkPage.resizeFigure(lines, figure: missing, factor: 2), lines)
    }

    func testHitFindsTheDrawingNearAPoint() {
        let lines = [draw("a", [100, 10, 0.5, 300, 10, 0.5])]
        let blocks = InkPage.blocks(lines) { _ in 1 }
        let figs = PaintFigures.figures(lines, blocks: blocks)
        XCTAssertEqual(PaintFigures.hit(figs, x: 200, y: 14, tolerance: 8)?.primary, "a")
        XCTAssertNil(PaintFigures.hit(figs, x: 200, y: 60, tolerance: 8))
    }
}
