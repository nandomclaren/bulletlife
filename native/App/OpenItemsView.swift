// Open items (CLAUDE.md 4): everything left loose, from the whole notebook, grouped by the page it is on, oldest
// first. The panel only shows and consults: the one thing it writes is a single entry's state, by the user's
// own tap (complete, cancel, migrate, schedule, "I wrote it there"). No bulk actions, no copying text.
import BulletLifeCore
import SwiftData
import SwiftUI
import UIKit

/// The quiet button that opens the panel, with how many items are open (no red badge, no alarm).
struct OpenItemsButton: View {
    @Binding var isOpen: Bool
    @Query private var records: [EntryRecord]
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("firstDay") private var firstDay = 1
    /// Settings: the count can be hidden.
    @AppStorage("openCount") private var showCount = true

    var body: some View {
        let count = OpenItems.items(records.map(\.light), eventStates: eventStates, firstDay: firstDay, today: Dates.today()).count
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray")
                if showCount && count > 0 { Text("\(count)").font(Theme.body(14, weight: .medium)).monospacedDigit() }
            }
            .foregroundStyle(Theme.muted)
        }
        .accessibilityLabel(S.openCount(count))
    }
}

struct OpenItemsPanel: View {
    /// Close the day: only what is still open on today's page.
    var onlyToday = false
    /// Opens the page an item is on (a time page or a collection), with the item marked.
    var open: (OpenItem) -> Void
    @Environment(\.modelContext) private var context
    @Query private var records: [EntryRecord]
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("doneMark") private var doneMark = "×"
    /// Items acted on stay listed (with their new state) while the panel is open.
    @State private var kept: [String: OpenItem] = [:]

    private var repo: Repository { Repository(context: context) }

    var body: some View {
        let today = Dates.today()
        let entries = records.map(\.light)
        let byId = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let found =
            onlyToday
            ? OpenItems.openToday(entries, eventStates: eventStates, firstDay: firstDay, today: today)
            : OpenItems.items(entries, eventStates: eventStates, firstDay: firstDay, today: today)
        let items = OpenItems.withKept(found, kept: kept, byId: byId)
        let groups = OpenItems.groups(items)
        let titles = Dictionary(repo.collections().map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        List {
            if groups.isEmpty {
                Text(S.nothingOpen)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
            ForEach(groups, id: \.id) { group in
                Section {
                    ForEach(group.items, id: \.entry.id) { item in row(item) }
                } header: {
                    HStack {
                        Text(OpenItems.groupLabel(group, collectionTitle: titles[group.source.logId]))
                        Spacer()
                        if group.id != "due" { Text(OpenItems.ageLabel(group.source.end, today: today)) }
                    }
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .safeAreaInset(edge: .top) {
            Text(onlyToday ? S.openToday : S.openItems)
                .font(Theme.body(20, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.paper)
        }
        .onDisappear { kept = [:] }
    }

    private func row(_ item: OpenItem) -> some View {
        let e = item.entry
        let stateful = States.stateful(e.type, eventStates: eventStates)
        let glyph = States.glyph(e.type, e.state, eventStates: eventStates, doneMark: doneMark)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Tap: the next state, as on the page.
            Button {
                act(item) { $0.state = States.next($0.state) }
            } label: {
                DoneGlyph(glyph: glyph, type: e.type, state: e.state, check: doneMark == "✓")
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .disabled(!stateful)
            VStack(alignment: .leading, spacing: 6) {
                // Tap the text: its page.
                let shown = DueText.split(e.text)
                Button {
                    open(item)
                } label: {
                    Text(shown.text.isEmpty ? "—" : shown.text)
                        .font(Theme.body(16))
                        .foregroundStyle(stateful && e.state != .open ? Theme.muted : Theme.text)
                        .strikethrough(e.state == .cancelled)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                if !shown.dates.isEmpty {
                    HStack(spacing: 6) { ForEach(shown.dates, id: \.self) { DueBadge(iso: $0) } }
                }
                if item.category == .unplaced && e.placement?.status == .pending {
                    Button(S.wroteItThere) {
                        act(item) { $0.placement = Placement(status: .placed, confirmedAt: Repository.now()) }
                    }
                    .font(Theme.body(13, weight: .medium))
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                }
            }
            if stateful {
                Menu {
                    Button(S.migrate) { mark(item, .migrated) }
                    Button(S.schedule) { mark(item, .scheduled) }
                    if e.state != .open { Button(S.reopen) { act(item) { $0.state = .open } } }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    /// > or < on one entry; marking it again takes it back to open.
    private func mark(_ item: OpenItem, _ state: EntryState) {
        let old = item.entry.state
        act(item) { $0.state = $0.state == state ? .open : state }
        if old != state { Toasts.marked(state) { act(item) { $0.state = old } } }
    }

    private func act(_ item: OpenItem, _ change: (inout Entry) -> Void) {
        kept[item.entry.id] = item
        repo.update(id: item.entry.id) { e in
            change(&e)
            // Marked > or <: pending until the user writes it at the destination; anything else clears the mark.
            if e.state == .migrated || e.state == .scheduled {
                if e.placement == nil { e.placement = Placement(status: .pending) }
            } else {
                e.placement = nil
            }
        }
    }
}

/// A bullet in the panel that plays the done animation (Settings) when its entry is completed or cancelled here.
struct DoneGlyph: UIViewRepresentable {
    let glyph: String
    let type: EntryType
    let state: EntryState
    let check: Bool

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.font = UIFont(name: "AvenirNext-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
        label.isUserInteractionEnabled = false
        context.coordinator.state = state
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = glyph.isEmpty ? " " : glyph
        let color = Theme.ui(type == .text || type == .heading ? "text" : type.rawValue)
        label.textColor = color
        let before = context.coordinator.state
        context.coordinator.state = state
        if before != state, state == .done || state == .cancelled {
            DispatchQueue.main.async {
                DoneFx.play(cancel: state == .cancelled, check: check, bullet: label, mark: label, color: color, host: nil, textRect: nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var state: EntryState = .open
    }
}

/// A due date in a list (Open items, search): the same pill as on the page, beside the text.
struct DueBadge: View {
    let iso: String
    @AppStorage("dateOrder") private var dateOrder = DateOrder.dmy.rawValue

    var body: some View {
        let today = Dates.today()
        let color: Color = {
            switch Due.status(iso, today: today) {
            case .overdue: return Theme.task
            case .today: return Theme.event
            case .future: return Theme.muted
            }
        }()
        HStack(spacing: 4) {
            Image(systemName: "calendar").font(.system(size: 10, weight: .semibold))
            Text(Due.label(iso, today: today, order: DateOrder(rawValue: dateOrder) ?? .dmy)).font(Theme.body(12, weight: .semibold))
        }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.13), in: Capsule())
    }
}

enum DueText {
    /// The text without its stored due dates (they show as pills), and the dates.
    static func split(_ text: String) -> (text: String, dates: [String]) {
        let tokens = Due.tokens(text)
        var t = text as NSString
        for token in tokens.reversed() { t = t.replacingCharacters(in: token.range, with: "") as NSString }
        let plain = (t as String).replacingOccurrences(of: "  ", with: " ").replacingOccurrences(of: " )", with: ")")
            .trimmingCharacters(in: .whitespaces)
        return (plain, tokens.map(\.iso))
    }
}
