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
