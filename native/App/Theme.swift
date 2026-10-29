// Look and words (CLAUDE.md 8). Colors are the PWA's Classic palette, light and dark; the UI is in English,
// with every string here (8.1), so other languages can come later.
import BulletLifeCore
import SwiftUI
import UIKit

enum Theme {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let paper = dynamic(0xFAF8F4, 0x141414)
    static let text = dynamic(0x1F1D1A, 0xECE9E4)
    static let muted = dynamic(0x726D65, 0x8D8A85)
    static let rule = dynamic(0xE6E1D8, 0x2A2A2A)
    static let task = dynamic(0xE0533D, 0xEF6B56)
    static let event = dynamic(0x3B82C4, 0x5B9BD8)
    static let note = dynamic(0x2A9D8F, 0x3BB3A4)

    /// The color of a line's bullet (and caret): from the type of its root item (Outline.colorTypes).
    static func color(_ type: EntryType) -> Color {
        switch type {
        case .task: return task
        case .event: return event
        case .note: return note
        case .text, .heading: return text
        }
    }

    /// Avenir Next where the system has it (iOS does), as in the PWA.
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        .custom("Avenir Next", size: size).weight(weight)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1
        )
    }
}

enum S {
    static let today = "Today"
    static let day = "Day"
    static let week = "Week"
    static let previous = "Previous"
    static let next = "Next"
    static let settings = "Settings"
    static let newLine = "Write"
    static let task = "Task"
    static let event = "Event"
    static let note = "Note"
    static let text = "Text"
    static let heading = "Heading"
    static let migrate = "Migrate"
    static let schedule = "Schedule"
    static let reopen = "Open again"
    static let priority = "Priority"
    static let indent = "Indent"
    static let outdent = "Outdent"
    static let delete = "Delete"
    static let firstDay = "First day of week"
    static let monday = "Monday"
    static let sunday = "Sunday"
    static let eventStates = "Event states"
    static let eventStatesHint = "Complete, cancel, migrate and schedule events like tasks."
    static let doneMark = "Done mark"
    static let importTitle = "Bring over from the web app"
    static let importButton = "Import a backup file…"
    static let importHint =
        "In the web app: Settings › Backup › Export everything. Then choose that file here. It replaces what is on this device."
    static func imported(_ n: Int) -> String { "Imported \(n) \(n == 1 ? "entry" : "entries")." }
    static let importFailed = "That file is not a Bullet Life backup."
    static let onDevice = "On this device"
    static func entries(_ n: Int) -> String { "\(n) \(n == 1 ? "entry" : "entries")" }
    static func weekTitle(_ n: Int) -> String { "Week \(n)" }
}
