// Data model (CLAUDE.md section 9), the same shapes the PWA stores (src/data/types.ts), so a PWA backup
// imports as it is. Field names match the JSON.
import Foundation

public enum EntryType: String, Codable, CaseIterable, Sendable {
    case task, event, note, text, heading
}

public enum EntryState: String, Codable, CaseIterable, Sendable {
    case open, done, cancelled, migrated, scheduled
}

public enum Signifier: String, Codable, CaseIterable, Sendable {
    case priority, inspiration, explore
}

public struct Placement: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case pending, placed }
    public var status: Status
    public var placedEntryId: String?
    public var confirmedAt: String?

    public init(status: Status, placedEntryId: String? = nil, confirmedAt: String? = nil) {
        self.status = status
        self.placedEntryId = placedEntryId
        self.confirmedAt = confirmedAt
    }
}

public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var logId: String
    /// Fixed layout row: 'YYYY-MM-DD' in a Month, 'YYYY-MM' in a Year. '' when the entry lives in the page body.
    public var slot: String
    public var parentId: String?
    /// Fractional index (OrderKey): entries of a page sort by it.
    public var order: String
    public var type: EntryType
    public var state: EntryState
    public var text: String
    public var signifiers: [Signifier]
    public var collapsed: Bool
    public var dueDate: String?
    /// Written or drawn with the pen: vector strokes.
    public var ink: Ink?
    public var placement: Placement?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String, logId: String, slot: String = "", parentId: String? = nil, order: String, type: EntryType = .text,
        state: EntryState = .open, text: String = "", signifiers: [Signifier] = [], collapsed: Bool = false,
        dueDate: String? = nil, ink: Ink? = nil, placement: Placement? = nil, createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.logId = logId
        self.slot = slot
        self.parentId = parentId
        self.order = order
        self.type = type
        self.state = state
        self.text = text
        self.signifiers = signifiers
        self.collapsed = collapsed
        self.dueDate = dueDate
        self.ink = ink
        self.placement = placement
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, logId, slot, parentId, order, type, state, text, signifiers, collapsed, dueDate, ink, placement, createdAt, updatedAt
    }

    // Lenient: older rows may lack a field; a missing one takes its default instead of failing the import.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        logId = try c.decode(String.self, forKey: .logId)
        slot = try c.decodeIfPresent(String.self, forKey: .slot) ?? ""
        parentId = try c.decodeIfPresent(String.self, forKey: .parentId)
        order = try c.decodeIfPresent(String.self, forKey: .order) ?? "a0"
        type = (try? c.decode(EntryType.self, forKey: .type)) ?? .text
        state = (try? c.decode(EntryState.self, forKey: .state)) ?? .open
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        signifiers = (try? c.decode([Signifier].self, forKey: .signifiers)) ?? []
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        ink = try? c.decodeIfPresent(Ink.self, forKey: .ink)
        placement = try? c.decodeIfPresent(Placement.self, forKey: .placement)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }
}

public enum LogKind: String, Codable, Sendable {
    case future, monthly, weekly, daily, collection
}

public struct Log: Codable, Equatable, Identifiable, Sendable {
    /// Time logs use deterministic ids ('daily:2026-10-18'); collections 'collection:<ULID>'.
    public var id: String
    public var kind: LogKind
    public var title: String
    public var periodStart: String?
    public var periodEnd: String?
    /// A period page set up explicitly ("Set up week"): the time log it stands for, e.g. 'weekly:2026-W43'.
    public var periodLogId: String?
    /// A collection pinned to the top of the Index.
    public var pinned: Bool?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String, kind: LogKind, title: String, periodStart: String? = nil, periodEnd: String? = nil,
        periodLogId: String? = nil, pinned: Bool? = nil, createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.periodLogId = periodLogId
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Ink

/// Height of one ruled line in Pen mode, in points (the PWA's CSS px: the same numbers on the same page).
public let inkRow: Double = 40

public enum StrokeKind: String, Codable, Sendable {
    /// Writing: one ruled line, transcribed.
    case writing = "w"
    /// Drawing: never transcribed.
    case drawing = "d"
}

public struct Stroke: Codable, Equatable, Sendable {
    public var k: StrokeKind
    /// Color token: 'ink', 'task', 'event' or 'note' (re-colors with the theme).
    public var c: String
    /// Writing: the ruled row (within the entry) the stroke belongs to.
    public var r: Int
    /// Flat [x, y, pressure, ...]: x from the sheet's left edge, y from the entry's top.
    public var p: [Double]
    /// Pressure came from a real pen.
    public var pen: Bool?
    /// The hand-drawn bullet of the line (found when transcribing).
    public var b: Bool?
    /// Pen size (stroke diameter) when not the default.
    public var s: Double?

