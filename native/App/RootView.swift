// Where the notebook is open and how it moves (CLAUDE.md 5.1): one place at a time (a time page, the Index or
// a collection), a real history for Back, and, going up a level, the page scrolls to where you came from and
// marks it briefly. Navigating never creates or writes anything.
import BulletLifeCore
import SwiftData
import UIKit
import CoreSpotlight
import SwiftUI

enum Place: Hashable {
    case time(Period)
    case index
    case collection(String)

    /// As kept on the device: "index", "c:<id>", "d:2026-10-30", "w:2026-W44", "m:2026-10", "y:2026".
    var stored: String {
        switch self {
        case .index: return "index"
        case .collection(let id): return "c:" + id
        case .time(.day(let k)): return "d:" + k
        case .time(.week(let k)): return "w:" + k
        case .time(.month(let k)): return "m:" + k
        case .time(.year(let k)): return "y:" + k
        }
    }

    init?(stored s: String) {
        let value = String(s.dropFirst(2))
        switch s.prefix(2) {
        case "c:": self = .collection(value)
        case "d:": self = .time(.day(value))
        case "w:": self = .time(.week(value))
        case "m:": self = .time(.month(value))
        case "y:": self = .time(.year(value))
        default:
            guard s == "index" else { return nil }
            self = .index
        }
    }
}

/// Where a page was scrolled (from the top of its content), to put it back there.
struct ScrollRestore: Equatable {
    let place: Place
    let y: CGFloat
    let id: Int
}

/// The settings that decide which time logs exist (CLAUDE.md 3.2), read where navigation needs them.
enum Prefs {
    static var active: ActiveLogs {
        let d = UserDefaults.standard
        return ActiveLogs(
            monthly: d.object(forKey: "logMonthly") as? Bool ?? true, weekly: d.object(forKey: "logWeekly") as? Bool ?? true,
            daily: d.object(forKey: "logDaily") as? Bool ?? true)
    }
    static var firstDay: Weekday { UserDefaults.standard.object(forKey: "firstDay") as? Int ?? 1 }
    /// Rapid-logging prefixes (Settings), each falling back to its default if left empty or clashing.
    static var prefixes: Prefixes {
        let d = UserDefaults.standard
        let def = Prefixes()
        return Prefixes(
            task: d.string(forKey: "prefixTask") ?? def.task, event: d.string(forKey: "prefixEvent") ?? def.event,
            note: d.string(forKey: "prefixNote") ?? def.note, heading: d.string(forKey: "prefixHeading") ?? def.heading,
            priority: d.string(forKey: "prefixPriority") ?? def.priority)
    }
}

@MainActor
final class Navigator: ObservableObject {
    @Published private(set) var place: Place
    @Published private(set) var lastPeriod: Period
    @Published private(set) var history: [Place] = []
    /// A day ('YYYY-MM-DD') or month ('YYYY-MM') to scroll to and mark on a Month or Year page.
    @Published var focus: String?
    /// An entry to scroll to and mark (opened from Open items).
    @Published var highlight: String?
    @Published var showOpen = false
    /// The search sheet is open.
    @Published var searching = false
    /// Close the day opens the panel on what is still open today.
    @Published var openToday = false

    /// Kept on the device under this key (the second of two pages), if set.
    private let key: String?

    init() {
        let start = Prefs.active.finest(Dates.today(), firstDay: Prefs.firstDay)
        place = .time(start)
        lastPeriod = start
        key = nil
    }

    /// A navigator that comes back where it was last time (the Index the first time).
    init(rememberedAs key: String) {
        self.key = key
        let saved = UserDefaults.standard.string(forKey: key).flatMap(Place.init(stored:)) ?? .index
        place = saved
        if case .time(let p) = saved { lastPeriod = p } else { lastPeriod = Prefs.active.finest(Dates.today(), firstDay: Prefs.firstDay) }
    }

    func go(_ next: Place, highlight: String? = nil, focus: String? = nil) {
        guard next != place || highlight != nil else { return }
        if next != place {
            history.append(place)
            if history.count > 100 { history.removeFirst() }
        }
        move(to: next)
        if let highlight {
            // Cleared first, so the same entry opened again is marked again.
            self.highlight = nil
            DispatchQueue.main.async { self.highlight = highlight }
        } else {
            self.highlight = nil
        }
        if let focus { self.focus = focus }
    }

