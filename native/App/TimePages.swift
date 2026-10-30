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
    /// Scrolled down: the small label goes and the title shrinks, leaving more of the page in view.
    var compact = false
    @ViewBuilder var accessory: Accessory
    @AppStorage("firstDay") private var firstDay = 1
    @State private var picking = false
    @State private var picked = Date()
    /// The open book's right page shows only its name; ‹ › on the left page turn two pages.
    @Environment(\.pageRole) private var role
    @Environment(\.pageStep) private var step
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The open book's right page and a page consulted beside: no controls of their own.
            if role == .main { controls }
            if !label.isEmpty && !compact {
                Text(label.uppercased())
                    .font(Theme.body(13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
            Text(title)
                .font(Theme.body(compact ? 19 : 30, weight: .bold))
                .foregroundStyle(Theme.text)
        }
        // The other page's name sits level with the left page's (where the controls would be).
        .padding(.top, role == .main ? 0 : 44)
        .animation(.easeInOut(duration: 0.2), value: compact)
    }

    /// On a narrow screen (iPhone) the trail gets a line of its own, above ‹ Today › and the calendar; there is
    /// no room for both on one.
    @ViewBuilder private var controls: some View {
        if sizeClass == .compact {
            VStack(alignment: .leading, spacing: 8) {
                Trail(period: $period)
                HStack(spacing: 12) {
                    buttons
                    Spacer(minLength: 0)
                    accessory
                }
                .font(Theme.body(15))
            }
        } else {
            HStack(spacing: 12) {
                Trail(period: $period)
                Spacer(minLength: 8)
                accessory
                buttons
            }
            .font(Theme.body(15))
        }
    }

    /// ‹ Today › and the calendar.
    @ViewBuilder private var buttons: some View {
        Button {
            period = period.moved(-step, firstDay: firstDay)
        } label: {
            Image(systemName: "chevron.left")
        }
        .accessibilityLabel(S.previous)
        // Today: this level's period of today; holding it goes to the finest log on, today.
        Text(S.today)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.rule))
            .foregroundStyle(Theme.task)
            .onTapGesture { period = Period.containing(Dates.today(), like: period, firstDay: firstDay) }
            .onLongPressGesture { period = Prefs.active.finest(Dates.today(), firstDay: firstDay) }
            .accessibilityAddTraits(.isButton)
        Button {
            period = period.moved(step, firstDay: firstDay)
        } label: {
            Image(systemName: "chevron.right")
        }
        .accessibilityLabel(S.next)
        // The calendar: any day, at this page's level.
        Button {
            picked = Dates.fromIso(period.anchor(today: Dates.today(), firstDay: firstDay))
            picking = true
        } label: {
            Image(systemName: "calendar")
        }
        .accessibilityLabel(S.goToDate)
        .popover(isPresented: $picking) {
            DatePicker(S.goToDate, selection: $picked, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(width: 320)
                .padding()
                .presentationCompactAdaptation(.popover)
                .onChange(of: picked) {
                    period = Period.containing(Dates.toIso(picked), like: period, firstDay: firstDay)
                    picking = false
                }
        }
    }
}

/// 2026 › Oct › Wk 44 › 29: each item goes to that level, around the day the page is looked at from.
struct Trail: View {
    @Binding var period: Period
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("logMonthly") private var monthly = true
    @AppStorage("logWeekly") private var weekly = true
    @AppStorage("logDaily") private var daily = true

