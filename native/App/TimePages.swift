// Time pages beyond Day and Week (CLAUDE.md 3.6 and 5.1): the header every time page shares (the trail
// Year › Month › Week › Day, ‹ Today ›), and the Month and Year pages, whose layout is drawn from the date and
// never stored: only what the user writes is (in slots: a day 'YYYY-MM-DD' or a month 'YYYY-MM').
import BulletLifeCore
import SwiftData
import SwiftUI

/// The header of a time page: the trail (each level one tap away), ‹ Today ›, an accessory (Type | Pen),
/// then the small label and the big title.
struct TimeHeader<Accessory: View>: View {
    @Binding var period: Period
    let label: String
    let title: String
    @ViewBuilder var accessory: Accessory
    @AppStorage("firstDay") private var firstDay = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Trail(period: $period)
                Spacer(minLength: 8)
                accessory
                Button {
                    period = period.moved(-1, firstDay: firstDay)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(S.previous)
                Button(S.today) {
                    period = Period.containing(Dates.today(), like: period, firstDay: firstDay)
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                Button {
                    period = period.moved(1, firstDay: firstDay)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel(S.next)
            }
            .font(Theme.body(15))
            if !label.isEmpty {
                Text(label.uppercased())
                    .font(Theme.body(13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
            }
            Text(title)
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(Theme.text)
        }
    }
}

/// 2026 › Oct › Wk 44 › 29: each item goes to that level, around the day the page is looked at from.
struct Trail: View {
    @Binding var period: Period
    @AppStorage("firstDay") private var firstDay = 1

    var body: some View {
        let anchor = period.anchor(today: Dates.today(), firstDay: firstDay)
        let items = Period.trail(anchor: anchor, firstDay: firstDay)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                    if n > 0 {
                        Text("›").foregroundStyle(Theme.muted.opacity(0.7))
                    }
                    let current = item.sameLevel(period)
                    Button(Self.label(item)) { period = item }
                        .font(Theme.body(15, weight: current ? .bold : .regular))
                        .foregroundStyle(current ? Theme.text : Theme.muted)
                        .buttonStyle(.plain)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    static func label(_ p: Period) -> String {
        switch p {
        case .year(let y): return y
        case .month(let m): return PageView.format("\(m)-01", "MMM")
        case .week(let k): return S.weekShort(Dates.weekNumber(k))
        case .day(let d): return String(Int(d.suffix(2)) ?? 0)
        }
    }
}

/// One stretch of a time page where the user writes (a Month day, Month tasks, a Year month), with the page
/// editor embedded. Loaded and saved on its own; nothing is stored until something is written.
struct SlotEditor: View {
    let logId: String
    let slot: String
    var minHeight: CGFloat = 27
    var fitOneLine = false
    @Environment(\.modelContext) private var context
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var lines: [Line] = []

    private var repo: Repository { Repository(context: context) }

    var body: some View {
        PageEditorView(
            lines: $lines, eventStates: eventStates, doneMark: doneMark, embedded: true, minHeight: minHeight, fitOneLine: fitOneLine
        ) { action, id in
            action.apply(to: &lines, id: id, eventStates: eventStates)
        }
        .onAppear { lines = repo.lines(logId: logId, slot: slot) }
        .onChange(of: lines) { repo.save(lines, logId: logId, slot: slot) }
    }
}

/// Month: every day of the month (number, weekday initial, a line to write the day in), thin rules between
/// weeks with a tappable "Wk 44", then Month tasks.
struct MonthPage: View {
    let ym: String
    @Binding var period: Period
    @AppStorage("firstDay") private var firstDay = 1

    var body: some View {
        let today = Dates.today()
        let current = Dates.monthOf(today) == ym
        let logId = Period.month(ym).logId
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TimeHeader(
                    period: $period, label: PageView.format("\(ym)-01", "MMMM"),
                    title: current ? S.thisMonth : PageView.format("\(ym)-01", "MMMM yyyy")
                ) { EmptyView() }
                .padding(.bottom, 16)
                ForEach(Array(Dates.monthDays(ym).enumerated()), id: \.element) { n, iso in
                    if n > 0 && Dates.weekday(iso) == firstDay { weekRule(iso) }
                    dayRow(iso, today: today, logId: logId)
                }
                Text(S.monthTasks)
                    .font(Theme.body(13, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 28)
                    .padding(.bottom, 8)
                SlotEditor(logId: logId, slot: "", minHeight: 96)
                    .id("\(logId)/tasks")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 240)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
    }

    private func weekRule(_ iso: String) -> some View {
        let key = Dates.weekKey(iso, firstDay: firstDay)
        return HStack(spacing: 8) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            Button(S.weekShort(Dates.weekNumber(key))) { period = .week(key) }
                .font(Theme.body(11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func dayRow(_ iso: String, today: String, logId: String) -> some View {
        let weekend = [0, 6].contains(Dates.weekday(iso))
        let isToday = iso == today
        // Number and initial sit on the baseline of the line written beside them (both start at the top, with
        // the same line height as the text).
        return HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Button {
                    period = .day(iso)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(Int(iso.suffix(2)) ?? 0))
                            .font(Theme.body(17, weight: isToday ? .bold : .regular).monospacedDigit())
                        if isToday { Circle().fill(Theme.task).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 } }
                    }
                    .frame(width: 34, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(PageView.format(iso, "EEEE MMMM d"))
                Text(PageView.format(iso, "EEEEE"))
                    .font(Theme.body(13, weight: .medium))
                    .frame(width: 22, alignment: .leading)
                    .accessibilityHidden(true)
            }
            SlotEditor(logId: logId, slot: iso, minHeight: 27, fitOneLine: true)
                .id("\(logId)/\(iso)")
        }
        .foregroundStyle(weekend ? Theme.muted : Theme.text)
        .frame(minHeight: 44, alignment: .top)
        .padding(.top, 8)
    }
}

/// Year (future log): the twelve months with their names already written and a generous place to write in
/// each; a month's name opens its Month.
struct YearPage: View {
    let year: String
    @Binding var period: Period

    var body: some View {
        let currentMonth = Dates.monthOf(Dates.today())
        let logId = Period.year(year).logId
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                TimeHeader(period: $period, label: "", title: year) { EmptyView() }
                    .padding(.bottom, 16)
                ForEach(0..<12, id: \.self) { n in
                    let ym = Dates.addMonths("\(year)-01", n)
                    Section {
                        SlotEditor(logId: logId, slot: ym, minHeight: 96)
                            .id("\(logId)/\(ym)")
                            .padding(.bottom, 20)
                    } header: {
                        Button {
                            period = .month(ym)
                        } label: {
                            Text(PageView.format("\(ym)-01", "MMMM"))
                                .font(Theme.body(17, weight: .semibold))
                                .foregroundStyle(ym == currentMonth ? Theme.task : Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .background(Theme.paper)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 240)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
    }
}
