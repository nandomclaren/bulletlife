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

struct RootView: View {
    @StateObject private var nav = Navigator()
    @AppStorage("theme") private var theme = Theme.Look.auto.rawValue
    @AppStorage("palette") private var palette = Theme.Palette.classic.rawValue
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context

    private var period: Binding<Period> {
        Binding(get: { nav.period }, set: { nav.go(.time($0)) })
    }

    var body: some View {
        NavigationStack {
            page
                // A new theme or palette: the page is drawn again in its colors (UIKit text keeps what it drew).
                .id("\(theme)/\(palette)")
                .background(Theme.paper.ignoresSafeArea())
                .safeAreaInset(edge: .top, spacing: 0) { Banners() }
                // Open items: a column beside the page on iPad (the page stays visible and editable), a sheet on
                // iPhone (CLAUDE.md 4.2).
                .inspector(isPresented: $nav.showOpen) {
                    OpenItemsPanel(onlyToday: nav.openToday) { item in
                        let target: Place = item.source.period.map { Place.time($0) } ?? .collection(item.source.logId)
                        nav.go(target, highlight: item.entry.id,
                               focus: item.entry.slot.isEmpty ? nil : item.entry.slot)
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

    /// Paper, Graphite and Night hold the window to light or dark (Automatic follows the system); the colors
    /// read the theme and palette when they are drawn.
    private func applyLook() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = Theme.look.style }
        }
    }

    /// Day, Week and collections are free pages (Type or Pen); Month and Year have their fixed layouts.
    @ViewBuilder private var page: some View {
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
