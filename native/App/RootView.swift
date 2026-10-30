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

    init() {
        let start = Prefs.active.finest(Dates.today(), firstDay: Prefs.firstDay)
        place = .time(start)
        lastPeriod = start
    }

    func go(_ next: Place, highlight: String? = nil, focus: String? = nil) {
        guard next != place || highlight != nil else { return }
        if next != place {
            history.append(place)
            if history.count > 100 { history.removeFirst() }
        }
        move(to: next)
        self.highlight = highlight
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
    /// The second of two pages: its own place and history (it keeps the last page it showed).
    @StateObject private var second = Navigator()
    @AppStorage("theme") private var theme = Theme.Look.auto.rawValue
    @AppStorage("palette") private var palette = Theme.Palette.classic.rawValue
    @AppStorage("pageLayout") private var layoutChoice = PageLayout.single.rawValue
    @Environment(\.horizontalSizeClass) private var sizeClass

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
                        // With two pages, it opens on the second, beside the page being written (CLAUDE.md 4.2).
                        let opener = layout == .two && target != nav.place ? second : nav
                        opener.go(target, highlight: item.entry.id, focus: focus)
                        if sizeClass == .compact { nav.showOpen = false }
                    }
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 440)
                }
                .onChange(of: nav.showOpen) { if !nav.showOpen { nav.openToday = false } }
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
                main
                Divider()
                SecondPage(nav: second, main: nav)
            }
            .environment(\.pageBeside, true)
        case .book:
            HStack(spacing: 0) {
                main
                Divider()
                FacingPage(nav: nav)
            }
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

/// The second of two pages: a page of its own, with Back and the Index in a small glass bar at its corner (the
/// window's toolbar belongs to the first page).
struct SecondPage: View {
    @ObservedObject var nav: Navigator
    @ObservedObject var main: Navigator

    var body: some View {
        Group {
            // The same page twice would have two editors writing over each other: it is written on the left.
            if nav.place == main.place && nav.place != .index {
                Text(S.openOnLeft)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.paper)
            } else {
                NotebookPage(nav: nav, role: .second)
            }
        }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if !nav.history.isEmpty {
                        Button {
                            nav.back()
                        } label: {
                            Image(systemName: "chevron.backward").frame(width: 40, height: 40)
                        }
                        .accessibilityLabel(S.back)
                    }
                    Button {
                        nav.go(.index)
                    } label: {
                        Image(systemName: "book.closed").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(S.index)
                }
                .padding(.horizontal, 6)
                .glassBackground(in: Capsule(), interactive: true)
                .padding(16)
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