    var body: some View {
        let anchor = period.anchor(today: Dates.today(), firstDay: firstDay)
        // Levels turned off in Settings are left out (the Year is always on).
        let items = Period.trail(anchor: anchor, firstDay: firstDay, active: ActiveLogs(monthly: monthly, weekly: weekly, daily: daily))
        // When it doesn't fit (iPhone), it scrolls sideways, and the current level stays in view.
        ScrollViewReader { proxy in
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
                        .id(n)
                }
            }
        }
        .onAppear { reveal(proxy, items) }
        .onChange(of: period) { reveal(proxy, items) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func reveal(_ proxy: ScrollViewProxy, _ items: [Period]) {
        guard let n = items.firstIndex(where: { $0.sameLevel(period) }) else { return }
        proxy.scrollTo(n, anchor: .trailing)
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
    var highlight: String? = nil
    @Environment(\.modelContext) private var context
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var lines: [Line] = []
    @State private var saver = PageSaver()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.pageRole) private var role

    private var repo: Repository { Repository(context: context) }
    /// The second of two pages: read, not written (only a bullet's tap or menu, one entry at a time).
    private var consulting: Bool { role == .second }

    var body: some View {
        PageEditorView(
            lines: $lines, eventStates: eventStates, doneMark: doneMark, embedded: true, minHeight: minHeight, fitOneLine: fitOneLine,
            highlight: lines.contains { $0.id == highlight } ? highlight : nil, readOnly: consulting,
            onLineDone: { [logId] in Rewrites.check($0, logId: logId, repo: repo) },
            onSelection: { PageSelection.set(logId: logId, $0) }
        ) { action, id in
            // > or <: "Migrated" or "Scheduled", with Undo.
            if case .state(let s) = action, let old = lines.first(where: { $0.id == id })?.state, old != s {
                let slot = $lines
                let consulted = consulting
                let store = repo
                let states = eventStates
                Toasts.marked(s) {
                    if consulted {
                        store.consult(.state(old), id: id, eventStates: states)
                    } else if let i = slot.wrappedValue.firstIndex(where: { $0.id == id }) {
                        slot.wrappedValue[i].state = old
                    }
                }
            }
            if consulting, action != .toggleCollapsed {
                repo.consult(action, id: id, eventStates: eventStates)
            } else {
                action.apply(to: &lines, id: id, eventStates: eventStates)
            }
        }
        .onAppear { lines = repo.lines(logId: logId, slot: slot) }
        .onReceive(NotificationCenter.default.publisher(for: Repository.changedOutside)) { note in
            _ = note.patch(&lines, logId: logId, slot: slot)
        }
        .onReceive(NotificationCenter.default.publisher(for: Repository.saved)) { note in
            if consulting && note.isAbout(logId: logId, slot: slot) { lines = repo.lines(logId: logId, slot: slot) }
        }
        .onChange(of: lines) { if !consulting { saver.schedule(lines, logId: logId, slot: slot, repo: repo) } }
        .onChange(of: scenePhase) { if scenePhase != .active { saver.flush() } }
        .onDisappear { saver.flush() }
    }
}

/// Month: every day of the month (number, weekday initial, a line to write the day in), thin rules between
/// weeks with a tappable "Wk 44", then Month tasks. Coming up from a day or week, it scrolls to that day and
/// marks it briefly.
struct MonthPage: View {
    let ym: String
    @Binding var period: Period
    @EnvironmentObject private var nav: Navigator
    /// Consulted beside another page: read only, its days and months don't navigate.
    @Environment(\.pageRole) private var role
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("logMonthly") private var monthly = true
    @AppStorage("logWeekly") private var weekly = true
    @AppStorage("logDaily") private var daily = true
    @State private var marked: String?
    /// Scrolled past the first days: the header's title shrinks.
    @State private var scrolled = false
    @State private var width: CGFloat = 0
    /// Another page beside it (two pages, open book): one column.
    @Environment(\.pageBeside) private var beside

    private var active: ActiveLogs { ActiveLogs(monthly: monthly, weekly: weekly, daily: daily) }

    /// On its own on a wide screen, the days and Month tasks sit side by side, like an open notebook (as in
    /// the PWA); with a page beside it, or narrower, Month tasks follow the days.
    private var sideBySide: Bool { !beside && width >= 900 }

