// A Habits collection (Fernando's spread from his notebook): one page per month. The days of the month are
// columns (number and weekday initial, a quiet rule between weeks, as in the Month), the habits are rows the
// user writes, and each day of a habit takes a mark: done (× or ✓, as in Settings), not done (a dot) or
// skipped (a dash, no penalty). A tap moves the mark on; holding a day offers the four. Nothing is carried to
// the next month: its habits are written again by hand (CLAUDE.md principle 1).
import BulletLifeCore
import SwiftData
import SwiftUI

struct HabitsPage: View {
    let collection: Log
    var onIndex: () -> Void
    @EnvironmentObject private var nav: Navigator
    @Environment(\.modelContext) private var context
    @Environment(\.pageRole) private var role
    @Environment(\.focusMode) private var focus
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var month = Dates.monthOf(Dates.today())
    @State private var rows: [Entry] = []
    @State private var title = ""
    @State private var newName = ""
    /// The day opened from Open items: its column is marked for a moment.
    @State private var marked: String?
    @State private var removing: Entry?
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false
    @FocusState private var addingFocused: Bool

    private var repo: Repository { Repository(context: context) }
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Narrower on the iPhone, so a week of days still fits beside the names.
    private var nameWidth: CGFloat { sizeClass == .compact ? 112 : 160 }
    private let cell: CGFloat = 30
    private let rowHeight: CGFloat = 38

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
                // The names stay put (iPad upright, iPhone); only the days scroll sideways.
                HStack(alignment: .top, spacing: 0) {
                    names
                        .frame(width: nameWidth, alignment: .leading)
                        .overlay(alignment: .trailing) { Theme.rule.frame(width: 1) }
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            grid.padding(.trailing, 24)
                        }
                        .onChange(of: marked) { if let marked { withAnimation { proxy.scrollTo(marked, anchor: .center) } } }
                        .onAppear {
                            // Opens on today's week, when today is in this month.
                            let today = Dates.today()
                            if Dates.monthOf(today) == month { DispatchQueue.main.async { proxy.scrollTo(today, anchor: .center) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
        .onAppear {
            title = collection.title
            applyFocus()
            load()
        }
        .onChange(of: month) { load() }
        .onChange(of: nav.focus) { applyFocus() }
        .onChange(of: nav.highlight) { applyFocus() }
        .onChange(of: collection.id) {
            title = collection.title
            load()
        }
        .onDisappear(perform: rename)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if role != .second && !focus {
                HStack(spacing: 12) {
                    Button {
                        rename()
                        onIndex()
                    } label: {
                        Text("‹ \(S.index)")
                    }
                    .font(Theme.body(15))
                    Spacer()
                    Button { month = Dates.addMonths(month, -1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                        .accessibilityLabel(S.previousMonth)
                    Button(S.today) { month = Dates.monthOf(Dates.today()) }
                        .buttonStyle(.bordered)
                        .font(Theme.body(15, weight: .medium))
                    Button { month = Dates.addMonths(month, 1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                        .accessibilityLabel(S.nextMonth)
                    Menu {
                        Button(S.deleteCollection, role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(S.collectionMenu)
                }
            }
            Text(PageView.format("\(month)-01", "MMMM yyyy").uppercased())
                .font(Theme.body(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            TextField(S.name, text: $title)
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(rename)
        }
        .confirmationDialog(S.deleteTitle(collection.title), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(S.delete, role: .destructive) { confirmDeleteAgain = true }
        } message: {
            Text(S.deleteMessage(repo.entryCount(logId: collection.id)))
        }
        .alert(S.deleteAgainTitle, isPresented: $confirmDeleteAgain) {
            Button(S.deleteForever, role: .destructive) {
                repo.deleteCollection(id: collection.id)
                onIndex()
            }
            Button(S.cancel, role: .cancel) {}
        } message: {
            Text(S.deleteAgainMessage)
        }
        .confirmationDialog(removing?.text ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(S.deleteHabit, role: .destructive) {
                if let r = removing { repo.deleteHabit(id: r.id) }
                removing = nil
                load()
            }
        }
    }

    // MARK: Grid

    private var days: [String] { Dates.monthDays(month) }

    /// A quiet rule before each new week (as between the Month's weeks).
    private func weekStarts(_ iso: String) -> Bool {
        iso != days.first && Dates.weekday(iso) == firstDay
    }

    /// The fixed column: the habits' names, and the line to write a new one.
    private var names: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: headerHeight)
            ForEach(rows) { row in
                TextField(S.newHabit, text: name(row))
                    .font(Theme.body(16))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .padding(.trailing, 8)
                    .frame(height: rowHeight)
                    .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1) }
                    .contextMenu {
                        Button(S.deleteHabit, systemImage: "trash", role: .destructive) { removing = row }
                    }
            }
            if role != .second {
                TextField(S.newHabit, text: $newName)
                    .font(Theme.body(16))
                    .focused($addingFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.trailing, 8)
                    .frame(height: rowHeight)
            }
        }
    }

    private let headerHeight: CGFloat = 40

    /// The days: a header of numbers and initials, then one row of marks per habit.
    private var grid: some View {
        let today = Dates.today()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { iso in
                    VStack(spacing: 2) {
                        Text(String(Int(iso.suffix(2)) ?? 0))
                            .font(Theme.body(12, weight: iso == today ? .bold : .medium).monospacedDigit())
                        Text(PageView.format(iso, "EEEEE"))
                            .font(Theme.body(11, weight: .medium))
                    }
                    .foregroundStyle(iso == today ? Theme.task : [0, 6].contains(Dates.weekday(iso)) ? Theme.muted : Theme.text)
                    .frame(width: cell, height: headerHeight)
                    .overlay(alignment: .leading) { if weekStarts(iso) { Theme.rule.frame(width: 1) } }
                    .accessibilityLabel(PageView.format(iso, "EEEE MMMM d"))
                    .id(iso)
                }
            }
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element) { i, iso in
                        dayCell(row, day: i + 1, iso: iso, today: today)
                    }
                }
                .frame(height: rowHeight)
                .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1) }
            }
            if role != .second {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { iso in
                        Color.clear.frame(width: cell, height: rowHeight)
                            .overlay(alignment: .leading) { if weekStarts(iso) { Theme.rule.frame(width: 1) } }
                    }
                }
            }
        }
    }

    private func dayCell(_ row: Entry, day: Int, iso: String, today: String) -> some View {
        let mark = Habits.mark(row.marks, day: day)
        return Button {
            set(row, day: day, mark.next)
        } label: {
            glyph(mark)
                .frame(width: cell, height: rowHeight)
                .background(columnTint(iso, today: today))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) { if weekStarts(iso) { Theme.rule.frame(width: 1) } }
        .contextMenu {
            ForEach([HabitMark.done, .missed, .skipped, .empty], id: \.self) { m in
                Button(S.habitMarks[m] ?? "") { set(row, day: day, m) }
            }
        }
        .accessibilityLabel("\(row.text), \(PageView.format(iso, "MMMM d")): \(S.habitMarks[mark] ?? "")")
    }

    @ViewBuilder private func glyph(_ mark: HabitMark) -> some View {
        switch mark {
        case .done:
            Text(doneMark).font(Theme.body(17, weight: .semibold)).foregroundStyle(Theme.task)
        case .missed:
            Circle().fill(Theme.text).frame(width: 5, height: 5)
        case .skipped:
            Capsule().fill(Theme.muted).frame(width: 11, height: 2)
        case .empty:
            // The paper's dot grid: a faint dot where nothing is marked yet.
            Circle().fill(Theme.rule).frame(width: 3, height: 3)
        }
    }

    private func columnTint(_ iso: String, today: String) -> Color {
        if iso == marked { return Theme.task.opacity(0.14) }
        if iso == today { return Theme.task.opacity(0.06) }
        return .clear
    }

    // MARK: Writing

    private func name(_ row: Entry) -> Binding<String> {
        Binding(
            get: { rows.first { $0.id == row.id }?.text ?? row.text },
            set: { text in
                guard let i = rows.firstIndex(where: { $0.id == row.id }) else { return }
                rows[i].text = text
                repo.saveHabit(rows[i])
            })
    }

    private func set(_ row: Entry, day: Int, _ mark: HabitMark) {
        guard let i = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[i].marks = Habits.setting(rows[i].marks, day: day, to: mark)
        repo.saveHabit(rows[i])
    }

    /// A habit is added only by writing it (one row; nothing is copied from another month).
    private func add() {
        let text = newName.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let order = (try? OrderKey.between(rows.last?.order, nil)) ?? "a\(rows.count)"
        let now = Repository.now()
        let e = Entry(id: ULID.make(), logId: collection.id, slot: month, order: order, text: text, createdAt: now, updatedAt: now)
        repo.saveHabit(e)
        newName = ""
        load()
        addingFocused = true
    }

    private func load() {
        rows = repo.habits(logId: collection.id, month: month)
    }

    private func rename() {
        let next = title.trimmingCharacters(in: .whitespaces)
        if next.isEmpty { title = collection.title } else if next != collection.title { repo.renameCollection(id: collection.id, title: next) }
    }

    /// Opened on a day (from Open items, or a search result's month): that month, with the day's column marked.
    private func applyFocus() {
        // Only a fresh opening with a target (a stale focus from another page is left alone).
        guard nav.highlight != nil, let f = nav.focus, f.count >= 7 else { return }
        let ym = String(f.prefix(7))
        if ym != month { month = ym }
        guard f.count == 10 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            marked = f
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { if marked == f { marked = nil } } }
        }
    }
}