    func back() {
        guard let previous = history.popLast() else { return }
        move(to: previous)
        highlight = nil
        // Back where it was scrolled, exactly (not just to the day or month you came from).
        if let y = offsets[previous] {
            focus = nil
            restores += 1
            restore = ScrollRestore(place: previous, y: y, id: restores)
        }
    }

    /// How far each page was scrolled, to return there with Back (reported by the pages as they scroll).
    private var offsets: [Place: CGFloat] = [:]
    private var restores = 0
    /// A page to put back where it was scrolled: the page of `place` applies it once (by `id`).
    @Published private(set) var restore: ScrollRestore?

    func remember(_ y: CGFloat, for place: Place) {
        offsets[place] = max(0, y)
    }

    var period: Period {
        if case .time(let p) = place { return p }
        return lastPeriod
    }

    private func move(to next: Place) {
        // Going up (or back up) to a Month or Year: scroll to the day or month you came from.
        if case .time(let old) = place, case .time(let new) = next {
            let anchor = old.anchor(today: Dates.today(), firstDay: Prefs.firstDay)
            switch new {
            case .month(let ym) where Dates.monthOf(anchor) == ym && !old.sameLevel(new): focus = anchor
            case .year(let y) where Dates.yearOf(anchor) == y && !old.sameLevel(new): focus = Dates.monthOf(anchor)
            default: focus = nil
            }
        } else {
            focus = nil
        }
        if case .time(let p) = next { lastPeriod = p }
        place = next
        if let key { UserDefaults.standard.set(next.stored, forKey: key) }
    }
}

/// How many pages are open (iPad, wide): one; two, each with its own place; or an open book, whose right page
/// is the next day, week, month or year.
enum PageLayout: String, CaseIterable, Identifiable {
    case single, two, book
    var id: String { rawValue }
    var name: String {
        switch self {
        case .single: return S.singlePage
        case .two: return S.twoPages
        case .book: return S.openBook
        }
    }
    var icon: String {
        switch self {
        case .single: return "rectangle.portrait"
        case .two: return "rectangle.split.2x1"
        case .book: return "book.pages"
        }
    }
}

/// Which page a view is part of: the main one, the second of two pages, or the open book's right page.
enum PageRole { case main, second, facing }


private struct PageRoleKey: EnvironmentKey { static let defaultValue = PageRole.main }
private struct PageStepKey: EnvironmentKey { static let defaultValue = 1 }
private struct PageBesideKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var pageRole: PageRole {
        get { self[PageRoleKey.self] }
        set { self[PageRoleKey.self] = newValue }
    }
    /// How far ‹ › go: two pages in the open book.
    var pageStep: Int {
        get { self[PageStepKey.self] }
        set { self[PageStepKey.self] = newValue }
    }
    /// Another page is open beside this one.
    var pageBeside: Bool {
        get { self[PageBesideKey.self] }
        set { self[PageBesideKey.self] = newValue }
    }
}

struct RootView: View {
    @StateObject private var nav = Navigator()
    /// The second of two pages: its own place and history; it keeps the last page it showed (else the Index).
    @StateObject private var second = Navigator(rememberedAs: "secondPlace")
    @AppStorage("theme") private var theme = Theme.Look.auto.rawValue
    @AppStorage("palette") private var palette = Theme.Palette.classic.rawValue
    @AppStorage("pageLayout") private var layoutChoice = PageLayout.single.rawValue
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context
    /// The theme and palette the pages were built with.
    @State private var builtLook = ""
    private var currentLook: String { "\(theme)/\(palette)" }
    /// How far the divider between two pages is being dragged (hold it, then drag to close a page).
    @State private var dividerDrag: CGFloat = 0
    @AppStorage("firstDay") private var firstDay = 1
    /// A search result to open once the search sheet is gone (so the page scrolls and marks it in view).
    @State private var found: (place: Place, highlight: String?, focus: String?)?

    /// Two pages need the room of an iPad's full width; narrower, the notebook is one page.
    private var layout: PageLayout {
        sizeClass == .regular ? PageLayout(rawValue: layoutChoice) ?? .single : .single
    }