    var body: some View {
        let today = Dates.today()
        let current = Dates.monthOf(today) == ym
        let logId = Period.month(ym).logId
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if sideBySide {
                        HStack(alignment: .top, spacing: 48) {
                            days(today: today, logId: logId).frame(maxWidth: .infinity, alignment: .leading)
                            tasks(logId: logId, first: true).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: 1240)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            days(today: today, logId: logId)
                            tasks(logId: logId, first: false)
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 240)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .scrollDismissesKeyboard(.interactively)
            .remembersScroll(nav, place: .time(.month(ym)))
            .background(Theme.paper)
            // The header floats over the days, which scroll under it, seen blurred through.
            .safeAreaInset(edge: .top, spacing: 0) {
                TimeHeader(
                    period: $period, label: PageView.format("\(ym)-01", "MMMM"),
                    title: current ? S.thisMonth : PageView.format("\(ym)-01", "MMMM yyyy"), compact: scrolled
                ) { EmptyView() }
                .floatingHeaderStyle()
            }
            .onAppear { reveal(proxy, logId: logId) }
            .onChange(of: nav.focus) { reveal(proxy, logId: logId) }
            .onChange(of: nav.highlight) { reveal(proxy, logId: logId) }
        }
    }

    private func days(today: String, logId: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrolledMarker(scrolled: $scrolled)
            ForEach(Array(Dates.monthDays(ym).enumerated()), id: \.element) { n, iso in
                if n > 0 && Dates.weekday(iso) == firstDay { weekRule(iso) }
                dayRow(iso, today: today, logId: logId)
            }
        }
    }

    private func tasks(logId: String, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(S.monthTasks)
                .font(Theme.body(13, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.muted)
                .padding(.top, first ? 8 : 28)
                .padding(.bottom, 8)
            SlotEditor(logId: logId, slot: "", minHeight: 96, highlight: nav.highlight)
                .id("\(logId)/tasks")
        }
    }

    /// Scrolls to the day you came from (or an entry's day, from Open items) and marks it for a moment.
    private func reveal(_ proxy: ScrollViewProxy, logId: String) {
        let target: String
        if let focus = nav.focus, Dates.monthOf(focus) == ym, focus.count == 10 {
            target = focus
        } else if nav.highlight != nil {
            target = "tasks"
        } else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("\(logId)/\(target)", anchor: .center) }
            if target != "tasks" {
                marked = target
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { marked = nil } }
            }
        }
    }

    @ViewBuilder private func weekRule(_ iso: String) -> some View {
        let key = Dates.weekKey(iso, firstDay: firstDay)
        HStack(spacing: 8) {
            Rectangle().fill(Theme.rule).frame(height: 1)
            if weekly {
                Button(S.weekShort(Dates.weekNumber(key))) { period = .week(key) }
                    .font(Theme.body(11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .buttonStyle(.plain)
                    .allowsHitTesting(role != .second)
            }
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
                    if let p = active.below(month: iso, firstDay: firstDay) { period = p }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(String(Int(iso.suffix(2)) ?? 0))
                            .font(Theme.body(17, weight: isToday ? .bold : .regular).monospacedDigit())
                        if isToday { Circle().fill(Theme.task).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 } }
                    }
                    .frame(width: 34, alignment: .leading)
                }
                .buttonStyle(.plain)
                .allowsHitTesting(role != .second)
                .accessibilityLabel(PageView.format(iso, "EEEE MMMM d"))
                Text(PageView.format(iso, "EEEEE"))
                    .font(Theme.body(13, weight: .medium))
                    .frame(width: 22, alignment: .leading)
                    .accessibilityHidden(true)
            }
            SlotEditor(logId: logId, slot: iso, minHeight: 27, fitOneLine: true, highlight: nav.highlight)
        }
        .foregroundStyle(weekend ? Theme.muted : Theme.text)
        .frame(minHeight: 44, alignment: .top)
        .padding(.top, 8)
        .background(Theme.task.opacity(marked == iso ? 0.1 : 0).padding(.horizontal, -8))
        .id("\(logId)/\(iso)")
    }
}

/// Year (future log): the twelve months with their names already written and a generous place to write in
/// each; a month's name opens its Month.
struct YearPage: View {
    let year: String
    @Binding var period: Period
    @EnvironmentObject private var nav: Navigator
    /// Consulted beside another page: read only, its days and months don't navigate.
    @Environment(\.pageRole) private var role
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("logMonthly") private var monthly = true
    @AppStorage("logWeekly") private var weekly = true
    @AppStorage("logDaily") private var daily = true
    @State private var marked: String?
    /// Scrolled past the first months: the header's title shrinks.
    @State private var scrolled = false
    @State private var width: CGFloat = 0
    /// Another page beside it (two pages, open book): one column.
    @Environment(\.pageBeside) private var beside

