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

    static func dynamicUI(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    /// UIKit colors by token: the pen's colors ('ink' and the bullets'), and the page's ('text', 'muted', 'rule').
    /// The same instance each time, so the editor can tell whether a line already has its color.
    static func ui(_ token: String) -> UIColor {
        if let c = uiCache[token] { return c }
        let c = makeUI(token)
        uiCache[token] = c
        return c
    }

    private static var uiCache: [String: UIColor] = [:]

    private static func makeUI(_ token: String) -> UIColor {
        switch token {
        case "task": return dynamicUI(0xE0533D, 0xEF6B56)
        case "event": return dynamicUI(0x3B82C4, 0x5B9BD8)
        case "note": return dynamicUI(0x2A9D8F, 0x3BB3A4)
        case "muted": return dynamicUI(0x726D65, 0x8D8A85)
        case "rule": return dynamicUI(0xE6E1D8, 0x2A2A2A)
        default: return dynamicUI(0x1F1D1A, 0xECE9E4)  // 'ink', 'text', a heading
        }
    }

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

extension View {
    /// Liquid Glass where the system has it (iOS 26 and later, built with Xcode 26), the translucent material
    /// before that. Floating controls only (the pen toolbar, banners); the page itself stays paper.
    /// `clear` is the more transparent glass: over the paper, the page's lines and text show through it.
    @ViewBuilder func glassBackground(in shape: some Shape, interactive: Bool = false, clear: Bool = false) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // Interactive glass reacts to touch (it gives a little under the finger), as system bars do.
                let glass: Glass = clear ? .clear : .regular
                self.glassEffect(interactive ? glass.interactive() : glass, in: shape)
            } else {
                self.background(.regularMaterial, in: shape)
            }
        #else
            self.background(.regularMaterial, in: shape)
        #endif
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
    static let inspiration = "Inspiration"
    static let explore = "Explore"
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
    static func weekShort(_ n: Int) -> String { "Wk \(n)" }
    static let thisMonth = "This Month"
    static let monthTasks = "Month tasks"
    static let index = "Index"
    static let collections = "Collections"
    static let newCollection = "New collection"
    static let name = "Name"
    static let create = "Create"
    static let cancel = "Cancel"
    static let noCollections = "No collections yet."
    static let untitled = "Untitled"
    static let yearKind = "Year"
    static let pinned = "Pinned"
    static func pin(_ name: String) -> String { "Pin \(name) to the top" }
    static func unpin(_ name: String) -> String { "Unpin \(name)" }
    static let goToDate = "Go to date"
    static let collectionMenu = "Collection"
    static let deleteCollection = "Delete collection…"
    static func deleteTitle(_ name: String) -> String { "Delete \u{201C}\(name)\u{201D}?" }
    static func deleteMessage(_ n: Int) -> String {
        n == 0 ? "It has nothing written yet." : "Everything written in it (\(n) \(n == 1 ? "entry" : "entries")) will be deleted too."
    }
    static let deleteAgainTitle = "Delete it for good?"
    static let deleteAgainMessage = "This can't be undone."
    static let deleteForever = "Delete for good"
    static let openItems = "Open items"
    static let openToday = "Still open today"
    static let back = "Back"
    static func weekNotSetUp(_ n: Int) -> String { "Week \(n) isn't set up yet" }
    static func monthNotSetUp(_ month: String) -> String { "\(month) isn't set up yet" }
    static let setUpWeek = "Set up week"
    static let setUpMonth = "Set up month"
    static let closeDay = "Close the day"
    static let closeDayHint = "See what is still open, then write tomorrow."
    static let dismiss = "Dismiss"
    static let pageMenu = "Page"
    static let export = "Export"
    static let copyAs = "Copy As"
    static let share = "Share"
    static let exportPDF = "Export PDF"
    static let markdown = "Markdown"
    static let richText = "Rich Text"
    static let plainText = "Plain Text"
    static let copied = "Copied"
    static let selection = "Selection"
    static let logs = "Logs"
    static let logsHint = "Year and Index are always on. At least one of Month, Week and Day stays on."
    static let month = "Month"
    static let setupBanner = "Set-up banner"
    static let closeDayTime = "From"
    static let glyphStyle = "Markdown glyph style"
    static let checkboxes = "Checkboxes"
    static let dotNotation = "Dot notation"
    static let print = "Print"
    static let printHint = "A5 pages, in notebook order: the Year, then each Month with its weeks and days; collections last."
    static let thisYear = "This year"
    static let everything = "Everything"
    static let thisMonthPrint = "This month"
    static let weekPage = "Week"

    static let nothingOpen = "Nothing is open. Everything has a place."
    static let wroteItThere = "I wrote it there"
    static let close = "Close"
    static func openCount(_ n: Int) -> String { "\(n) open \(n == 1 ? "item" : "items")" }
    static let typeMode = "Type"
    static let penMode = "Pen"
    static let write = "Write"
    static let draw = "Draw"
    static let eraser = "Eraser"
    static let undo = "Undo"
    static let sizes = ["Fine", "Medium", "Bold"]
    static let colorNames = ["ink": "Ink", "task": "Red", "event": "Blue", "note": "Green"]
    static let handwriting = "Handwriting"
    static let language = "Language"
    static let portugueseBR = "Portuguese (Brazil)"
    static let englishUS = "English (US)"
    static let handwritingHint =
        "Handwriting becomes text on this device, after a short pause in writing. The first time, the language (about 20 MB) is downloaded."
    static let hwUnavailable = "Not in this build yet"
    static let hwNotDownloaded = "Not downloaded"
    static let hwDownloading = "Downloading…"
    static let hwReady = "Ready, works offline"
    static let hwFailed = "Download failed. It tries again when you write."
}