    var body: some View {
        NavigationStack {
            pages
                // A new theme or palette: the page is built again in its colors (UIKit text keeps what it drew),
                // once it is back on screen. Rebuilt while Settings was pushed over it, the stack showed nothing.
                .id(builtLook)
                .onAppear { if builtLook != currentLook { builtLook = currentLook } }
                .background(Theme.paper.ignoresSafeArea())
                // Open items: a column beside the page on iPad (the page stays visible and editable), a sheet on
                // iPhone (CLAUDE.md 4.2).
                .inspector(isPresented: $nav.showOpen) {
                    OpenItemsPanel(onlyToday: nav.openToday) { item in
                        let target: Place = item.source.period.map { Place.time($0) } ?? .collection(item.source.logId)
                        let focus = item.entry.slot.isEmpty ? nil : item.entry.slot
                        // With two pages, it opens on the second, the page to consult, beside the page being
                        // written (CLAUDE.md 4.2); an entry of the page being written is just marked there.
                        let opener = layout == .two && target != nav.place ? second : nav
                        opener.go(target, highlight: item.entry.id, focus: focus)
                        if sizeClass == .compact { nav.showOpen = false }
                    }
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 440)
                }
                .onChange(of: nav.showOpen) { if !nav.showOpen { nav.openToday = false } }
                .sheet(isPresented: $nav.searching, onDismiss: openFound) {
                    SearchView { place, highlight, focus in found = (place, highlight, focus) }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        if !nav.history.isEmpty {
                            Button {
                                nav.back()
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .accessibilityLabel(S.back)
                        }
                        Button {
                            nav.go(.index)
                        } label: {
                            Image(systemName: "book.closed")
                        }
                        .accessibilityLabel(S.index)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        // ⌘K / ⌘F come from the app's Go menu (NotebookCommands).
                        Button {
                            nav.searching = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(S.search)
                        OpenItemsButton(isOpen: $nav.showOpen)
                        if sizeClass == .regular { layoutMenu }
                        PageMenu(place: nav.place)
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(S.settings)
                    }
                }
        }
        // "Migrated" / "Scheduled" with Undo, above the pen toolbar.
        // (On iPhone, where there is no pen toolbar, it sits lower.)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, sizeClass == .compact ? 24 : 84) }
        .environmentObject(nav)
        // The app's menu commands (Go: search, Today, levels, pages) act on this window's notebook.
        .focusedSceneObject(nav)
        .tint(Theme.task)
        // Light or dark only this way: holding the window too made the two fight, and painting the scene's
        // windows covered the app with the system's overlay windows.
        .preferredColorScheme(Theme.Look(rawValue: theme)?.scheme)
        // The system's search: the notebook indexed at launch and page by page as it is written; a result
        // opens its page with the entry marked.
        .task { Spotlight.indexAll(repo: Repository(context: context)) }
        .onReceive(NotificationCenter.default.publisher(for: Repository.saved)) { note in
            guard let logId = note.userInfo?["logId"] as? String else { return }
            Spotlight.index(logId: logId, slot: note.userInfo?["slot"] as? String ?? "", repo: Repository(context: context))
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let t = Spotlight.target(activity, repo: Repository(context: context)) else { return }
            nav.go(t.place, highlight: t.id, focus: t.focus)
        }
        // The Close the day reminder tapped: tomorrow's page, with what is still open today beside it.
        .onReceive(NotificationCenter.default.publisher(for: Reminders.openCloseDay)) { _ in
            let today = Dates.today()
            UserDefaults.standard.set(true, forKey: "banner.closeDay.\(today)")
            nav.go(.time(.day(Dates.addDays(today, 1))))
            nav.openToday = true
            nav.showOpen = true
        }
    }

    /// The page the divider is being dragged over fades, as it is about to close.
    private func fading(_ side: PageDivider.Side) -> Double {
        let over = side == .left ? -dividerDrag : dividerDrag
        return over > 0 ? max(0.35, 1 - Double(over) / 300) : 1
    }

    /// The divider dragged away: one page stays, as a single page. Keeping the right one takes the left page
    /// there (the page consulted, or the open book's next period).
    private func closePage(_ side: PageDivider.Side) {
        if side == .left {
            switch layout {
            case .two: nav.go(second.place)
            case .book: if case .time(let p) = nav.place { nav.go(.time(p.moved(1, firstDay: firstDay))) }
            case .single: break
            }
        }
        withAnimation(.easeInOut(duration: 0.2)) { layoutChoice = PageLayout.single.rawValue }
    }

