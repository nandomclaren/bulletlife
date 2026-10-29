// Local storage (SwiftData). Shaped for iCloud sync (CloudKit) from the start: every attribute has a default,
// nothing is unique, no relationships (entries point to their log and parent by id, as in the PWA). Turning
// sync on later is a configuration change, not a migration (CLAUDE.md 17).
import BulletLifeCore
import Foundation
import SwiftData

@Model
final class EntryRecord {
    var uid: String = ""
    var logId: String = ""
    var slot: String = ""
    var parentId: String?
    var orderKey: String = "a0"
    var kind: String = EntryType.text.rawValue
    var state: String = EntryState.open.rawValue
    var text: String = ""
    /// Signifiers, comma separated ("priority,explore").
    var signifiers: String = ""
    var collapsed: Bool = false
    var dueDate: String?
    /// Ink as the PWA's JSON (strokes, tx, n, view).
    @Attribute(.externalStorage) var inkData: Data?
    var placementData: Data?
    var createdAt: String = ""
    var updatedAt: String = ""

    init(_ e: Entry) {
        update(from: e)
    }

    func update(from e: Entry) {
        uid = e.id
        logId = e.logId
        slot = e.slot
        parentId = e.parentId
        orderKey = e.order
        kind = e.type.rawValue
        state = e.state.rawValue
        text = e.text
        signifiers = e.signifiers.map(\.rawValue).joined(separator: ",")
        collapsed = e.collapsed
        dueDate = e.dueDate
        inkData = e.ink.flatMap { try? JSONEncoder().encode($0) }
        placementData = e.placement.flatMap { try? JSONEncoder().encode($0) }
        createdAt = e.createdAt
        updatedAt = e.updatedAt
    }

    var entry: Entry {
        Entry(
            id: uid, logId: logId, slot: slot, parentId: parentId, order: orderKey,
            type: EntryType(rawValue: kind) ?? .text, state: EntryState(rawValue: state) ?? .open, text: text,
            signifiers: signifiers.split(separator: ",").compactMap { Signifier(rawValue: String($0)) }, collapsed: collapsed,
            dueDate: dueDate, ink: inkData.flatMap { try? JSONDecoder().decode(Ink.self, from: $0) },
            placement: placementData.flatMap { try? JSONDecoder().decode(Placement.self, from: $0) },
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

@Model
final class LogRecord {
    var uid: String = ""
    var kind: String = LogKind.collection.rawValue
    var title: String = ""
    var periodStart: String?
    var periodEnd: String?
    var periodLogId: String?
    var pinned: Bool = false
    var createdAt: String = ""
    var updatedAt: String = ""

    init(_ l: Log) {
        uid = l.id
        kind = l.kind.rawValue
        title = l.title
        periodStart = l.periodStart
        periodEnd = l.periodEnd
        periodLogId = l.periodLogId
        pinned = l.pinned ?? false
        createdAt = l.createdAt
        updatedAt = l.updatedAt
    }

    var log: Log {
        Log(
            id: uid, kind: LogKind(rawValue: kind) ?? .collection, title: title, periodStart: periodStart, periodEnd: periodEnd,
            periodLogId: periodLogId, pinned: pinned, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

/// All reads and writes go through here; views never touch SwiftData directly (CLAUDE.md 10). Used from the
/// views only (the main context).
struct Repository {
    let context: ModelContext

    static func now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    private func records(logId: String, slot: String) -> [EntryRecord] {
        let descriptor = FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.logId == logId && $0.slot == slot })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The lines of one page (a log, or one fixed row of a Month or Year).
    func lines(logId: String, slot: String = "") -> [Line] {
        Outline.lines(from: records(logId: logId, slot: slot).map(\.entry))
    }

    /// Writes what changed on a page. A page that is still blank is not created (CLAUDE.md principle 7).
    func save(_ lines: [Line], logId: String, slot: String = "") {
        let records = records(logId: logId, slot: slot)
        let blank = lines.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty && ($0.type == .text || $0.type == .heading) && $0.ink == nil }
        if records.isEmpty && blank { return }
        let (put, remove) = Outline.diff(lines: lines, existing: records.map(\.entry), logId: logId, slot: slot, now: Self.now())
        guard !put.isEmpty || !remove.isEmpty else { return }
        let byId = Dictionary(records.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for e in put {
            if let r = byId[e.id] { r.update(from: e) } else { context.insert(EntryRecord(e)) }
        }
        for id in remove {
            if let r = byId[id] { context.delete(r) }
        }
        try? context.save()
    }

    func collections() -> [Log] {
        let descriptor = FetchDescriptor<LogRecord>(predicate: #Predicate { $0.kind == "collection" })
        return ((try? context.fetch(descriptor)) ?? []).map(\.log).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Replaces everything with a backup (the PWA's Settings › Export everything). Returns the entries read.
    func importBackup(_ data: Data) throws -> Int {
        let backup = try Backup.parse(data)
        try context.delete(model: EntryRecord.self)
        try context.delete(model: LogRecord.self)
        for e in backup.entries { context.insert(EntryRecord(e)) }
        for l in backup.logs { context.insert(LogRecord(l)) }
        try context.save()
        return backup.entries.count
    }

    func entryCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<EntryRecord>())) ?? 0
    }
}
