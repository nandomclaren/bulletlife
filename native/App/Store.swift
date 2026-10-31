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

    /// The entry without its ink, for queries over the whole notebook (Open items): the ink (often most of an
    /// entry's size) is not read at all.
    var light: Entry {
        Entry(
            id: uid, logId: logId, slot: slot, parentId: parentId, order: orderKey,
            type: EntryType(rawValue: kind) ?? .text, state: EntryState(rawValue: state) ?? .open, text: text,
            signifiers: signifiers.split(separator: ",").compactMap { Signifier(rawValue: String($0)) }, collapsed: collapsed,
            dueDate: dueDate, placement: placementData.flatMap { try? JSONDecoder().decode(Placement.self, from: $0) },
            createdAt: createdAt, updatedAt: updatedAt
        )
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
        // What a page wrote and hasn't saved yet goes in first: a page drawn again (or another view of it)
        // never reads it from before the last edits.
        PageSaver.flushPending(logId: logId, slot: slot)
        return Outline.lines(from: records(logId: logId, slot: slot).map(\.entry))
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
        NotificationCenter.default.post(name: Self.saved, object: nil, userInfo: ["logId": logId, "slot": slot])
    }

    /// A bullet's tap or menu on a page shown only to consult: written to that one entry, as Open items does
    /// (the pages showing it take the change from `changedOutside`). Folding stays on the screen.
    func consult(_ action: LineAction, id: String, eventStates: Bool) {
        update(id: id) { e in
            func toggle(_ s: Signifier) {
                if let k = e.signifiers.firstIndex(of: s) { e.signifiers.remove(at: k) } else { e.signifiers.append(s) }
            }
            switch action {
            case .type(let t):
                e.type = t
                if !States.stateful(t, eventStates: eventStates) { e.state = .open }
            case .state(let s): e.state = s
            case .togglePriority: toggle(.priority)
            case .toggleInspiration: toggle(.inspiration)
            case .toggleExplore: toggle(.explore)
            case .indent, .outdent, .toggleCollapsed, .delete: return
            }
            // Marked > or <: pending until the user writes it at the destination; anything else clears the mark.
            if e.state == .migrated || e.state == .scheduled {
                if e.placement == nil { e.placement = Placement(status: .pending) }
            } else {
                e.placement = nil
            }
        }
    }

    /// Every entry without its ink (fast: for queries over the whole notebook).
    func lightEntries() -> [Entry] {
        ((try? context.fetch(FetchDescriptor<EntryRecord>())) ?? []).map(\.light)
    }

    /// "Link it" (CLAUDE.md 4.4): the user confirms a line is the rewrite of an open item. The original gets its >
    /// (if it was still open) and is marked as written there.
    func link(_ sourceId: String, writtenAs placedId: String) {
        update(id: sourceId) { e in
            if e.state != .migrated && e.state != .scheduled { e.state = .migrated }
            e.placement = Placement(status: .placed, placedEntryId: placedId, confirmedAt: Self.now())
        }
    }

    /// Posted when a page is written: a page shown only to consult (the second of two pages) reads it again.
    /// userInfo: "logId", "slot".
    static let saved = Notification.Name("BulletLife.pageSaved")

    /// Posted when an entry changes from outside its page (Open items): the page showing it takes the new state,
    /// so it never writes back what it showed before. userInfo: "logId", "slot", "id", "state".
    static let changedOutside = Notification.Name("BulletLife.entriesChangedOutside")

    /// Every entry (Open items is a query over all of them, CLAUDE.md 4.1).
    func allEntries() -> [Entry] {
        ((try? context.fetch(FetchDescriptor<EntryRecord>())) ?? []).map(\.entry)
    }

    /// Changes one entry from outside its page: always one entry, by the user's own gesture (CLAUDE.md 4.3).
    func update(id: String, _ change: (inout Entry) -> Void) {
        let descriptor = FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.uid == id })
        guard let record = try? context.fetch(descriptor).first else { return }
        var e = record.entry
        change(&e)
        e.updatedAt = Self.now()
        record.update(from: e)
        try? context.save()
        NotificationCenter.default.post(
            name: Self.changedOutside, object: nil,
            userInfo: [
                "logId": e.logId, "slot": e.slot, "id": e.id, "state": e.state.rawValue, "type": e.type.rawValue,
                "signifiers": e.signifiers.map(\.rawValue),
            ])
    }

    func hasEntries(logId: String) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.logId == logId }))) ?? 0) > 0
    }

    /// Every log id that has something written, for printing.
    func writtenLogIds() -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<EntryRecord>())) ?? []).map(\.logId))
    }

    /// "Set up week" / "Set up month": records that the empty page was set up, so the banner goes away (the
    /// page itself stays empty). Its own id; it names the period it stands for.
    func setUpPeriod(_ s: Source) {
        let now = Self.now()
        let log = Log(
            id: "setup:\(ULID.make())", kind: s.kind, title: "", periodStart: s.start, periodEnd: s.end, periodLogId: s.logId,
            createdAt: now, updatedAt: now)
        context.insert(LogRecord(log))
        try? context.save()
    }

    /// A collection is created only by an explicit user action (CLAUDE.md principle 7).
    func createCollection(title: String) -> Log {
        let now = Self.now()
        let log = Log(id: "collection:\(ULID.make())", kind: .collection, title: title, createdAt: now, updatedAt: now)
        context.insert(LogRecord(log))
        try? context.save()
        return log
    }

    private func logRecord(_ id: String) -> LogRecord? {
        try? context.fetch(FetchDescriptor<LogRecord>(predicate: #Predicate { $0.uid == id })).first
    }

    func collection(_ id: String) -> Log? {
        logRecord(id).map(\.log).flatMap { $0.kind == .collection ? $0 : nil }
    }

    func renameCollection(id: String, title: String) {
        guard let r = logRecord(id) else { return }
        r.title = title
        r.updatedAt = Self.now()
        try? context.save()
    }

    func entryCount(logId: String) -> Int {
        (try? context.fetchCount(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.logId == logId }))) ?? 0
    }

    /// Deletes a collection and everything written in it (only after the user confirmed twice).
    func deleteCollection(id: String) {
        for r in (try? context.fetch(FetchDescriptor<EntryRecord>(predicate: #Predicate { $0.logId == id }))) ?? [] { context.delete(r) }
        if let r = logRecord(id) { context.delete(r) }
        try? context.save()
    }

    /// Pins a collection to the top of the Index, or unpins it.
    func setPinned(id: String, _ pinned: Bool) {
        guard let r = logRecord(id) else { return }
        r.pinned = pinned
        r.updatedAt = Self.now()
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

/// Writes a page a moment after typing stops, not on every key (a write reads and compares the whole page), and
/// at once when asked (the page changes, it leaves the screen, the app goes to the background).
@MainActor
final class PageSaver {
    private var pending: (lines: [Line], logId: String, slot: String, repo: Repository)?
    private var task: Task<Void, Never>?
    /// Every saver alive, so a read of a page can first take what any of them still holds for it.
    private static let all = NSHashTable<PageSaver>.weakObjects()

    init() { Self.all.add(self) }

    static func flushPending(logId: String, slot: String) {
        for saver in all.allObjects where saver.pending?.logId == logId && saver.pending?.slot == slot { saver.flush() }
    }

    func schedule(_ lines: [Line], logId: String, slot: String = "", repo: Repository) {
        pending = (lines, logId, slot, repo)
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        task?.cancel()
        task = nil
        guard let p = pending else { return }
        pending = nil
        p.repo.save(p.lines, logId: p.logId, slot: p.slot)
    }
}

extension Notification {
    /// The new state of an entry changed from outside its page, if this notice is about one of these lines.
    func outsideChange(in lines: [Line], logId: String, slot: String = "") -> (index: Int, state: EntryState)? {
        guard userInfo?["logId"] as? String == logId, userInfo?["slot"] as? String == slot,
            let id = userInfo?["id"] as? String, let i = lines.firstIndex(where: { $0.id == id }),
            let state = (userInfo?["state"] as? String).flatMap(EntryState.init(rawValue:))
        else { return nil }
        return (i, state)
    }

    /// Takes an entry changed from outside its page (Open items, the page beside) into these lines: its state,
    /// type and signifiers, so the page never writes back what it showed before. True if one was.
    func patch(_ lines: inout [Line], logId: String, slot: String = "") -> Bool {
        guard let (i, state) = outsideChange(in: lines, logId: logId, slot: slot) else { return false }
        lines[i].state = state
        if let type = (userInfo?["type"] as? String).flatMap(EntryType.init(rawValue:)) { lines[i].type = type }
        if let marks = userInfo?["signifiers"] as? [String] {
            lines[i].priority = marks.contains(Signifier.priority.rawValue)
            lines[i].inspiration = marks.contains(Signifier.inspiration.rawValue)
            lines[i].explore = marks.contains(Signifier.explore.rawValue)
        }
        return true
    }

    /// Whether this notice (a page saved) is about this page.
    func isAbout(logId: String, slot: String = "") -> Bool {
        userInfo?["logId"] as? String == logId && userInfo?["slot"] as? String == slot
    }
}