    private func openFound() {
        guard let f = found else { return }
        found = nil
        // With two pages, on the page to consult (the right one), as Open items; an entry of the page being
        // written is marked there.
        let opener = layout == .two && f.place != nav.place ? second : nav
        opener.go(f.place, highlight: f.highlight, focus: f.focus)
    }

    /// One page, two pages, or the open book: a system menu with the current one checked.
    private var layoutMenu: some View {
        Menu {
            Picker(S.pageLayout, selection: $layoutChoice) {
                ForEach(PageLayout.allCases) { l in
                    Label(l.name, systemImage: l.icon).tag(l.rawValue)
                }
            }
        } label: {
            Image(systemName: layout.icon)
        }
        .accessibilityLabel(S.pageLayout)
    }

    @ViewBuilder private var pages: some View {
        let main = NotebookPage(nav: nav)
            .safeAreaInset(edge: .top, spacing: 0) { Banners() }
            .environment(\.pageStep, layout == .book ? 2 : 1)
        switch layout {
        case .single:
            main
        case .two:
            HStack(spacing: 0) {
                main.opacity(fading(.left)).offset(x: min(0, dividerDrag))
                PageDivider(drag: $dividerDrag, close: closePage).offset(x: dividerDrag)
                SecondPage(nav: second).opacity(fading(.right)).offset(x: max(0, dividerDrag))
            }
            .clipShape(SidesOnly())
            .environment(\.pageBeside, true)
        case .book:
            HStack(spacing: 0) {
                main.opacity(fading(.left)).offset(x: min(0, dividerDrag))
                PageDivider(drag: $dividerDrag, close: closePage).offset(x: dividerDrag)
                FacingPage(nav: nav).opacity(fading(.right)).offset(x: max(0, dividerDrag))
            }
            .clipShape(SidesOnly())
            .environment(\.pageBeside, true)
        }
    }

}

/// A page of the notebook where `nav` is: Day, Week and collections are free pages (Type or Pen); Month and
/// Year have their fixed layouts.
struct NotebookPage: View {
    @ObservedObject var nav: Navigator
    var role = PageRole.main
    @Environment(\.modelContext) private var context

    private var period: Binding<Period> {
        Binding(get: { nav.period }, set: { nav.go(.time($0)) })
    }

    var body: some View {
        content
            .environmentObject(nav)
            .environment(\.pageRole, role)
    }

    @ViewBuilder private var content: some View {
        switch nav.place {
        case .index:
            IndexPage(period: period) { nav.go(.collection($0)) }
        case .collection(let id):
            if let log = Repository(context: context).collection(id) {
                PageView(period: period, collection: log) { nav.go(.index) }
            } else {
                IndexPage(period: period) { nav.go(.collection($0)) }
            }
        case .time(let p):
            switch p {
            case .day, .week: PageView(period: period)
            case .month(let ym): MonthPage(ym: ym, period: period)
            case .year(let y): YearPage(year: y, period: period)
            }
        }
    }
}

/// The second of two pages: a page to consult, read only (a bullet still answers the finger). Its one control,
/// an × at the corner, goes back to the Index; from there, or from Open items, it shows another page.
struct SecondPage: View {
    @ObservedObject var nav: Navigator

