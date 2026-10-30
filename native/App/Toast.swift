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
        let undo: () -> Void
    }

    @Published var current: Toast?

    func show(_ text: String, undo: @escaping () -> Void) {
        let toast = Toast(text: text, undo: undo)
        withAnimation(.easeOut(duration: 0.2)) { current = toast }
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
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
                Text(t.text).foregroundStyle(Theme.text)
                Button(S.undo) {
                    t.undo()
                    withAnimation(.easeIn(duration: 0.2)) { toasts.current = nil }
                }
                .fontWeight(.semibold)
                .foregroundStyle(Theme.task)
            }
            .font(Theme.body(15))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .glassBackground(in: Capsule(), interactive: true)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(t.id)
        }
    }
}
