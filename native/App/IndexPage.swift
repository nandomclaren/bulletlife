// Index (CLAUDE.md 3.1): always on. The current Year at the top, then the collections (pinned ones up there
// too). Days, weeks and months written are not listed (Fernando: it cluttered the Index); Today and the
// calendar sit in the header, where the time pages have them.
import BulletLifeCore
import SwiftData
import SwiftUI

struct IndexPage: View {
    @Binding var period: Period
    var openCollection: (String) -> Void
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<LogRecord> { $0.kind == "collection" }) private var records: [LogRecord]
    @State private var naming = false
    @State private var name = ""
    @State private var date = Date()
    @FocusState private var nameFocused: Bool

    private var repo: Repository { Repository(context: context) }

    var body: some View {
        let collections = records.map(\.log).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let pinned = collections.filter { $0.pinned == true }
        let others = collections.filter { $0.pinned != true }
        let year = Dates.yearOf(Dates.today())
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 20)
                // The Year is always on: the current one is always listed, even before anything is written in it.
                row(kind: S.yearKind, title: year) { period = .year(year) }
                ForEach(pinned) { c in collectionRow(c) }
                Text(S.collections.uppercased())
                    .font(Theme.body(13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                if collections.isEmpty && !naming {
                    Text(S.noCollections).font(Theme.body(15)).foregroundStyle(Theme.muted).padding(.vertical, 8)
                }
                ForEach(others) { c in collectionRow(c) }
                newCollection
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 120)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
    }

    /// Same place as on the time pages: Today, and the calendar to jump to any day (no ‹ ›: there is no
    /// previous Index).
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Spacer()
                DatePicker(S.goToDate, selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: date) { period = .day(Dates.toIso(date)) }
                Button(S.today) { period = .day(Dates.today()) }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
            }
            .font(Theme.body(15))
            Text(S.index)
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(Theme.text)
        }
    }

    private func row(kind: String?, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let kind {
                    Text(kind.uppercased())
                        .font(Theme.body(11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.muted)
                }
                Text(title)
                    .font(Theme.body(18))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func collectionRow(_ c: Log) -> some View {
        let title = c.title.isEmpty ? S.untitled : c.title
        let isPinned = c.pinned == true
        return HStack(spacing: 8) {
            row(kind: isPinned ? S.pinned : nil, title: title) { openCollection(c.id) }
            Button {
                repo.setPinned(id: c.id, !isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14))
                    .foregroundStyle(isPinned ? Theme.task : Theme.muted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPinned ? S.unpin(title) : S.pin(title))
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    @ViewBuilder private var newCollection: some View {
        if naming {
            HStack(spacing: 10) {
                TextField(S.name, text: $name)
                    .font(Theme.body(17))
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(create)
                Button(S.create, action: create)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(S.cancel) {
                    naming = false
                    name = ""
                }
                .foregroundStyle(Theme.muted)
            }
            .font(Theme.body(15))
        } else {
            Button("+ \(S.newCollection)") {
                naming = true
                nameFocused = true
            }
            .font(Theme.body(15, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Theme.task)
        }
    }

    /// Created only by this explicit action (CLAUDE.md principle 7), then opened.
    private func create() {
        let title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let log = repo.createCollection(title: title)
        naming = false
        name = ""
        openCollection(log.id)
    }
}
