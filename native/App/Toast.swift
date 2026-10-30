// A quiet notice at the bottom of the window with an Undo, for a mark the user just made: "Migrated" or
// "Scheduled" after > or < (CLAUDE.md 3.2). It goes by itself after a few seconds; it never acts on its own.
import BulletLifeCore
import SwiftUI
import UIKit

final class Toasts: ObservableObject {
    static let shared = Toasts()

    struct Toast: Identifiable {
        let id = UUID()
        let text: String
        /// The button, if any (Undo, Link it), and a second, quieter one (Not this one).
        var action: (label: String, run: () -> Void)?
        var other: (label: String, run: () -> Void)?
    }

    @Published var current: Toast?

    func show(_ text: String, undo: @escaping () -> Void) {
        present(Toast(text: text, action: (S.undo, undo)), for: 4)
    }

    /// A notice with no button (it just says what happened).
    func tell(_ text: String) {
        present(Toast(text: text), for: 3)
    }

    /// A suggestion to accept or turn down; it waits longer, and going by without an answer changes nothing.
    func suggest(_ text: String, _ label: String, run: @escaping () -> Void, other: String, otherRun: @escaping () -> Void) {
        present(Toast(text: text, action: (label, run), other: (other, otherRun)), for: 9)
    }

    private func present(_ toast: Toast, for seconds: Double) {
        let text = toast.text
        withAnimation(.easeOut(duration: 0.2)) { current = toast }
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.current?.id == toast.id else { return }
            withAnimation(.easeIn(duration: 0.2)) { self?.current = nil }
        }
    }

    /// After an entry was marked > or <, from wherever it was marked; `undo` puts its state back.
    static func marked(_ state: EntryState, undo: @escaping () -> Void) {
        guard state == .migrated || state == .scheduled else { return }
        shared.show(state == .migrated ? S.migrated : S.scheduled, undo: undo)
    }
}

struct ToastView: View {
    @ObservedObject private var toasts = Toasts.shared

    var body: some View {
        if let t = toasts.current {
            HStack(spacing: 16) {
                Text(t.text).foregroundStyle(Theme.text).lineLimit(2)
                if let other = t.other {
                    Button(other.label) {
                        other.run()
                        withAnimation(.easeIn(duration: 0.2)) { toasts.current = nil }
                    }
                    .foregroundStyle(Theme.muted)
                }
                if let action = t.action {
                    Button(action.label) {
                        action.run()
                        withAnimation(.easeIn(duration: 0.2)) { toasts.current = nil }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.task)
                }
            }
            .frame(maxWidth: 640)
            .font(Theme.body(15))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassBackground(in: Capsule(), interactive: true)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(t.id)
        }
    }
}

/// Phase 4b (CLAUDE.md 4.4): a task or event just written that reads like an open item from another page.
/// Only a suggestion, by the toast: "Link it" marks the original as written here (one entry, the user's tap);
/// "Not this one" never suggests that pair again on this device.
@MainActor
enum Rewrites {
    private static let dismissedKey = "dismissedLinks"

    static func check(_ line: Line, logId: String, repo: Repository) {
        guard line.type == .task || line.type == .event, line.text.trimmingCharacters(in: .whitespaces).count >= 3 else { return }
        let d = UserDefaults.standard
        let dismissed = Set(d.stringArray(forKey: dismissedKey) ?? [])
        let items = OpenItems.items(
            repo.lightEntries(), eventStates: d.object(forKey: "eventStates") as? Bool ?? true, firstDay: Prefs.firstDay, today: Dates.today()
        )
        .filter { $0.entry.id != line.id && $0.source.logId != logId && !dismissed.contains("\(line.id):\($0.entry.id)") }
        guard let item = Similar.bestMatch(line.text, items, text: { $0.entry.text }) else { return }
        let title = item.source.kind == .collection ? repo.collection(item.source.logId)?.title : nil
        let origin = OpenItems.sourceLabel(item.source, slot: item.entry.slot, collectionTitle: title)
        var plain = item.entry.text as NSString
        for t in Due.tokens(item.entry.text).reversed() { plain = plain.replacingCharacters(in: t.range, with: "") as NSString }
        let text = (plain as String).trimmingCharacters(in: .whitespaces)
        let short = text.count > 48 ? String(text.prefix(46)) + "…" : text
        let lineId = line.id, sourceId = item.entry.id
        Toasts.shared.suggest(
            S.looksLike(short, origin), S.linkIt,
            run: {
                repo.link(sourceId, writtenAs: lineId)
                Toasts.shared.tell(S.linked)
            },
            other: S.notThisOne,
            otherRun: {
                let all = (d.stringArray(forKey: dismissedKey) ?? []) + ["\(lineId):\(sourceId)"]
                d.set(Array(all.suffix(500)), forKey: dismissedKey)
            })
    }
}
