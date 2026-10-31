// The same cases as the PWA's tests (src/**/*.test.ts), so both apps behave alike.
import Foundation
import XCTest

@testable import BulletLifeCore

final class OrderKeyTests: XCTestCase {
    // Vectors from the PWA's fractional-indexing package (generateKeyBetween).
    func testMatchesTheJavaScriptLibrary() throws {
        let cases: [(String?, String?, String)] = [
            (nil, nil, "a0"), ("a0", nil, "a1"), ("a9", nil, "aA"), ("az", nil, "b00"), ("aZ", nil, "aa"), ("Zz", nil, "a0"),
            ("a0", "a1", "a0V"), ("a0", "a0V", "a0G"), ("a0V", "a1", "a0l"), (nil, "a0", "Zz"), (nil, "Zz", "Zy"),
            ("a1", "a2", "a1V"), ("a0", "a01", "a00V"), ("b00", "b01", "b00V"), ("a0V", "a0W", "a0VV"), ("Zy", "Zz", "ZyV"),
            ("zzzzzzzzzzzzzzzzzzzzzzzzzzy", nil, "zzzzzzzzzzzzzzzzzzzzzzzzzzz"),
        ]
        for (a, b, expected) in cases {
            XCTAssertEqual(try OrderKey.between(a, b), expected, "between(\(a ?? "nil"), \(b ?? "nil"))")
        }
    }

    func testAssignKeepsKeysStillInOrder() {
        let keys = OrderKey.assign(ids: ["x", "new", "y"], existing: ["x": "a0", "y": "a1"])
        XCTAssertEqual(keys[0], "a0")
        XCTAssertEqual(keys[2], "a1")
        XCTAssertTrue(keys[1] > "a0" && keys[1] < "a1")
    }

    func testULIDsAreSortableAndUnique() {
        let a = ULID.make(now: Date(timeIntervalSince1970: 1_700_000_000))
        let b = ULID.make(now: Date(timeIntervalSince1970: 1_700_000_001))
        XCTAssertEqual(a.count, 26)
        XCTAssertTrue(a < b)
        XCTAssertNotEqual(ULID.make(), ULID.make())
    }
}

final class DatesTests: XCTestCase {
    // Vectors from the PWA (src/dates.ts): [day, week key Monday-first, week key Sunday-first].
    func testWeekKeys() {
        let cases: [(String, String, String)] = [
            ("2026-01-01", "2026-W01", "2026-W01"), ("2026-10-18", "2026-W42", "2026-W43"), ("2026-10-19", "2026-W43", "2026-W43"),
            ("2026-12-31", "2026-W53", "2026-W53"), ("2027-01-03", "2026-W53", "2027-W01"), ("2027-01-04", "2027-W01", "2027-W01"),
            ("2020-12-31", "2020-W53", "2020-W53"), ("2021-01-03", "2020-W53", "2021-W01"), ("2026-03-29", "2026-W13", "2026-W14"),
        ]
        for (day, monday, sunday) in cases {
            XCTAssertEqual(Dates.weekKey(day, firstDay: 1), monday, day)
            XCTAssertEqual(Dates.weekKey(day, firstDay: 0), sunday, day)
        }
    }

    func testWeekStarts() {
        let cases: [(String, String, String)] = [
            ("2026-W01", "2025-12-29", "2025-12-28"), ("2026-W43", "2026-10-19", "2026-10-18"),
            ("2020-W53", "2020-12-28", "2020-12-27"), ("2027-W01", "2027-01-04", "2027-01-03"),
        ]
        for (key, monday, sunday) in cases {
            XCTAssertEqual(Dates.weekKeyStart(key, firstDay: 1), monday, key)
            XCTAssertEqual(Dates.weekKeyStart(key, firstDay: 0), sunday, key)
        }
    }

    func testMonths() {
        XCTAssertEqual(Dates.addMonths("2026-12", 1), "2027-01")
        XCTAssertEqual(Dates.addMonths("2026-01", -1), "2025-12")
        XCTAssertEqual(Dates.daysInMonth("2028-02"), 29)
        XCTAssertEqual(Dates.daysInMonth("2026-02"), 28)
        XCTAssertEqual(Dates.monthDays("2026-02").last, "2026-02-28")
        XCTAssertEqual(Dates.addDays("2026-10-31", 1), "2026-11-01")
    }

    func testPeriods() {
        XCTAssertEqual(Period.week("2026-W43").logId, "weekly:2026-W43")
        XCTAssertEqual(Period.week("2026-W43").end(firstDay: 1), "2026-10-25")
        XCTAssertEqual(Period.month("2026-02").end(firstDay: 1), "2026-02-28")
        XCTAssertEqual(Period.day("2026-10-31").moved(1, firstDay: 1), .day("2026-11-01"))
        XCTAssertEqual(Period.containing("2026-10-18", like: .week(""), firstDay: 1), .week("2026-W42"))
    }
}

final class LinesTests: XCTestCase {
    func testPrefixes() {
        XCTAssertEqual(Rapid.match(". ")?.type, .task)
        XCTAssertEqual(Rapid.match("o. ")?.type, .event)
        XCTAssertEqual(Rapid.match("O. ")?.type, .event)
        XCTAssertEqual(Rapid.leading("O. Dinner")?.type, .event)
        XCTAssertEqual(Rapid.match("- ")?.type, .note)
        XCTAssertEqual(Rapid.match("# ")?.type, .heading)
        XCTAssertEqual(Rapid.match("* . "), PrefixMatch(type: .task, priority: true, length: 4))
        XCTAssertEqual(Rapid.match("* "), PrefixMatch(type: .text, priority: true, length: 2))
        XCTAssertNil(Rapid.match("o "))
        XCTAssertNil(Rapid.match("of "))
        XCTAssertNil(Rapid.match("* # "))
        XCTAssertEqual(Rapid.match("• ")?.type, .task)
        XCTAssertEqual(Rapid.match("– ")?.type, .note)
        XCTAssertEqual(Rapid.leading(". devocional"), PrefixMatch(type: .task, priority: false, length: 2))
        XCTAssertNil(Rapid.leading("devocional"))
    }

    func testStateCycleAndGlyphs() {
        XCTAssertEqual(States.next(.open), .done)
        XCTAssertEqual(States.next(.done), .cancelled)
        XCTAssertEqual(States.next(.cancelled), .open)
        XCTAssertEqual(States.next(.migrated), .open)
        XCTAssertEqual(States.glyph(.note, .done, eventStates: true), "–")
        XCTAssertEqual(States.glyph(.event, .done, eventStates: false), "○")
        XCTAssertEqual(States.glyph(.event, .done, eventStates: true), "×")
        XCTAssertEqual(States.glyph(.task, .done, eventStates: true, doneMark: "✓"), "✓")
        XCTAssertEqual(States.glyph(.task, .migrated, eventStates: true), ">")
        XCTAssertEqual(States.glyph(.text, .open, eventStates: true), "")
    }

    func testTree() {
        let lines = [
            Line(id: "a", type: .task, indent: 0, collapsed: true), Line(id: "b", type: .note, indent: 1),
            Line(id: "c", type: .event, indent: 2), Line(id: "d", type: .text, indent: 0, text: "1. first"),
        ]
        XCTAssertEqual(Outline.parentIds(lines), [nil, "a", "b", nil])
        XCTAssertEqual(Outline.colorTypes(lines), [.task, .task, .task, .task])
        XCTAssertEqual(Outline.hidden(lines), [false, true, true, false])
        XCTAssertEqual(Outline.numberPrefix("12) x"), "12)")
        XCTAssertNil(Outline.numberPrefix("2026 was"))
        XCTAssertNil(Outline.numberPrefix("1.5 kg"))
    }

    func testEntriesRoundTripThroughLines() {
        let lines = [Line(id: "a", type: .task, text: "Call"), Line(id: "b", type: .note, indent: 1, text: "number")]
        let first = Outline.diff(lines: lines, existing: [], logId: "daily:2026-10-29", slot: "", now: "t1")
        XCTAssertEqual(first.put.map(\.parentId), [nil, "a"])
        XCTAssertEqual(Outline.lines(from: first.put), lines)
        // Changing one line writes only that one; removing a line reports it.
        var edited = lines
        edited[1].text = "the number"
        let second = Outline.diff(lines: edited, existing: first.put, logId: "daily:2026-10-29", slot: "", now: "t2")
        XCTAssertEqual(second.put.map(\.id), ["b"])
        let third = Outline.diff(lines: [lines[0]], existing: first.put, logId: "daily:2026-10-29", slot: "", now: "t3")
        XCTAssertEqual(third.remove, ["b"])
    }