    var body: some View {
        NotebookPage(nav: nav, role: .second)
            .overlay(alignment: .topTrailing) {
                if nav.place != .index {
                    Button {
                        nav.go(.index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .glassBackground(in: Circle(), interactive: true)
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                    .accessibilityLabel(S.closePage)
                }
            }
    }
}

/// The open book's right page: the period after the left one, at the same level, editable. It has no
/// controls of its own; what is tapped on it (a day, a week, a month) takes the left page there.
struct FacingPage: View {
    @ObservedObject var nav: Navigator
    @AppStorage("firstDay") private var firstDay = 1

    var body: some View {
        if case .time(let p) = nav.place {
            let next = p.moved(1, firstDay: firstDay)
            let period = Binding(get: { next }, set: { nav.go(.time($0)) })
            Group {
                switch next {
                case .day, .week: PageView(period: period)
                case .month(let ym): MonthPage(ym: ym, period: period)
                case .year(let y): YearPage(year: y, period: period)
                }
            }
            .id(next)
            .environmentObject(nav)
            .environment(\.pageRole, .facing)
        } else {
            // The Index and collections are single pages.
            Theme.paper
        }
    }
}

/// The line between two pages. Held for a moment, it shows a handle (as the system's split view does); dragged,
/// the line goes with the finger and pushes the page on that side away; far enough, that page closes and the
/// other stays as a single page.
struct PageDivider: View {
    enum Side { case left, right }
    @Binding var drag: CGFloat
    var close: (Side) -> Void
    @State private var holding = false
    private let threshold: CGFloat = 120

    var body: some View {
        Rectangle()
            .fill(Theme.rule)
            .frame(width: 1)
            .overlay {
                Capsule()
                    .fill(Theme.muted)
                    .frame(width: 6, height: 44)
                    .opacity(holding ? 1 : 0)
                    .scaleEffect(holding ? 1 : 0.6)
            }
            .overlay {
                // A wider place to hold than the line itself.
                Color.clear
                    .frame(width: 28)
                    .contentShape(Rectangle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .onEnded { _ in
                                withAnimation(.spring(duration: 0.2)) { holding = true }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            // In the window's space: the divider itself moves with the finger.
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                            .onChanged { value in
                                if case .second(true, let d) = value, let d { drag = d.translation.width }
                            }
                            .onEnded { _ in
                                let d = drag
                                withAnimation(.spring(duration: 0.25)) {
                                    holding = false
                                    drag = 0
                                }
                                if d > threshold { close(.right) } else if d < -threshold { close(.left) }
                            }
                    )
            }
            .zIndex(1)
            .accessibilityElement()
            .accessibilityLabel(S.pageDivider)
            .accessibilityAction(named: S.closeRightPage) { close(.right) }
            .accessibilityAction(named: S.closeLeftPage) { close(.left) }
    }
}

/// Clips at the sides only: a page pushed away by the divider stays within the window's width, while the pages'
/// paper still reaches up under the toolbar.
struct SidesOnly: Shape {
    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -10_000))
    }
}

/// The app's Go menu (the iPad's menu bar, and the list shown while ⌘ is held): search, and the keyboard's
/// way around the notebook (CLAUDE.md 5.1): ⌘T Today; ⌃⌘↑ / ⌃⌘↓ a level up or down (Day › Week › Month ›
/// Year, around the day looked at); ⌃⌘← / ⌃⌘→ the previous or next page at the same level.
struct NotebookCommands: Commands {
    @FocusedObject private var nav: Navigator?

    var body: some Commands {
        CommandMenu(S.goMenu) {
            Button(S.search) { nav?.searching = true }.keyboardShortcut("k", modifiers: .command)
            Button(S.find) { nav?.searching = true }.keyboardShortcut("f", modifiers: .command)
            Divider()
            Button(S.today) { nav?.goToday() }.keyboardShortcut("t", modifiers: .command)
            Button(S.levelUp) { nav?.level(-1) }.keyboardShortcut(.upArrow, modifiers: [.control, .command])
            Button(S.levelDown) { nav?.level(1) }.keyboardShortcut(.downArrow, modifiers: [.control, .command])
            Button(S.previousPage) { nav?.page(-1) }.keyboardShortcut(.leftArrow, modifiers: [.control, .command])
            Button(S.nextPage) { nav?.page(1) }.keyboardShortcut(.rightArrow, modifiers: [.control, .command])
        }
    }
}

extension Navigator {
    private var current: Period? {
        if case .time(let p) = place { return p }
        return nil
    }

    /// Today at the page's level (the finest log on, from the Index or a collection).
    func goToday() {
        let p = current.map { Period.containing(Dates.today(), like: $0, firstDay: Prefs.firstDay) }
        go(.time(p ?? Prefs.active.finest(Dates.today(), firstDay: Prefs.firstDay)))
    }

    func level(_ step: Int) {
        guard let p = current, let next = p.level(step, today: Dates.today(), firstDay: Prefs.firstDay, active: Prefs.active) else { return }
        go(.time(next))
    }

    func page(_ step: Int) {
        guard let p = current else { return }
        go(.time(p.moved(step, firstDay: Prefs.firstDay)))
    }
}
