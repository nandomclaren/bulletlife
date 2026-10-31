// Global search (CLAUDE.md 5, ⌘K): every entry on every page, collapsed or not, and collection names. A system
// sheet with the search field ready to type; a result opens its page with the entry marked. It only finds and
// opens: nothing is changed from here.
import BulletLifeCore
import SwiftData
import SwiftUI

struct SearchView: View {
    /// Opens a page (with the entry to mark, and the day or month to scroll to on a Month or Year).
    var open: (Place, _ highlight: String?, _ focus: String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [EntryRecord]
    @Query(filter: #Predicate<LogRecord> { $0.kind == "collection" }) private var logs: [LogRecord]
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var query = ""
    @State private var active = true

    var body: some View {
        let collections = logs.map(\.log)
        let titles = Dictionary(collections.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let foundCollections = Search.collections(collections, query: query)
        let found = Search.entries(records.map(\.light), query: query)
        NavigationStack {
            List {
                if !foundCollections.isEmpty {
                    Section(S.collections) {
                        ForEach(foundCollections, id: \.item.id) { hit in
                            Button {
                                go(.collection(hit.item.id), nil, nil)
                            } label: {
                                Text(marked(hit.item.title, hit.ranges)).font(Theme.body(17))
                            }
                        }
                    }
                }
                if !found.isEmpty {
                    Section(S.entriesSection) {
                        ForEach(found, id: \.item.id) { hit in row(hit, titles: titles) }
                    }
                }
                if !query.trimmingCharacters(in: .whitespaces).isEmpty && found.isEmpty && foundCollections.isEmpty {
                    Text(S.nothingFound).foregroundStyle(Theme.muted)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(S.search)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $active, placement: .navigationBarDrawer(displayMode: .always), prompt: S.searchPrompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(S.done) { dismiss() } }
            }
        }
    }

    private func row(_ hit: SearchHit<Entry>, titles: [String: String]) -> some View {
        let e = hit.item
        let source = Source(logId: e.logId, firstDay: firstDay)
        let glyph = States.glyph(e.type, e.state, eventStates: eventStates, doneMark: doneMark)
        return Button {
            let place: Place = source.period.map { .time($0) } ?? .collection(e.logId)
            go(place, e.id, e.slot.isEmpty ? nil : e.slot)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(glyph.isEmpty ? " " : glyph)
                    .font(Theme.body(17, weight: .bold))
                    .foregroundStyle(Theme.color(e.type))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(marked(e.text, hit.ranges))
                        .font(Theme.body(17))
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                    let dates = Due.tokens(e.text).map(\.iso)
                    if !dates.isEmpty {
                        HStack(spacing: 6) { ForEach(dates, id: \.self) { DueBadge(iso: $0) } }
                    }
                    Text(OpenItems.sourceLabel(source, slot: e.slot, collectionTitle: titles[e.logId]))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
    }

    /// The words found, in bold.
    private func marked(_ text: String, _ ranges: [NSRange]) -> AttributedString {
        var a = AttributedString(text)
        for r in ranges {
            if let range = Range(r, in: a) { a[range].font = Theme.body(17, weight: .bold) }
        }
        // Due dates show as pills below, not as "due:2026-10-30" (with the space before them).
        let ns = text as NSString
        for token in Due.tokens(text).reversed() {
            var r = token.range
            if r.location > 0, ns.character(at: r.location - 1) == 32 { r = NSRange(location: r.location - 1, length: r.length + 1) }
            if let range = Range(r, in: a) { a.removeSubrange(range) }
        }
        return a
    }

    private func go(_ place: Place, _ highlight: String?, _ focus: String?) {
        dismiss()
        open(place, highlight, focus)
    }
}
