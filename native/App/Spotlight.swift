// The notebook in the system's search (CLAUDE.md 14): every written entry is indexed on the device
// (Core Spotlight), with where it is. A result opens its page with the entry marked. Nothing leaves the device.
import BulletLifeCore
@preconcurrency import CoreSpotlight
import SwiftUI

@MainActor
enum Spotlight {
    /// Everything again (at launch): what was deleted elsewhere goes too.
    static func indexAll(repo: Repository) {
        let entries = repo.lightEntries()
        let titles = Dictionary(repo.collections().map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let items = entries.compactMap { item($0, titles: titles) }
        CSSearchableIndex.default().deleteAllSearchableItems { _ in CSSearchableIndex.default().indexSearchableItems(items) }
    }

    /// One page again, after it was written.
    static func index(logId: String, slot: String, repo: Repository) {
        let titles = Dictionary(repo.collections().map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let entries = repo.lightEntries().filter { $0.logId == logId && $0.slot == slot }
        // Built here, on the main actor; the index's callback only hands them over.
        let items = entries.compactMap { item($0, titles: titles) }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain(logId, slot)]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items)
        }
    }

    private static func domain(_ logId: String, _ slot: String) -> String { "\(logId)|\(slot)" }

    private static func item(_ e: Entry, titles: [String: String]) -> CSSearchableItem? {
        let text = InlineText.strip(e.text).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !e.logId.hasPrefix("setup:") else { return nil }
        let source = Source(logId: e.logId, firstDay: Prefs.firstDay)
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = text
        attributes.contentDescription = OpenItems.sourceLabel(source, slot: e.slot, collectionTitle: titles[e.logId])
        return CSSearchableItem(uniqueIdentifier: e.id, domainIdentifier: domain(e.logId, e.slot), attributeSet: attributes)
    }

    /// The page and entry a Spotlight result stands for.
    static func target(_ activity: NSUserActivity, repo: Repository) -> (place: Place, id: String, focus: String?)? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let e = repo.lightEntries().first(where: { $0.id == id })
        else { return nil }
        let source = Source(logId: e.logId, firstDay: Prefs.firstDay)
        return (source.period.map { .time($0) } ?? .collection(e.logId), id, e.slot.isEmpty ? nil : e.slot)
    }
}