    public init(k: StrokeKind, c: String = "ink", r: Int = 0, p: [Double], pen: Bool? = nil, b: Bool? = nil, s: Double? = nil) {
        self.k = k
        self.c = c
        self.r = r
        self.p = p
        self.pen = pen
        self.b = b
        self.s = s
    }

    enum CodingKeys: String, CodingKey { case k, c, r, p, pen, b, s }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        k = (try? c.decode(StrokeKind.self, forKey: .k)) ?? .writing
        self.c = try c.decodeIfPresent(String.self, forKey: .c) ?? "ink"
        r = try c.decodeIfPresent(Int.self, forKey: .r) ?? 0
        p = try c.decodeIfPresent([Double].self, forKey: .p) ?? []
        pen = try c.decodeIfPresent(Bool.self, forKey: .pen)
        b = try c.decodeIfPresent(Bool.self, forKey: .b)
        s = try c.decodeIfPresent(Double.self, forKey: .s)
    }

    public var box: Box { Box(points: p) }
}

public struct Ink: Codable, Equatable, Sendable {
    public struct View: Codable, Equatable, Sendable {
        public var w: Double
        public var x: Double
        public init(w: Double, x: Double) {
            self.w = w
            self.x = x
        }
    }

    public var strokes: [Stroke]
    /// Text the last transcription wrote; while the entry's text still equals it, a new one may replace it.
    public var tx: String?
    /// Writing strokes the last transcription read; a different count means the ink changed since.
    public var n: Int?
    /// A drawing's size and place in Type mode.
    public var view: View?

    public init(strokes: [Stroke], tx: String? = nil, n: Int? = nil, view: View? = nil) {
        self.strokes = strokes
        self.tx = tx
        self.n = n
        self.view = view
    }

    public var writingCount: Int { strokes.filter { $0.k == .writing }.count }
    public var hasWriting: Bool { writingCount > 0 }
    /// Has writing the last transcription did not read.
    public var needsTranscription: Bool { hasWriting && n != writingCount }

    /// Ruled rows the ink takes: writing counts the rows it was written on; drawings every row they cover.
    public var rows: Int {
        var rows = 0
        for s in strokes {
            rows = max(rows, s.k == .writing ? s.r + 1 : Int(((s.box.y1 + 4) / inkRow).rounded(.up)))
        }
        return rows
    }
}

public struct Box: Equatable, Sendable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(x0: Double, y0: Double, x1: Double, y1: Double) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    /// The box of flat [x, y, pressure, ...] points.
    public init(points p: [Double]) {
        var b = Box(x0: .infinity, y0: .infinity, x1: -.infinity, y1: -.infinity)
        var i = 0
        while i + 1 < p.count {
            b.x0 = min(b.x0, p[i])
            b.x1 = max(b.x1, p[i])
            b.y0 = min(b.y0, p[i + 1])
            b.y1 = max(b.y1, p[i + 1])
            i += 3
        }
        self = b
    }

    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }
}

// MARK: - Backup (the PWA's Settings › Export everything)

public struct Backup: Codable, Sendable {
    public static let format = 1

    public var app: String
    public var format: Int
    public var createdAt: String
    /// Collections only (time pages need no rows).
    public var logs: [Log]
    public var entries: [Entry]

    public init(createdAt: String, logs: [Log], entries: [Entry]) {
        app = "bullet-life"
        format = Backup.format
        self.createdAt = createdAt
        self.logs = logs
        self.entries = entries
    }

    public enum Problem: Error, Equatable {
        case notJSON, notBackup, newerFormat
    }

    /// Reads a backup file written by the PWA or this app.
    public static func parse(_ data: Data) throws -> Backup {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Problem.notJSON }
        guard object["app"] as? String == "bullet-life", let format = object["format"] as? Int else { throw Problem.notBackup }
        if format > Backup.format { throw Problem.newerFormat }
        do {
            return try JSONDecoder().decode(Backup.self, from: data)
        } catch {
            throw Problem.notBackup
        }
    }
}