    func testReadsAPWABackup() throws {
        let json = """
            {"app":"bullet-life","format":1,"createdAt":"2026-10-29T10:00:00.000Z","logs":[],
             "entries":[{"id":"01J","logId":"daily:2026-10-28","slot":"","parentId":null,"order":"a0","type":"text","state":"open",
               "text":"Feliz pelo dia","signifiers":[],"collapsed":false,"createdAt":"x","updatedAt":"y",
               "ink":{"strokes":[{"k":"w","c":"ink","r":0,"p":[90,14.5,0.53,120,30,0.5],"pen":true}],"n":1,"tx":"Feliz pelo dia"},
               "realmId":"rlm-public","owner":"me"}]}
            """
        let backup = try Backup.parse(Data(json.utf8))
        XCTAssertEqual(backup.entries.count, 1)
        XCTAssertEqual(backup.entries[0].ink?.strokes[0].p[1], 14.5)
        XCTAssertEqual(backup.entries[0].ink?.needsTranscription, false)
        XCTAssertThrowsError(try Backup.parse(Data("{}".utf8)))
        XCTAssertThrowsError(try Backup.parse(Data(#"{"app":"bullet-life","format":9,"logs":[],"entries":[]}"#.utf8)))
    }
}

final class PenRulesTests: XCTestCase {
    func s(_ pts: [(Double, Double)], k: StrokeKind = .writing, r: Int = 0) -> Stroke {
        Stroke(k: k, r: r, p: pts.flatMap { [$0.0, $0.1, 0.5] })
    }
    func word(_ x: Double) -> Stroke { s([(x, 20), (x + 20, 10), (x + 40, 22), (x + 60, 12)]) }
    func circle(_ cx: Double, _ cy: Double, _ r: Double) -> Stroke {
        var pts: [(Double, Double)] = []
        for i in 0...12 {
            let a: Double = Double(i) / 12 * 2 * Double.pi
            pts.append((cx + r * cos(a), cy + r * sin(a)))
        }
        return s(pts)
    }
    func hand(_ id: String, _ top: Double, _ rows: Int, startX: Double = 20) -> PlacedBlock {
        PlacedBlock(id: id, top: top, height: Double(rows) * 40, typed: false, strokes: (0..<rows).map { r in s([(startX, 20), (startX + 80, 24)], r: r) })
    }

    func testReadingALine() {
        XCTAssertEqual(PenRules.readLineShape([s([(40, 20), (42, 21)]), word(62)]), LineShape(type: .task, bullet: [0], indent: 0))
        XCTAssertEqual(PenRules.readLineShape([circle(42, 20, 6), word(62)]).type, .event)
        XCTAssertEqual(PenRules.readLineShape([s([(34, 20), (50, 21)]), word(62)]).type, .note)
        XCTAssertEqual(PenRules.readLineShape([word(62), word(140)]), LineShape(type: .text, bullet: [], indent: 0))
        XCTAssertEqual(PenRules.readLineShape([s([(40, 20), (42, 21)])]).type, .text)
        XCTAssertEqual(PenRules.readLineShape([s([(60, 4), (64, 36)]), word(70)]).type, .text)
        XCTAssertEqual(PenRules.readLineShape([s([(78, 20), (80, 21)]), word(98)]).indent, 1)
        XCTAssertEqual(PenRules.readLineShape([word(132)]).indent, 2)
        XCTAssertEqual(PenRules.readLineShape([word(70)]).indent, 0)
        // A small written "o" is not a dot (a task): a loop that size reads as a circle.
        XCTAssertNotEqual(PenRules.shapeOf(circle(42, 20, 4), circle(42, 20, 4).box), .task)
    }

    func testALetterAtTheStartOfAParagraphLineIsNoBullet() {
        // The line above starts at x 60; "o suficiente": a small "o" in line with it continues the paragraph.
        let above = hand("a", 0, 1, startX: 60)
        let o = circle(64, 60, 4)
        XCTAssertEqual(PenRules.place([above], contentEnd: 40, stroke: o, row: 1), .join(id: "a", r: 1, top: 0, absorb: nil))
        // In the margin, left of where the line above starts, a dot or a circle opens a new item.
        XCTAssertEqual(PenRules.place([above], contentEnd: 40, stroke: s([(42, 60), (43, 61)]), row: 1), .new(after: nil, blanks: 0, top: 40))
        XCTAssertEqual(PenRules.place([above], contentEnd: 40, stroke: circle(44, 60, 5), row: 1), .new(after: nil, blanks: 0, top: 40))
    }

    func testStrokeRows() {
        let g = s([(100, 18), (110, 38), (104, 62)]).box
        XCTAssertEqual(PenRules.strokeRow(g, kind: .writing, last: nil, now: 0), 0)
        XCTAssertEqual(PenRules.strokeRow(s([(100, 36), (100, 72)]).box, kind: .writing, last: nil, now: 0), 1)
        let accent = s([(100, 34), (104, 30)]).box
        XCTAssertEqual(PenRules.strokeRow(accent, kind: .writing, last: nil, now: 0), 0)
        XCTAssertEqual(PenRules.strokeRow(accent, kind: .writing, last: LastStroke(row: 1, at: 1, box: Box(x0: 96, y0: 50, x1: 110, y1: 78)), now: 1.5), 1)
        let e = s([(20, 98), (30, 110)]).box
        XCTAssertEqual(PenRules.strokeRow(e, kind: .writing, last: LastStroke(row: 1, at: 1, box: Box(x0: 600, y0: 50, x1: 640, y1: 78)), now: 1.3), 2)
        // "um pouco": a tall p written low, and the small letters after it.
        let p = s([(130, 30), (131, 66), (131, 34), (140, 30), (138, 44)]).box
        let word0 = Box(x0: 100, y0: 24, x1: 122, y1: 38)
        XCTAssertEqual(PenRules.strokeRow(p, kind: .writing, last: nil, now: 0), 1)
        XCTAssertEqual(PenRules.strokeRow(p, kind: .writing, last: LastStroke(row: 0, at: 1, box: word0), now: 1.2), 0)
        XCTAssertEqual(PenRules.strokeRow(p, kind: .writing, last: LastStroke(row: 0, at: 1, box: word0), now: 4), 1)
        let o = s([(150, 26), (158, 32), (150, 38)]).box
        XCTAssertEqual(PenRules.strokeRow(o, kind: .writing, last: LastStroke(row: 1, at: 1, box: Box(x0: 130, y0: 30, x1: 140, y1: 66)), now: 1.2), 0)
        // "criança", "menos,": a cedilla or a comma under the word just written.
        let onRule = Box(x0: 300, y0: 24, x1: 340, y1: 39)
        let comma = s([(343, 40), (340, 48)]).box
        let cedilla = s([(306, 41), (309, 46), (304, 49)]).box
        XCTAssertEqual(PenRules.strokeRow(comma, kind: .writing, last: nil, now: 0), 1)
        XCTAssertEqual(PenRules.strokeRow(comma, kind: .writing, last: LastStroke(row: 0, at: 1, box: onRule), now: 1.3), 0)
        XCTAssertEqual(PenRules.strokeRow(cedilla, kind: .writing, last: LastStroke(row: 0, at: 1, box: onRule), now: 1.3), 0)
        let under = s([(310, 62), (330, 78)]).box
        XCTAssertEqual(PenRules.strokeRow(under, kind: .writing, last: LastStroke(row: 0, at: 1, box: onRule), now: 1.3), 1)
    }

    func testPlacement() {
        XCTAssertEqual(PenRules.place([hand("a", 0, 2)], contentEnd: 80, stroke: s([(22, 100), (90, 110)]), row: 2), .join(id: "a", r: 2, top: 0, absorb: nil))
        XCTAssertEqual(PenRules.place([hand("a", 0, 1)], contentEnd: 40, stroke: s([(10, 60), (11, 61)]), row: 1), .new(after: nil, blanks: 0, top: 40))
        XCTAssertEqual(PenRules.place([hand("a", 0, 1)], contentEnd: 40, stroke: s([(80, 60), (140, 66)]), row: 1), .new(after: nil, blanks: 0, top: 40))
        XCTAssertEqual(PenRules.place([hand("a", 0, 1)], contentEnd: 40, stroke: s([(20, 100), (90, 110)]), row: 2), .new(after: nil, blanks: 1, top: 80))
        let blank = PlacedBlock(id: "b", top: 40, height: 40, typed: false, strokes: [])
        XCTAssertEqual(
            PenRules.place([hand("a", 0, 1), blank, hand("c", 80, 1)], contentEnd: 120, stroke: s([(20, 60), (90, 66)]), row: 1),
            .join(id: "a", r: 1, top: 0, absorb: "b"))
        XCTAssertEqual(
            PenRules.place([hand("a", 0, 1), blank, hand("c", 80, 1)], contentEnd: 120, stroke: s([(120, 60), (190, 66)]), row: 1),
            .join(id: "b", r: 0, top: 40, absorb: nil))
        let typed = PlacedBlock(id: "h", top: 0, height: 40, typed: true, strokes: [])
        XCTAssertEqual(PenRules.place([typed], contentEnd: 40, stroke: s([(60, 10), (80, 30)]), row: 0), .new(after: "h", blanks: 0, top: 40))
    }

    func testParagraphOnOneLine() {
        func row(_ r: Int, _ x: Double) -> Stroke {
            let dy: Double = Double(r) * 40
            return s([(x, 20 + dy), (x + 20, 10 + dy), (x + 40, 22 + dy), (x + 60, 12 + dy)], r: r)
        }
        let out = PenRules.onOneLine([row(0, 100), row(0, 300), row(1, 60), row(1, 200)])
        XCTAssertEqual(Set(out.map(\.box.y0)).count, 1)
        XCTAssertEqual(out[2].box.x0, 400)
        XCTAssertEqual(out[3].box.x0 - out[2].box.x0, 140)
        XCTAssertEqual(out[0].box.x0, 100)
    }
}

final class InkPageTests: XCTestCase {
    func w(_ x: Double, _ y: Double, r: Int = 0) -> Stroke { Stroke(k: .writing, r: r, p: [x, y, 0.5, x + 30, y + 8, 0.5]) }

    func testBlocksStackTypedAndHandwrittenLines() {
        let lines = [
            Line(id: "h", type: .heading, text: "Blurb"),
            Line(id: "p", text: "two lines", ink: Ink(strokes: [w(80, 14), w(80, 54, r: 1)], tx: "two lines", n: 2)),
            Line(id: "t", type: .task, text: "a long typed task"),
        ]
        let blocks = InkPage.blocks(lines) { $0.id == "t" ? 2 : 1 }
        XCTAssertEqual(blocks.map(\.top), [0, 40, 120])
        XCTAssertEqual(blocks.map(\.height), [40, 80, 80])
        XCTAssertEqual(blocks.map(\.typed), [true, false, true])
        XCTAssertEqual(InkPage.contentEnd(blocks), 200)
        // Page coordinates: the paragraph's second line sits at its top + 40 + 54.
        XCTAssertEqual(InkPage.strokes(blocks)[1].stroke.p[1], 94)
    }

    func testCorrectedHandwritingStaysHandwriting() {
        XCTAssertFalse(InkPage.isTyped(Line(text: "Thati", ink: Ink(strokes: [w(80, 14)], tx: "That i", n: 1))))
        XCTAssertTrue(InkPage.isTyped(Line(text: "typed")))
        XCTAssertTrue(InkPage.isTyped(Line(type: .task)))
        XCTAssertFalse(InkPage.isTyped(Line()))
    }

    func testWritingJoinsOrStartsEntries() {
        let lines = [Line(id: "a", ink: Ink(strokes: [w(20, 14)], tx: "", n: 1)), Line(id: "b")]
        // On the blank line right under the paragraph: joins it on its line 1, and the blank line goes.
        let joined = InkPage.add(w(20, 54), placement: .join(id: "a", r: 1, top: 0, absorb: "b"), to: lines)
        XCTAssertEqual(joined.entryId, "a")
        XCTAssertEqual(joined.lines.map(\.id), ["a"])
        XCTAssertEqual(joined.lines[0].ink?.strokes.last?.r, 1)
        XCTAssertEqual(joined.lines[0].ink?.strokes.last?.p[1], 54)
        XCTAssertEqual(joined.lines[0].ink?.tx, "")
        // Two ruled lines below the content: a blank line, then the new entry, its stroke from its own top.
        let fresh = InkPage.add(w(20, 134), placement: .new(after: nil, blanks: 1, top: 120), to: lines)
        XCTAssertEqual(fresh.lines.count, 4)
        XCTAssertEqual(fresh.lines.last?.id, fresh.entryId)
        XCTAssertEqual(fresh.lines.last?.ink?.strokes[0].p[1], 14)
        XCTAssertNil(fresh.lines[2].ink)
    }

    func testErasing() {
        let lines = [
            Line(id: "a", text: "hello", ink: Ink(strokes: [w(20, 14)], tx: "hello", n: 1)),
            Line(id: "b", text: "fixed by hand", ink: Ink(strokes: [w(20, 14)], tx: "x", n: 1)),
            Line(id: "c", ink: Ink(strokes: [w(20, 14)])),
        ]
        let out = InkPage.erase(["a": [0], "b": [0], "c": [0]], from: lines)
        // The transcription goes with its handwriting; a typed correction stays; the emptied last line goes.
        XCTAssertEqual(out.map(\.id), ["a", "b"])
        XCTAssertEqual(out[0].text, "")
        XCTAssertNil(out[0].ink)
        XCTAssertEqual(out[1].text, "fixed by hand")
    }
}

final class TranscriptionTests: XCTestCase {
    func handwritten(_ text: String = "", tx: String? = nil, n: Int? = nil, strokes: Int = 2) -> Line {
        let s = (0..<strokes).map { _ in Stroke(k: .writing, p: [10, 10, 0.5, 20, 20, 0.5]) }
        return Line(text: text, ink: Ink(strokes: s, tx: tx, n: n))
    }

    func testPendingOnlyUnreadWriting() {
        let read = handwritten("hi", tx: "hi", n: 2)
        let fresh = handwritten()
        let drawing = Line(ink: Ink(strokes: [Stroke(k: .drawing, p: [0, 0, 0.5])]))
        XCTAssertEqual(Transcription.pending([read, fresh, drawing, Line(text: "typed")]).map(\.id), [fresh.id])
    }

    func testFirstPassWritesTextTypeIndentAndBullet() throws {
        let parent = Line(type: .task, text: "Trip")
        let line = handwritten()
        let shape = LineShape(type: .task, bullet: [0], indent: 3)
        let out = try XCTUnwrap(Transcription.apply(id: line.id, n: 2, text: "Pack", shape: shape, to: [parent, line]))
        XCTAssertEqual(out[1].text, "Pack")
        XCTAssertEqual(out[1].type, .task)
        XCTAssertEqual(out[1].indent, 1)  // clamped: one deeper than the line above
        XCTAssertEqual(out[1].ink?.tx, "Pack")
        XCTAssertEqual(out[1].ink?.n, 2)
        XCTAssertEqual(out[1].ink?.strokes.map(\.b), [true, nil])
    }

    func testStaleCountIsSkipped() {
        let line = handwritten(strokes: 3)
        XCTAssertNil(Transcription.apply(id: line.id, n: 2, text: "x", shape: LineShape(type: .text, bullet: [], indent: 0), to: [line]))
    }

    func testCorrectionIsNeverOverwritten() throws {
        let line = handwritten("Corrected", tx: "Corected", n: 1, strokes: 2)
        let out = try XCTUnwrap(
            Transcription.apply(id: line.id, n: 2, text: "Corected more", shape: LineShape(type: .note, bullet: [], indent: 2), to: [line]))
        XCTAssertEqual(out[0].text, "Corrected")
        XCTAssertEqual(out[0].ink?.tx, "Corected")
        XCTAssertEqual(out[0].type, .text)  // type and indent are read only the first time
        XCTAssertEqual(out[0].ink?.n, 2)
    }

    func testOwnTranscriptionIsReplaced() throws {
        let line = handwritten("Corected", tx: "Corected", n: 1)
        let out = try XCTUnwrap(Transcription.apply(id: line.id, n: 2, text: "Corrected", shape: LineShape(type: .text, bullet: [], indent: 0), to: [line]))
        XCTAssertEqual(out[0].text, "Corrected")
        XCTAssertEqual(out[0].ink?.tx, "Corrected")
    }

    func testFirstPassAdoptsExistingText() throws {
        let line = handwritten("Already here")
        let out = try XCTUnwrap(Transcription.apply(id: line.id, n: 2, text: "Alredy", shape: LineShape(type: .text, bullet: [], indent: 0), to: [line]))
        XCTAssertEqual(out[0].text, "Already here")
        XCTAssertEqual(out[0].ink?.tx, "Already here")
    }
}

final class ExportTests: XCTestCase {
    let sample: [Line] = [
        Line(type: .task, collapsed: true, priority: true, text: "Call the bank"),
        Line(type: .note, indent: 1, text: "closes at 6"),
        Line(type: .task, state: .done, text: "Buy bread"),
        Line(type: .task, state: .migrated, text: "Renew passport"),
        Line(type: .task, state: .scheduled, text: "Dentist"),
        Line(type: .task, state: .cancelled, text: "Gym"),
        Line(type: .event, text: "Dinner with Ana"),
        Line(type: .event, state: .done, text: "Concert"),
        Line(type: .event, state: .cancelled, text: "Trip"),
        Line(type: .text, text: "Quiet day."),
    ]

    func page(_ lines: [Line]) -> ExportDoc { ExportDoc(title: "Sun, Oct 18", sections: [ExportSection(lines: lines)]) }

    func testMarkdownCheckboxesWithCollapsedChildren() {
        let expected = [
            "# Sun, Oct 18", "", "- [ ] * Call the bank", "  - closes at 6", "- [x] Buy bread", "- [>] Renew passport", "- [<] Dentist",
            "- ~~Gym~~", "- ○ Dinner with Ana", "- [x] ○ Concert", "- ~~○ Trip~~", "Quiet day.", "",
        ]
        XCTAssertEqual(Export.markdown(page(sample)), expected.joined(separator: "\n"))
    }

    func testMarkdownDots() {
        let lines = Export.markdown(page(sample), style: .dots).components(separatedBy: "\n")
        XCTAssertEqual(
            Array(lines[2..<11]),
            [
                "- . * Call the bank", "  - - closes at 6", "- x Buy bread", "- > Renew passport", "- < Dentist", "- ~~. Gym~~",
                "- o Dinner with Ana", "- x o Concert", "- ~~o Trip~~",
            ])
    }

    func testSections() {
        let doc = ExportDoc(
            title: "October 2026",
            sections: [
                ExportSection(heading: "18 Sun", lines: [Line(text: "Long walk")]),
                ExportSection(heading: "19 Mon", lines: []),
                ExportSection(heading: "Month tasks", lines: [Line(type: .task, text: "Taxes"), Line(type: .heading, text: "Work")]),
            ])
        XCTAssertEqual(Export.markdown(doc), "# October 2026\n\n## 18 Sun\n\nLong walk\n\n## Month tasks\n\n- [ ] Taxes\n### Work\n")
    }

    func testPlain() {
        let lines = Export.plain(page(sample)).components(separatedBy: "\n")
        XCTAssertEqual(Array(lines[1..<5]), ["", "• * Call the bank", "  – closes at 6", "× Buy bread"])
        XCTAssertTrue(lines[7].hasPrefix("• G\u{0336}"))
    }

    func testHtmlNestsCollapsedChildren() {
        let html = Export.html(page(Array(sample[0..<3])))
        XCTAssertTrue(html.contains("<h1>Sun, Oct 18</h1>"))
        XCTAssertNotNil(html.range(of: #"Call the bank<ul[^>]*><li>.*closes at 6</li></ul></li><li>.*Buy bread"#, options: .regularExpression))
    }

    func testUntranscribedInkIsMarked() {
        let l = Line(ink: Ink(strokes: [Stroke(k: .writing, p: [0, 0, 0.5])]))
        XCTAssertEqual(Export.markdown(ExportDoc(title: "", sections: [ExportSection(lines: [l])])), "(handwriting)\n")
    }

    func testInline() {
        XCTAssertEqual(InlineText.strip("a **bold** and *it* ==hi== 2*3"), "a bold and it hi 2*3")
        XCTAssertEqual(InlineText.html("**a<b**", esc: Export.esc), "<b>a&lt;b</b>")
    }
}

final class TranscriptionJobTests: XCTestCase {
    func testJobLeavesOutBulletAndLaysRowsOnOneLine() {
        // A dot (the bullet) at the left, then a word on row 0 and another on row 1.
        let dot = Stroke(k: .writing, r: 0, p: [70, 20, 0.5, 71, 21, 0.5])
        let w1 = Stroke(k: .writing, r: 0, p: [100, 10, 0.5, 160, 30, 0.5])
        let w2 = Stroke(k: .writing, r: 1, p: [100, 50, 0.5, 140, 70, 0.5])
        let line = Line(ink: Ink(strokes: [dot, w1, w2]))
        let jobs = Transcription.jobs([Line(text: "typed"), line])
        XCTAssertEqual(jobs.count, 1)
        let job = jobs[0]
        XCTAssertEqual(job.id, line.id)
        XCTAssertEqual(job.n, 3)
        XCTAssertEqual(job.shape.type, .task)
        XCTAssertEqual(job.shape.bullet, [0])
        XCTAssertEqual(job.strokes.count, 2)
        // From the origin; row 1 goes to the right of row 0, on the same baseline.
        XCTAssertEqual(job.strokes[0], [0, 0, 0.5, 60, 20, 0.5])
        XCTAssertEqual(job.strokes[1], [100, 0, 0.5, 140, 20, 0.5])
    }

    func testWritingTotalIgnoresTranscription() throws {
        let line = Line(ink: Ink(strokes: [Stroke(k: .writing, p: [0, 0, 0.5]), Stroke(k: .drawing, p: [0, 0, 0.5])]))
        XCTAssertEqual(Transcription.writingTotal([line]), 1)
        let done = try XCTUnwrap(Transcription.apply(id: line.id, n: 1, text: "a", shape: LineShape(type: .text, bullet: [], indent: 0), to: [line]))
        XCTAssertEqual(Transcription.writingTotal(done), 1)
        XCTAssertTrue(Transcription.jobs(done).isEmpty)
    }
}

final class EditingTests: XCTestCase {
    func indents(_ xs: Int...) -> [Line] { xs.map { Line(indent: $0) } }

    func testShiftIndent() {
        XCTAssertEqual(Outline.shiftIndent(indents(0, 0, 1, 0), from: 1, to: 1, delta: 1), [0, 1, 2, 0])
        XCTAssertNil(Outline.shiftIndent(indents(0, 1), from: 1, to: 1, delta: 1))
        XCTAssertNil(Outline.shiftIndent(indents(0), from: 0, to: 0, delta: 1))
        XCTAssertEqual(Outline.shiftIndent(indents(0, 1, 2, 1), from: 1, to: 1, delta: -1), [0, 0, 1, 1])
        XCTAssertNil(Outline.shiftIndent(indents(0, 1), from: 0, to: 0, delta: -1))
    }

    func testNumbers() {
        XCTAssertEqual(Outline.nextNumber("2."), "3.")
        XCTAssertEqual(Outline.nextNumber("9)"), "10)")
    }

    func run(_ before: [String]?, _ after: [(Int, String)]) -> [String] {
        var lines = after.enumerated().map { i, a in Line(id: "l\(i)", indent: a.0, text: a.1) }
        let keep = before.map { b in Outline.listRestarts(b.enumerated().map { Line(id: "l\($0.offset)", text: $0.element) }) } ?? []
        Outline.renumberLists(&lines, keep: keep)
        return lines.map(\.text)
    }

    func testRenumberLists() {
        XCTAssertEqual(run(nil, [(0, "1. a"), (0, "2. new"), (0, "2. b"), (0, "3. c")]), ["1. a", "2. new", "3. b", "4. c"])
        XCTAssertEqual(run(nil, [(0, "1. a"), (0, "3. c")]), ["1. a", "2. c"])
        XCTAssertEqual(
            run(nil, [(0, "1. a"), (1, "note"), (1, "1. sub"), (1, "5. sub"), (0, "7. b")]), ["1. a", "note", "1. sub", "2. sub", "2. b"])
        XCTAssertEqual(run(nil, [(0, "4) a"), (0, "1. b"), (0, "plain"), (0, "9. c")]), ["4) a", "5) b", "plain", "9. c"])
        XCTAssertEqual(
            run(["1. a", "2. b", "10. x"], [(0, "1. a"), (0, "2. b"), (0, "10. x"), (0, "11. ")]), ["1. a", "2. b", "10. x", "11. "])
        let before = ["1. a", "2. b", "3. c", "10. x", "11. y"].enumerated().map { Line(id: "abcxy".map(String.init)[$0.offset], text: $0.element) }
        var after = before.filter { $0.id != "b" }
        Outline.renumberLists(&after, keep: Outline.listRestarts(before))
        XCTAssertEqual(after.map(\.text), ["1. a", "2. c", "10. x", "11. y"])
    }

    func testRestartIfFirst() {
        var a = [Line(text: "1. Alpha"), Line(indent: 1, text: "2. Inserted")]
        Outline.restartIfFirst(&a, 1)
        XCTAssertEqual(a[1].text, "1. Inserted")
        var b = [Line(text: "1. a"), Line(text: "2. b"), Line(text: "3. c")]
        Outline.restartIfFirst(&b, 2)
        XCTAssertEqual(b[2].text, "3. c")
    }

    func testEnterSplitsAndContinuesType() {
        let lines = [Line(type: .task, text: "Buy bread")]
        let out = PageEdit.enter(lines, at: Caret(index: 0, offset: 3))
        XCTAssertEqual(out.lines.map(\.text), ["Buy", " bread"])
        XCTAssertEqual(out.lines[1].type, .task)
        XCTAssertEqual(out.caret, Caret(index: 1, offset: 0))
        // After a heading, plain text.
        let h = PageEdit.enter([Line(type: .heading, text: "Work")], at: Caret(index: 0, offset: 4))
        XCTAssertEqual(h.lines[1].type, .text)
    }

    func testEnterOnEmptyBulletOutdentsThenDropsBullet() {
        let nested = [Line(type: .task, text: "a"), Line(type: .task, indent: 1)]
        let once = PageEdit.enter(nested, at: Caret(index: 1, offset: 0))
        XCTAssertEqual(once.lines[1].indent, 0)
        XCTAssertEqual(once.lines[1].type, .task)
        let twice = PageEdit.enter(once.lines, at: Caret(index: 1, offset: 0))
        XCTAssertEqual(twice.lines[1].type, .text)
    }

    func testEnterInNumberedList() {
        let next = PageEdit.enter([Line(text: "1. a"), Line(text: "2. b")], at: Caret(index: 1, offset: 4))
        XCTAssertEqual(next.lines.map(\.text), ["1. a", "2. b", "3. "])
        XCTAssertEqual(next.caret, Caret(index: 2, offset: 3))
        let ends = PageEdit.enter(next.lines, at: Caret(index: 2, offset: 3))
        XCTAssertEqual(ends.lines.map(\.text), ["1. a", "2. b", ""])
        // Splitting the middle of a list renumbers what follows.
        let mid = PageEdit.enter([Line(text: "1. a"), Line(text: "2. b")], at: Caret(index: 0, offset: 4))
        XCTAssertEqual(mid.lines.map(\.text), ["1. a", "2. ", "3. b"])
    }

    func testEnterOnOpenParentAddsFirstChild() {
        let lines = [Line(type: .task, text: "Trip"), Line(type: .note, indent: 1, text: "bags")]
        let out = PageEdit.enter(lines, at: Caret(index: 0, offset: 4))
        XCTAssertEqual(out.lines.map(\.indent), [0, 1, 1])
        XCTAssertEqual(out.lines[1].type, .note)
        var closed = lines
        closed[0].collapsed = true
        let after = PageEdit.enter(closed, at: Caret(index: 0, offset: 4))
        XCTAssertEqual(after.lines.map(\.indent), [0, 1, 0])
        XCTAssertEqual(after.caret.index, 2)
    }

    func testBackspaceAtStartSteps() throws {
        let lines = [Line(text: "Hello"), Line(type: .task, indent: 1, priority: true, text: "world")]
        let a = try XCTUnwrap(PageEdit.backspaceAtStart(lines, at: Caret(index: 1, offset: 0)))
        XCTAssertEqual(a.lines[1].indent, 0)
        let b = try XCTUnwrap(PageEdit.backspaceAtStart(a.lines, at: Caret(index: 1, offset: 0)))
        XCTAssertEqual(b.lines[1].type, .text)
        XCTAssertFalse(b.lines[1].priority)
        let c = try XCTUnwrap(PageEdit.backspaceAtStart(b.lines, at: Caret(index: 1, offset: 0)))
        XCTAssertEqual(c.lines.map(\.text), ["Helloworld"])
        XCTAssertEqual(c.caret, Caret(index: 0, offset: 5))
        XCTAssertNil(PageEdit.backspaceAtStart(c.lines, at: Caret(index: 0, offset: 0)))
    }

    func testHandwritingIsNeverDeletedFromTypeMode() {
        let ink = Ink(strokes: [Stroke(k: .writing, p: [0, 0, 0.5])], tx: "hand", n: 1)
        let lines = [Line(text: "abc"), Line(text: "hand", ink: ink), Line(text: "xyz")]
        XCTAssertNil(PageEdit.backspaceAtStart(lines, at: Caret(index: 1, offset: 0)))
        let out = PageEdit.deleteRange(lines, from: Caret(index: 0, offset: 1), to: Caret(index: 2, offset: 1))
        XCTAssertEqual(out.lines.map(\.text), ["ayz", ""])
        XCTAssertEqual(out.lines[1].ink, ink)
        // A handwritten line joins the handwritten line above, ink and all: one paragraph, read again.
        let above = Ink(strokes: [Stroke(k: .writing, r: 0, p: [60, 20, 0.5]), Stroke(k: .writing, r: 1, p: [60, 60, 0.5])], tx: "vinha fazendo", n: 2)
        let o = Ink(strokes: [Stroke(k: .writing, r: 0, p: [44, 20, 0.5], b: true), Stroke(k: .writing, r: 0, p: [70, 20, 0.5])], tx: "suficiente", n: 2)
        let pair = [Line(text: "vinha fazendo", ink: above), Line(text: "suficiente", ink: o)]
        let joined = try! XCTUnwrap(PageEdit.backspaceAtStart(pair, at: Caret(index: 1, offset: 0)))
        XCTAssertEqual(joined.lines.count, 1)
        XCTAssertEqual(joined.lines[0].text, "vinha fazendo suficiente")
        XCTAssertEqual(joined.caret, Caret(index: 0, offset: 13))
        let strokes = joined.lines[0].ink!.strokes
        XCTAssertEqual(strokes.map(\.r), [0, 1, 2, 2])
        XCTAssertEqual(strokes[2].p[1], 100)
        XCTAssertNil(strokes[2].b)
        XCTAssertTrue(joined.lines[0].ink!.needsTranscription)
        XCTAssertEqual(joined.lines[0].ink!.tx, "vinha fazendo suficiente")
        // Corrected by hand: the correction stays when it is read again.
        var corrected = pair
        corrected[1].text = "suficiente!"
        let kept = try! XCTUnwrap(PageEdit.backspaceAtStart(corrected, at: Caret(index: 1, offset: 0)))
        XCTAssertNotEqual(kept.lines[0].ink!.tx, kept.lines[0].text)
        // A selection ending inside a handwritten line keeps that line, with its remaining text.
        let end = PageEdit.deleteRange(lines, from: Caret(index: 0, offset: 1), to: Caret(index: 1, offset: 2))
        XCTAssertEqual(end.lines.map(\.text), ["a", "nd", "xyz"])
    }

    func testInsertTextWithBreaks() {
        let out = PageEdit.insertText([Line(type: .task, text: "ab")], at: Caret(index: 0, offset: 1), "1\n2\n3")
        XCTAssertEqual(out.lines.map(\.text), ["a1", "2", "3b"])
        XCTAssertEqual(out.lines.map(\.type), [.task, .task, .task])
        XCTAssertEqual(out.caret, Caret(index: 2, offset: 1))
    }

    func testUtf16Offsets() {
        let out = PageEdit.enter([Line(text: "👍ok")], at: Caret(index: 0, offset: 2))
        XCTAssertEqual(out.lines.map(\.text), ["👍", "ok"])
    }

    func testDeleteLineLiftsChildren() {
        let lines = [Line(id: "a", type: .task, text: "a"), Line(id: "b", type: .note, indent: 1, text: "b")]
        XCTAssertEqual(PageEdit.deleteLine(lines, id: "a").map(\.indent), [0])
        XCTAssertEqual(PageEdit.deleteLine([lines[0]], id: "a").count, 1)
    }
}

final class ErasedInTypeTests: XCTestCase {
    func testOnlyTranscribedHandwritingWithItsTextDeleted() {
        let w = [Stroke(k: .writing, p: [0, 0, 0.5])]
        let erased = Line(id: "e", ink: Ink(strokes: w, tx: "hi", n: 1))
        let kept = Line(id: "k", text: "hi", ink: Ink(strokes: w, tx: "hi", n: 1))
        let waiting = Line(id: "w", ink: Ink(strokes: w))
        let blank = Line(id: "b")
        XCTAssertEqual(InkPage.erasedInType([erased, kept, waiting, blank]), ["e"])
    }
}

final class TrailTests: XCTestCase {
    func testAnchorIsTodayInsideElseFirstDay() {
        XCTAssertEqual(Period.month("2026-10").anchor(today: "2026-10-29", firstDay: 1), "2026-10-29")
        XCTAssertEqual(Period.month("2026-11").anchor(today: "2026-10-29", firstDay: 1), "2026-11-01")
        XCTAssertEqual(Period.year("2027").anchor(today: "2026-10-29", firstDay: 1), "2027-01-01")
        XCTAssertEqual(Period.day("2026-10-18").anchor(today: "2026-10-29", firstDay: 1), "2026-10-18")
    }

    func testTrail() {
        XCTAssertEqual(
            Period.trail(anchor: "2026-10-29", firstDay: 1),
            [.year("2026"), .month("2026-10"), .week(Dates.weekKey("2026-10-29", firstDay: 1)), .day("2026-10-29")])
        XCTAssertEqual(Period.trail(anchor: "2026-10-29", firstDay: 1, active: ActiveLogs(weekly: false)), [.year("2026"), .month("2026-10"), .day("2026-10-29")])
        XCTAssertTrue(Period.day("a").sameLevel(.day("b")))
        XCTAssertFalse(Period.day("a").sameLevel(.week("b")))
    }
}

final class OpenItemsTests: XCTestCase {
    let today = "2026-10-19"  // Monday, Wk 43
    var n = 0
    func e(_ logId: String, _ text: String, type: EntryType = .task, state: EntryState = .open, slot: String = "", placement: Placement? = nil) -> Entry {
        n += 1
        return Entry(id: "e\(n)", logId: logId, slot: slot, order: "a\(n)", type: type, state: state, text: text, placement: placement, createdAt: "", updatedAt: "")
    }
    func texts(_ entries: [Entry], eventStates: Bool = true) -> [String] {
        OpenItems.items(entries, eventStates: eventStates, firstDay: 1, today: today).map(\.entry.text)
    }

    func testEndedPeriods() {
        let entries = [
            e("weekly:2026-W41", "last-week task"), e("daily:2026-10-18", "yesterday task"), e("daily:2026-10-19", "today task"),
            e("weekly:2026-W43", "this week task"), e("monthly:2026-09", "september task"), e("monthly:2026-10", "this month task"),
            e("daily:2026-10-18", "done", state: .done), e("daily:2026-10-18", "cancelled", state: .cancelled),
            e("daily:2026-10-18", "a note", type: .note), e("daily:2026-10-18", "free text", type: .text),
            e("monthly:2026-09", "day phrase", type: .text, slot: "2026-09-03"), e("collection:01X", "collection task"),
        ]
        XCTAssertEqual(texts(entries), ["september task", "last-week task", "yesterday task"])
    }

    func testEventsOnlyWithEventStates() {
        let entries = [e("daily:2026-10-18", "dinner", type: .event)]
        XCTAssertEqual(texts(entries), ["dinner"])
        XCTAssertEqual(texts(entries, eventStates: false), [])
    }

    func testUnplaced() {
        let entries = [
            e("daily:2026-10-19", "migrated today", state: .migrated, placement: Placement(status: .pending)),
            e("collection:01X", "scheduled", state: .scheduled, placement: Placement(status: .pending)),
            e("daily:2026-10-12", "placed", state: .migrated, placement: Placement(status: .placed, confirmedAt: today)),
        ]
        let items = OpenItems.items(entries, eventStates: true, firstDay: 1, today: today)
        XCTAssertEqual(items.map(\.entry.text), ["migrated today", "scheduled"])
        XCTAssertEqual(items.map(\.category), [.unplaced, .unplaced])
    }

    func testYearItemsArrived() {
        let entries = [
            e("future:2026", "november", slot: "2026-11"), e("future:2026", "october", slot: "2026-10"),
            e("future:2026", "march", slot: "2026-03"), e("future:2026", "march done", state: .done, slot: "2026-03"),
        ]
        let items = OpenItems.items(entries, eventStates: true, firstDay: 1, today: today)
        XCTAssertEqual(items.map(\.entry.text), ["march", "october"])
        XCTAssertEqual(OpenItems.groups(items).map { OpenItems.groupLabel($0) }, ["2026 · March", "2026 · October"])
    }

    func testDueFirst() {
        let entries = [
            e("collection:01X", "pay rent due:2026-10-19"), e("daily:2026-10-25", "future page, overdue due:2026-10-10"),
            e("daily:2026-10-12", "old, no date"), e("weekly:2026-W44", "later due:2026-10-30"),
            e("daily:2026-10-12", "done due:2026-10-01", state: .done), e("daily:2026-10-12", "note due:2026-10-01", type: .note),
        ]
        let groups = OpenItems.groups(OpenItems.items(entries, eventStates: true, firstDay: 1, today: today))
        XCTAssertEqual(groups.map { OpenItems.groupLabel($0) }, ["Due", "Mon, Oct 12"])
        XCTAssertEqual(groups[0].items.map(\.entry.text), ["future page, overdue due:2026-10-10", "pay rent due:2026-10-19"])
    }

    func testGroupLabelsAndAge() {
        let items = OpenItems.items([e("daily:2026-10-05", "b"), e("weekly:2026-W41", "a"), e("daily:2026-10-05", "c")], eventStates: true, firstDay: 1, today: today)
        let groups = OpenItems.groups(items)
        XCTAssertEqual(groups.map { OpenItems.groupLabel($0) }, ["Wk 41 · Oct 5 – 11", "Mon, Oct 5"])
        XCTAssertEqual(groups.map { OpenItems.ageLabel($0.source.end, today: today) }, ["last week", "2 weeks ago"])
        XCTAssertEqual(groups.map(\.items.count), [1, 2])
        XCTAssertEqual(OpenItems.ageLabel("2026-10-18", today: today), "yesterday")
        XCTAssertEqual(OpenItems.ageLabel("2026-10-25", today: today), "")
    }

    func testOpenTodayAndKept() {
        let entries = [e("daily:2026-10-19", "open"), e("daily:2026-10-19", "done", state: .done), e("daily:2026-10-18", "old")]
        XCTAssertEqual(OpenItems.openToday(entries, eventStates: true, firstDay: 1, today: today).map(\.entry.text), ["open"])
        let task = e("daily:2026-10-18", "tap me")
        let item = OpenItems.items([task], eventStates: true, firstDay: 1, today: today)[0]
        var done = task
        done.state = .done
        let shown = OpenItems.withKept(OpenItems.items([done], eventStates: true, firstDay: 1, today: today), kept: [task.id: item], byId: [task.id: done])
        XCTAssertEqual(shown.map(\.entry.state), [.done])
    }

    func testDiffMarksPlacementPendingAndDueDate() {
        let lines = [Line(type: .task, state: .migrated, text: "call due:2026-10-20")]
        let (put, _) = Outline.diff(lines: lines, existing: [], logId: "daily:2026-10-19", slot: "", now: "t")
        XCTAssertEqual(put[0].placement?.status, .pending)
        XCTAssertEqual(put[0].dueDate, "2026-10-20")
        var reopened = lines
        reopened[0].state = .open
        let (again, _) = Outline.diff(lines: reopened, existing: put, logId: "daily:2026-10-19", slot: "", now: "t2")
        XCTAssertNil(again[0].placement)
    }
}

final class ActiveLogsTests: XCTestCase {
    func testAtLeastOneTimeLogStaysOn() {
        XCTAssertEqual(ActiveLogs(monthly: false, weekly: false, daily: false), ActiveLogs(monthly: false, weekly: false, daily: true))
        let onlyWeek = ActiveLogs(monthly: false, weekly: true, daily: false)
        XCTAssertFalse(onlyWeek.canTurnOff(.weekly))
        XCTAssertTrue(onlyWeek.canTurnOff(.daily))
        XCTAssertTrue(ActiveLogs().canTurnOff(.weekly))
    }

    func testWhereThingsGo() {
        let noDays = ActiveLogs(daily: false)
        XCTAssertEqual(noDays.finest("2026-10-29", firstDay: 1), .week(Dates.weekKey("2026-10-29", firstDay: 1)))
        XCTAssertEqual(noDays.below(month: "2026-10-29", firstDay: 1), .week(Dates.weekKey("2026-10-29", firstDay: 1)))
        XCTAssertEqual(ActiveLogs(weekly: false).below(month: "2026-10-29", firstDay: 1), .day("2026-10-29"))
        XCTAssertEqual(ActiveLogs(monthly: false).below(year: "2026-11", firstDay: 1), .day("2026-11-01"))
        XCTAssertEqual(ActiveLogs().below(year: "2026-11", firstDay: 1), .month("2026-11"))
        XCTAssertNil(ActiveLogs(monthly: true, weekly: false, daily: false).below(month: "2026-10-29", firstDay: 1))
    }
}

final class PasteTests: XCTestCase {
    let sample: [Line] = [
        Line(type: .task, priority: true, text: "Call the bank"),
        Line(type: .note, indent: 1, text: "closes at 6"),
        Line(type: .task, state: .done, text: "Buy bread"),
        Line(type: .task, state: .migrated, text: "Renew passport"),
        Line(type: .task, state: .cancelled, inspiration: true, text: "Gym"),
        Line(type: .event, text: "Dinner with Ana"),
        Line(type: .event, state: .done, text: "Concert"),
        Line(type: .event, state: .cancelled, text: "Trip"),
    ]
    struct Shape: Equatable {
        var type: EntryType, state: EntryState, indent: Int, text: String, priority: Bool, inspiration: Bool
    }
    func shape(_ ls: [Line]) -> [Shape] {
        ls.map { Shape(type: $0.type, state: $0.state, indent: $0.indent, text: $0.text, priority: $0.priority, inspiration: $0.inspiration) }
    }
    var doc: ExportDoc { ExportDoc(title: "", sections: [ExportSection(lines: sample)]) }

    func testMarkdownRoundTrips() throws {
        XCTAssertEqual(shape(try XCTUnwrap(Paste.fromText(Export.markdown(doc)))), shape(sample))
        XCTAssertEqual(shape(try XCTUnwrap(Paste.fromText(Export.markdown(doc, style: .dots)))), shape(sample))
    }

    func testPlainTextKeepsTypeStateIndent() throws {
        let got = shape(try XCTUnwrap(Paste.fromText(Export.plain(doc))))
        XCTAssertEqual(got[0], Shape(type: .task, state: .open, indent: 0, text: "Call the bank", priority: true, inspiration: false))
        XCTAssertEqual(got[1], Shape(type: .note, state: .open, indent: 1, text: "closes at 6", priority: false, inspiration: false))
        XCTAssertEqual(got[4], Shape(type: .task, state: .cancelled, indent: 0, text: "Gym", priority: false, inspiration: true))
        XCTAssertEqual(got[5], Shape(type: .event, state: .open, indent: 0, text: "Dinner with Ana", priority: false, inspiration: false))
    }

    func testExactLinesWithFreshIds() throws {
        let got = try XCTUnwrap(Paste.fromJSON(Paste.json(sample)))
        XCTAssertEqual(shape(got), shape(sample))
        XCTAssertNotEqual(got[0].id, sample[0].id)
    }

    func testNotesAppMarkdown() throws {
        let bear = [
            "# Sunday, October 18, 2026", "", "## Âncoras", "  - [x] Devocional", "  - [x] Exercício ", "    - 15m Flow",
            "## Priorities", "  - [x] Hillsong<!-- {\"fold\":true} -->", "    - A note under it", "## Buffer", "  -> Weekly Review",
            "## Blurb", "  A paragraph of free text.",
        ].joined(separator: "\n")
        let got = try XCTUnwrap(Paste.fromText(bear))
        XCTAssertEqual(got.map(\.type), [.heading, .task, .task, .note, .heading, .task, .note, .heading, .task, .heading, .text])
        XCTAssertEqual(got.map(\.indent), [0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0])
        XCTAssertTrue(got[5].collapsed)
        XCTAssertEqual(got[8].state, .migrated)
        XCTAssertEqual(got[5].text, "Hillsong")
    }

    func testOrdinaryTextIsNotParsed() {
        XCTAssertNil(Paste.fromText("Just a sentence.\nAnd another."))
    }

    func testPasteIntoPage() {
        let page = [Line(type: .task, indent: 1, text: "abcd")]
        let pasted = [Line(type: .note, text: "x"), Line(type: .note, indent: 1, text: "y")]
        let mid = PageEdit.paste(page, at: Caret(index: 0, offset: 2), pasted)
        XCTAssertEqual(mid.lines.map(\.text), ["ab", "x", "y", "cd"])
        XCTAssertEqual(mid.lines.map(\.indent), [1, 1, 2, 1])
        XCTAssertEqual(mid.caret, Caret(index: 2, offset: 1))
        let empty = PageEdit.paste([Line()], at: Caret(index: 0, offset: 0), pasted)
        XCTAssertEqual(empty.lines.map(\.text), ["x", "y"])
    }
}

final class InkPreviewTests: XCTestCase {
    let writing = Stroke(k: .writing, p: [10, 10, 0.5, 110, 30, 0.5])
    let drawing = Stroke(k: .drawing, p: [0, 0, 0.5, 200, 100, 0.5])

    func testWhatShows() {
        XCTAssertEqual(InkPreview.kind(Line(ink: Ink(strokes: [writing]))), .writing)
        XCTAssertNil(InkPreview.kind(Line(text: "hi", ink: Ink(strokes: [writing], tx: "hi", n: 1))))
        XCTAssertNil(InkPreview.kind(Line(ink: Ink(strokes: [writing], tx: "", n: 1))))
        XCTAssertEqual(InkPreview.kind(Line(text: "caption", ink: Ink(strokes: [drawing]))), .drawing)
        XCTAssertNil(InkPreview.kind(Line(text: "typed")))
    }

    func testSizes() throws {
        let w = try XCTUnwrap(InkPreview.frame(Line(ink: Ink(strokes: [writing])), maxWidth: 600))
        XCTAssertEqual(w.width, 108 * 0.7, accuracy: 0.01)
        XCTAssertEqual(w.height, 28 * 0.7, accuracy: 0.01)
        // A drawing: 60% of its width + 20 by default (at most 240 + 20), or the width the user gave it.
        let d = try XCTUnwrap(InkPreview.frame(Line(ink: Ink(strokes: [drawing])), maxWidth: 600))
        XCTAssertEqual(d.width, 208 * 0.6 + 20, accuracy: 0.01)
        var sized = Ink(strokes: [drawing])
        sized.view = Ink.View(w: 400, x: 500)
        let s = try XCTUnwrap(InkPreview.frame(Line(ink: sized), maxWidth: 600))
        XCTAssertEqual(s.width, 400)
        XCTAssertEqual(s.x, 200)  // kept inside the column
    }
}

final class DueTests: XCTestCase {
    let today = "2026-10-19"  // Monday
    func p(_ s: String, _ order: DateOrder = .dmy) -> String? { Due.parse(s, today: today, order: order)?.iso }

    func testParsing() {
        XCTAssertEqual(p("2026-12-03"), "2026-12-03")
        XCTAssertEqual(p("23/10"), "2026-10-23")
        XCTAssertEqual(p("10-23"), "2026-10-23")
        XCTAssertEqual(p("03/04"), "2026-04-03")
        XCTAssertEqual(p("03/04", .mdy), "2026-03-04")
        XCTAssertEqual(p("01-02 rest"), "2026-02-01")
        XCTAssertEqual(p("today"), today)
        XCTAssertEqual(p("Tomorrow"), "2026-10-20")
        XCTAssertEqual(p("yesterday"), "2026-10-18")
        XCTAssertEqual(p("fri"), "2026-10-23")
        XCTAssertEqual(p("monday"), "2026-10-19")
        XCTAssertEqual(p("next monday"), "2026-10-26")
        XCTAssertEqual(p("next week"), "2026-10-26")
        XCTAssertEqual(p("next month"), "2026-11-01")
        XCTAssertEqual(p("in 3 days"), "2026-10-22")
        XCTAssertEqual(p("in 2 weeks"), "2026-11-02")
    }

    func testUnfinishedOrInvalid() {
        for s in ["next", "in 3", "tomorrowx", "31/02", "2026-13-01"] { XCTAssertNil(p(s), s) }
    }

    func testResolve() {
        let r = Due.resolve("Call Ana due:tomorrow about rent", today: today)
        XCTAssertEqual(r?.text, "Call Ana due:2026-10-20 about rent")
        XCTAssertEqual(r?.shift, 2)
        XCTAssertEqual(Due.resolve("Pay due:next monday", today: today)?.text, "Pay due:2026-10-26")
        XCTAssertNil(Due.resolve("Pay due:2026-10-26", today: today))
        XCTAssertNil(Due.resolve("Pay due:next", today: today))
        XCTAssertNil(Due.resolve("overdue:today", today: today))
        XCTAssertNil(Due.resolve("a due:fri", today: today, upTo: 7))
        XCTAssertEqual(Due.of("x due:2026-10-26 y"), "2026-10-26")
    }

    func testLabels() {
        XCTAssertEqual(Due.label("2026-10-19", today: today), "Today")
        XCTAssertEqual(Due.label("2026-10-20", today: today), "Tomorrow")
        XCTAssertEqual(Due.label("2026-10-18", today: today), "Yesterday")
        XCTAssertEqual(Due.label("2026-10-23", today: today), "23 Oct")
        XCTAssertEqual(Due.label("2026-10-23", today: today, order: .mdy), "Oct 23")
        XCTAssertEqual(Due.label("2027-01-05", today: today), "5 Jan 2027")
    }

    func testSortingOnRequest() {
        let L = { (t: String, type: EntryType, indent: Int, state: EntryState) in Line(type: type, state: state, indent: indent, text: t) }
        XCTAssertEqual(Due.runs([L("Devocional", .task, 0, .open), L("Italiano", .task, 0, .open), L("Mercado due:2026-10-23", .task, 0, .open)]), [])
        XCTAssertEqual(Due.runs([L("a due:2026-10-20", .task, 0, .open), L("no date", .task, 0, .open), L("b due:2026-10-25", .task, 0, .open)])[0].sorted, true)
        let lines = [
            L("List", .heading, 0, .open), L("b due:2026-10-25", .task, 0, .open), L("child of b", .note, 1, .open),
            L("no date", .task, 0, .open), L("a due:2026-10-20", .task, 0, .cancelled), L("c due:2026-11-02", .task, 0, .open),
            L("free text", .text, 0, .open), L("alone due:2026-10-01", .task, 0, .open),
        ]
        let runs = Due.runs(lines)
        XCTAssertEqual(runs, [Due.Run(items: [1, 3, 4, 5], sorted: false)])
        let sorted = Due.sort(lines, runs[0])
        XCTAssertEqual(sorted.map(\.text), ["List", "a due:2026-10-20", "b due:2026-10-25", "child of b", "c due:2026-11-02", "no date", "free text", "alone due:2026-10-01"])
        XCTAssertEqual(Due.runs(sorted)[0].sorted, true)
    }
}

final class LassoTests: XCTestCase {
    let w = { (pts: [(Double, Double)]) in Stroke(k: .writing, p: pts.flatMap { [$0.0, $0.1, 0.5] }) }

    func testRowWithinReadsTheRuledLineInItsEntry() {
        XCTAssertEqual(PenRules.rowWithin(Box(points: [20, 90, 0.5, 60, 110, 0.5]), top: 40), 1)
    }

    func testMoveToAnotherLineKeepsTheEmptiedLineBlank() {
        // Line a has two words; the second is dropped on line b (its second row on the sheet, y 40-80).
        let a = Line(ink: Ink(strokes: [w([(70, 10), (110, 30)]), w([(200, 10), (240, 30)])], tx: "hi there", n: 2))
        var aText = a
        aText.text = "hi there"
        let b = Line(ink: Ink(strokes: [w([(70, 50), (110, 70)])].map { var s = $0; s.p = s.p.enumerated().map { $0 % 3 == 1 ? $1 - 40 : $1 }; return s }, tx: "x", n: 1))
        var bText = b
        bText.text = "x"
        var dropped = aText.ink!.strokes[1]
        dropped.p = dropped.p.enumerated().map { $0 % 3 == 1 ? $1 + 40 : $1 }
        let (out, to) = InkPage.move([PageStroke(entryId: a.id, index: 1, stroke: dropped)], in: [aText, bText]) { _ in 1 }
        XCTAssertEqual(to, b.id)
        XCTAssertEqual(out.map(\.id), [a.id, b.id])
        XCTAssertEqual(out[0].ink?.strokes.count, 1)
        XCTAssertNil(out[0].ink?.n)  // transcribed again
        XCTAssertEqual(out[1].ink?.strokes.count, 2)
        XCTAssertEqual(out[1].ink?.strokes[1].r, 0)
        XCTAssertEqual(out[1].ink?.strokes[1].box.y0, 10)  // in b's own coordinates
        XCTAssertNil(out[1].ink?.n)
    }

    func testMovingAllHandwritingAwayLeavesABlankLine() {
        var a = Line(type: .task, ink: Ink(strokes: [w([(70, 10), (110, 30)])], tx: "call", n: 1))
        a.text = "call"
        var dropped = a.ink!.strokes[0]
        dropped.p = dropped.p.enumerated().map { $0 % 3 == 1 ? $1 + 120 : $1 }
        let (out, to) = InkPage.move([PageStroke(entryId: a.id, index: 0, stroke: dropped)], in: [a]) { _ in 1 }
        XCTAssertEqual(to, out[3].id)
        XCTAssertEqual(out.count, 4)  // a (now blank), two skipped lines, the moved word
        XCTAssertEqual(out[0].id, a.id)
        XCTAssertNil(out[0].ink)
        XCTAssertEqual(out[0].text, "")
        XCTAssertEqual(out[0].type, .text)
        XCTAssertEqual(out[3].ink?.strokes.first?.box.y0, 10)
    }

    func testHandBulletAndWords() {
        var dot = w([(70, 18), (73, 21)])
        dot.b = true
        let l = Line(ink: Ink(strokes: [dot, w([(100, 10), (160, 30)]), Stroke(k: .drawing, p: [300, 0, 0.5, 400, 30, 0.5])]))
        XCTAssertEqual(InkPage.handBullet(l), Box(x0: 70, y0: 18, x1: 73, y1: 21))
        XCTAssertEqual(InkPage.handWords(l)?.x0, 100)
        XCTAssertEqual(InkPage.handWords(l)?.x1, 160)
        XCTAssertNil(InkPage.handBullet(Line(text: "typed")))
    }
}

final class InlineRunTests: XCTestCase {
    func testRunsMarkWordsAndMarkers() {
        let r = InlineText.runs("a **b *c* d** e")
        // "**" open, "b " bold, "*" open (bold), "c" bold italic, "*" close, " d" bold, "**" close.
        XCTAssertEqual(r.map(\.location), [2, 4, 6, 7, 8, 9, 11])
        XCTAssertEqual(r.map(\.length), [2, 2, 1, 1, 1, 2, 2])
        XCTAssertEqual(r.map(\.isMarker), [true, false, true, false, true, false, true])
        XCTAssertTrue(r[3].bold && r[3].italic)
        XCTAssertEqual(r[0].span?.location, 2)
        XCTAssertEqual(r[0].span?.length, 11)
        XCTAssertEqual(r[2].span?.location, 6)
        XCTAssertTrue(InlineText.runs("2*3 plain").isEmpty)
    }

    func testToggleWrapsAndUnwraps() {
        let on = InlineText.toggle("say hello now", from: 4, to: 9, mark: "**")
        XCTAssertEqual(on.text, "say **hello** now")
        XCTAssertEqual(on.from, 6)
        XCTAssertEqual(on.to, 11)
        let off = InlineText.toggle(on.text, from: on.from, to: on.to, mark: "**")
        XCTAssertEqual(off.text, "say hello now")
        XCTAssertEqual(off.from, 4)
        // Italic inside bold is added, not mistaken for the bold's stars.
        XCTAssertEqual(InlineText.toggle("**hi**", from: 2, to: 4, mark: "*").text, "***hi***")
        // An empty selection leaves the caret between the marks.
        let empty = InlineText.toggle("ab", from: 1, to: 1, mark: "*")
        XCTAssertEqual(empty.text, "a**b")
        XCTAssertEqual(empty.from, 2)
    }
}

final class MoveLineTests: XCTestCase {
    func testMovesTheLineWithItsChildren() {
        let a = Line(text: "a"), d = Line(indent: 0, text: "drawing"), c = Line(indent: 1, text: "child"), b = Line(text: "b")
        let out = PageEdit.moveLine([a, d, c, b], id: d.id, before: 4)
        XCTAssertEqual(out?.map(\.text), ["a", "b", "drawing", "child"])
        XCTAssertEqual(PageEdit.moveLine([a, d, c, b], id: d.id, before: 0)?.map(\.text), ["drawing", "child", "a", "b"])
        // Dropped right where it is: no move.
        XCTAssertNil(PageEdit.moveLine([a, d, c, b], id: d.id, before: 1))
        XCTAssertNil(PageEdit.moveLine([a, d, c, b], id: d.id, before: 3))
    }

    func testNeverDeeperThanOneUnderTheLineAbove() {
        let a = Line(text: "a"), b = Line(indent: 1, text: "b"), d = Line(indent: 2, text: "d")
        let out = PageEdit.moveLine([a, b, d], id: d.id, before: 0)
        XCTAssertEqual(out?.map(\.text), ["d", "a", "b"])
        XCTAssertEqual(out?[0].indent, 0)
    }
}

final class SearchTests: XCTestCase {
    let e = { (id: String, text: String, at: String) in
        Entry(id: id, logId: "daily:2026-10-19", order: "a0", type: .task, text: text, createdAt: at, updatedAt: at)
    }

    func testFindsEveryWordIgnoringCaseAndAccentsNewestFirst() {
        var collapsed = e("3", "banco de dados", "2026-10-15")
        collapsed.collapsed = true
        let entries = [e("1", "Ligar para o Banco", "2026-10-01"), e("2", "Renew passport at the consulate", "2026-10-10"), collapsed, e("4", "   ", "2026-10-16")]
        XCTAssertEqual(Search.entries(entries, query: "BANCO").map(\.item.id), ["3", "1"])
        XCTAssertEqual(Search.entries(entries, query: "passport consul").map(\.item.id), ["2"])
        let r = Search.entries(entries, query: "lígar banco")[0].ranges
        XCTAssertEqual(r.map(\.location), [0, 13])
        XCTAssertEqual(r.map(\.length), [5, 5])
        XCTAssertTrue(Search.entries(entries, query: "  ").isEmpty)
    }

    func testMatchesCollectionNames() {
        let logs = [Log(id: "collection:1", kind: .collection, title: "Livros lidos", createdAt: "", updatedAt: "")]
        XCTAssertEqual(Search.collections(logs, query: "livros").map(\.item.title), ["Livros lidos"])
    }
}

final class LevelStepTests: XCTestCase {
    func testUpAndDownAroundTheAnchor() {
        let day = Period.day("2026-10-30")
        XCTAssertEqual(day.level(-1, today: "2026-10-30", firstDay: 1), .week(Dates.weekKey("2026-10-30", firstDay: 1)))
        XCTAssertNil(day.level(1, today: "2026-10-30", firstDay: 1))
        // A month other than today's goes down to its first day's week.
        XCTAssertEqual(Period.month("2026-09").level(1, today: "2026-10-30", firstDay: 1), .week(Dates.weekKey("2026-09-01", firstDay: 1)))
        XCTAssertNil(Period.year("2026").level(-1, today: "2026-10-30", firstDay: 1))
        // Weekly off: Day goes up to the Month.
        let noWeeks = ActiveLogs(monthly: true, weekly: false, daily: true)
        XCTAssertEqual(day.level(-1, today: "2026-10-30", firstDay: 1, active: noWeeks), .month("2026-10"))
    }
}

final class PrefixSettingsTests: XCTestCase {
    func testChosenPrefixesAndFallbacks() {
        let p = Prefixes(task: "t", event: "", note: "t", heading: "##", priority: "too long")
        XCTAssertEqual(p.task, "t")
        XCTAssertEqual(p.event, "o.")  // empty: default
        XCTAssertEqual(p.note, "-")  // same as task: default
        XCTAssertEqual(p.heading, "##")
        XCTAssertEqual(p.priority, "*")
        XCTAssertEqual(Rapid.match("t ", prefixes: p)?.type, .task)
        XCTAssertEqual(Rapid.leading("## Title", prefixes: p)?.type, .heading)
    }
}

final class SimilarTests: XCTestCase {
    let m = { (a: String, b: String) in Similar.isStrongMatch(Similar.normalize(a), Similar.normalize(b)) }

    func testNormalizes() {
        XCTAssertEqual(Similar.normalize("Ligar para o Banco, até às 18h! due:2026-10-20"), ["ligar", "banco", "ate", "18h"])
    }

    func testMatchesTheSameItemWrittenDifferently() {
        XCTAssertTrue(m("Call the bank", "call bank"))
        XCTAssertTrue(m("Renew passport at the consulate", "renew passport consulate"))
        XCTAssertTrue(m("Pagar aluguel", "pagar o aluguel!"))
        XCTAssertTrue(m("Gym", "gym"))
    }

    func testStaysQuietOnWeakOverlaps() {
        XCTAssertFalse(m("Call the bank", "Call mom"))
        XCTAssertFalse(m("Buy bread", "Buy a new phone case"))
        XCTAssertFalse(m("Gym", "Gym with Ana on Friday"))
    }

    func testPicksTheClosest() {
        let c = ["renew passport", "renew passport at the consulate", "call bank"]
        XCTAssertEqual(Similar.bestMatch("Renew passport at consulate", c) { $0 }, "renew passport at the consulate")
        XCTAssertNil(Similar.bestMatch("Water the plants", c) { $0 })
    }
}
