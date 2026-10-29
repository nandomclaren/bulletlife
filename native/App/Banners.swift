// Quiet in-app banners (CLAUDE.md 5), on the pages of the current period (today's Day, this Week, this
// Month): "Week 44 isn't set up yet" and, in the evening, Close the day. Both can be dismissed and only open
// things up; the one thing written is an explicit "Set up", which records the (still empty) page as set up.
import BulletLifeCore
import SwiftData
import SwiftUI

struct Banners: View {
    @EnvironmentObject private var nav: Navigator
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<LogRecord> { $0.periodLogId != nil }) private var setUps: [LogRecord]
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("logMonthly") private var monthly = true
    @AppStorage("logWeekly") private var weekly = true
    @AppStorage("logDaily") private var daily = true
    @AppStorage("setupBanner") private var setupBanner = true
    @AppStorage("closeDay") private var closeDay = true
    @AppStorage("closeDayAt") private var closeDayAt = "20:00"
    @State private var dismissed = 0

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let today = Dates.today()
        if case .time(let p) = nav.place, isCurrent(p, today: today) {
            VStack(spacing: 6) {
                if let pending = pendingSetUp(today: today) {
                    banner(text: setUpText(pending), action: pending.kind == .weekly ? S.setUpWeek : S.setUpMonth) {
                        setUp(pending)
                    } dismiss: {
                        UserDefaults.standard.set(true, forKey: "banner.setup.\(pending.logId)")
                        dismissed += 1
                    }
                }
                if showClose(now: now, today: today) {
                    banner(text: S.closeDayHint, action: S.closeDay) {
                        UserDefaults.standard.set(true, forKey: "banner.closeDay.\(today)")
                        dismissed += 1
                        nav.go(.time(.day(Dates.addDays(today, 1))))
                        nav.openToday = true
                        nav.showOpen = true
                    } dismiss: {
                        UserDefaults.standard.set(true, forKey: "banner.closeDay.\(today)")
                        dismissed += 1
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .frame(maxWidth: 760)
            .id(dismissed)
        }
    }

    private func isCurrent(_ p: Period, today: String) -> Bool {
        switch p {
        case .day(let d): return d == today
        case .week(let k): return k == Dates.weekKey(today, firstDay: firstDay)
        case .month(let m): return m == Dates.monthOf(today)
        case .year: return false
        }
    }

    /// This month's or this week's page, when its log is on and nothing shows it was set up (written in, or set
    /// up with the button).
    private func pendingSetUp(today: String) -> Source? {
        guard setupBanner else { return nil }
        var candidates: [Period] = []
        if monthly { candidates.append(.month(Dates.monthOf(today))) }
        if weekly { candidates.append(.week(Dates.weekKey(today, firstDay: firstDay))) }
        let marked = Set(setUps.compactMap(\.periodLogId))
        let repo = Repository(context: context)
        return candidates.lazy.map(\.logId)
            .first { id in
                !marked.contains(id) && !repo.hasEntries(logId: id) && !UserDefaults.standard.bool(forKey: "banner.setup.\(id)")
            }
            .map { Source(logId: $0, firstDay: firstDay) }
    }

    private func setUpText(_ s: Source) -> String {
        s.kind == .weekly ? S.weekNotSetUp(Dates.weekNumber(s.key)) : S.monthNotSetUp(PageView.format("\(s.key)-01", "MMMM"))
    }

    /// Records the empty page as set up, opens it and the Open items panel to write it from.
    private func setUp(_ s: Source) {
        Repository(context: context).setUpPeriod(s)
        if let p = s.period { nav.go(.time(p)) }
        nav.showOpen = true
    }

    private func showClose(now: Date, today: String) -> Bool {
        guard closeDay, daily, !UserDefaults.standard.bool(forKey: "banner.closeDay.\(today)") else { return false }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: now) >= closeDayAt
    }

    private func banner(text: String, action: String, onAction: @escaping () -> Void, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(Theme.body(14))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Button(action, action: onAction)
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.task)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(S.dismiss)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14))
    }
}
