// Where the notebook is open and how it moves (CLAUDE.md 5.1): one place at a time (a time page, the Index or
// a collection), a real history for Back, and, going up a level, the page scrolls to where you came from and
// marks it briefly. Navigating never creates or writes anything.
import BulletLifeCore
import SwiftData
import UIKit
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

/// The settings that decide which time logs exist (CLAUDE.md 3.2), read where navigation needs them.
enum Prefs {
    static var active: ActiveLogs {
        let d = UserDefaults.standard
        return ActiveLogs(
            monthly: d.object(forKey: "logMonthly") as? Bool ?? true, weekly: d.object(forKey: "logWeekly") as? Bool ?? true,
            daily: d.object(forKey: "logDaily") as? Bool ?? true)
    }
    static var firstDay: Weekday { UserDefaults.standard.object(forKey: "firstDay") as? Int ?? 1 }
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
    @State private var searching = false
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
                // A new theme or palette: the page is drawn again in its colors (UIKit text keeps what it drew).
                .id("\(theme)/\(palette)")
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
                .sheet(isPresented: $searching, onDismiss: openFound) {
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
                        Button {
                            searching = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .keyboardShortcut("k", modifiers: .command)
                        .accessibilityLabel(S.search)
                        // ⌘F too, as in other apps.
                        .background {
                            Button("") { searching = true }
                                .keyboardShortcut("f", modifiers: .command)
                                .opacity(0)
                                .accessibilityHidden(true)
                        }
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
        .environmentObject(nav)
        .tint(Theme.task)
        .onAppear(perform: applyLook)
        .onChange(of: theme) { applyLook() }
        .onChange(of: palette) { applyLook() }
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
            .clipped()
            .environment(\.pageBeside, true)
        case .book:
            HStack(spacing: 0) {
                main.opacity(fading(.left)).offset(x: min(0, dividerDrag))
                PageDivider(drag: $dividerDrag, close: closePage).offset(x: dividerDrag)
                FacingPage(nav: nav).opacity(fading(.right)).offset(x: max(0, dividerDrag))
            }
            .clipped()
            .environment(\.pageBeside, true)
        }
    }

    /// Paper, Graphite and Night hold the window to light or dark (Automatic follows the system); the colors
    /// read the theme and palette when they are drawn.
    private func applyLook() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = Theme.look.style }
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
            // Paper under the toolbar, where the line does not go (else the window's own background shows).
            .background(Theme.paper.ignoresSafeArea())
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