    /// On its own on a wide screen, the year opens like a notebook: January to June on the left, July to
    /// December on the right (as the PWA's spread); with a page beside it, or narrower, one column.
    private var spread: Bool { !beside && width >= 900 }

    var body: some View {
        let logId = Period.year(year).logId
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if spread {
                        HStack(alignment: .top, spacing: 48) {
                            months(0..<6, logId: logId, marker: true).frame(maxWidth: .infinity, alignment: .leading)
                            months(6..<12, logId: logId, marker: false).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: 1240)
                    } else {
                        months(0..<12, logId: logId, marker: true)
                            .frame(maxWidth: 720, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 240)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .scrollDismissesKeyboard(.interactively)
            .remembersScroll(nav, place: .time(.year(year)))
            .background(Theme.paper)
            .safeAreaInset(edge: .top, spacing: 0) {
                TimeHeader(period: $period, label: "", title: year, compact: scrolled) { EmptyView() }
                    .floatingHeaderStyle()
            }
            .onAppear { reveal(proxy, logId: logId) }
            .onChange(of: nav.focus) { reveal(proxy, logId: logId) }
        }
    }

    /// A run of months, each with its name (sticky while its month scrolls by) and a place to write.
    private func months(_ range: Range<Int>, logId: String, marker: Bool) -> some View {
        let currentMonth = Dates.monthOf(Dates.today())
        return LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if marker { ScrolledMarker(scrolled: $scrolled) }
            ForEach(range, id: \.self) { n in
                let ym = Dates.addMonths("\(year)-01", n)
                Section {
                    SlotEditor(logId: logId, slot: ym, minHeight: 96, highlight: nav.highlight)
                        .padding(.bottom, 20)
                        .background(Theme.task.opacity(marked == ym ? 0.08 : 0).padding(.horizontal, -8))
                        .id("\(logId)/\(ym)")
                } header: {
                    Button {
                        period = ActiveLogs(monthly: monthly, weekly: weekly, daily: daily).below(year: ym, firstDay: firstDay)
                    } label: {
                        Text(PageView.format("\(ym)-01", "MMMM"))
                            .font(Theme.body(17, weight: .semibold))
                            .foregroundStyle(ym == currentMonth ? Theme.task : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .background(Theme.paper)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(role != .second)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
                }
            }
        }
    }

    /// Scrolls to the month you came from (or an entry's month, from Open items) and marks it for a moment.
    private func reveal(_ proxy: ScrollViewProxy, logId: String) {
        guard let focus = nav.focus.map({ String($0.prefix(7)) }), focus.hasPrefix(year) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("\(logId)/\(focus)", anchor: .top) }
            marked = focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation { marked = nil } }
        }
    }
}

/// Placed at the top of a page's content: tells when it has scrolled under the header, so the header's title can
/// shrink. Shrinking moves the content up by about the header's lost height (up to ~40 pt), so it shrinks past
/// 100 pt and grows back only near the top: a single threshold flipped back and forth forever and froze the page.
struct ScrolledMarker: View {
    @Binding var scrolled: Bool

    var body: some View {
        Color.clear
            .frame(height: 0)
            .onGeometryChange(for: CGFloat.self) { ($0.frame(in: .scrollView).minY / 10).rounded() * 10 } action: { y in
                if !scrolled && y < -100 { scrolled = true } else if scrolled && y > -20 { scrolled = false }
            }
    }
}

extension View {
    /// Back returns a Month or Year to where it was scrolled, exactly (iOS 18's scroll position; before that,
    /// to the day or month you came from).
    @ViewBuilder func remembersScroll(_ nav: Navigator, place: Place) -> some View {
        if #available(iOS 18.0, *) {
            modifier(ScrollMemory(nav: nav, place: place))
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct ScrollMemory: ViewModifier {
    @ObservedObject var nav: Navigator
    let place: Place
    @State private var position = ScrollPosition(edge: .top)
    @State private var applied = 0

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                nav.remember(y, for: place)
            }
            .onAppear(perform: apply)
            .onChange(of: nav.restore) { apply() }
    }

    private func apply() {
        guard let r = nav.restore, r.place == place, r.id != applied else { return }
        applied = r.id
        // After the page is laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { position.scrollTo(y: r.y) }
    }
}
