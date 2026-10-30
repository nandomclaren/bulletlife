// Look and words (CLAUDE.md 8). Colors are the PWA's Classic palette, light and dark; the UI is in English,
// with every string here (8.1), so other languages can come later.
import BulletLifeCore
import SwiftUI
import UIKit

enum Theme {
    // MARK: Theme and palette (Settings, kept on this device like the PWA's)

    /// Automatic (the system's light or dark), Paper (light), Graphite (dark), Night (black, for OLED).
    enum Look: String, CaseIterable, Identifiable {
        case auto, paper, graphite, night
        var id: String { rawValue }
        var name: String { S.themes[rawValue] ?? rawValue }
        var hint: String { S.themeHints[rawValue] ?? "" }
        /// What the window is held to (nil: the system decides).
        var style: UIUserInterfaceStyle {
            switch self {
            case .auto: return .unspecified
            case .paper: return .light
            case .graphite, .night: return .dark
            }
        }
    }

    /// The bullets' colors: task, event, note, each with a light and a dark version (the theme picks one).
    enum Palette: String, CaseIterable, Identifiable {
        case classic, ocean, forest, dusk, ink
        var id: String { rawValue }
        var name: String { S.palettes[rawValue] ?? rawValue }
        /// task, event, note: (light, dark).
        var colors: [(UInt32, UInt32)] {
            switch self {
            case .classic: return [(0xE0533D, 0xEF6B56), (0x3B82C4, 0x5B9BD8), (0x2A9D8F, 0x3BB3A4)]
            case .ocean: return [(0x2563A8, 0x6AA3E8), (0xD2603F, 0xF08A70), (0xB0852A, 0xD9AC55)]
            case .forest: return [(0x2F7D4F, 0x5CB37F), (0xB0683A, 0xD8905F), (0x7A6AA8, 0xA99BE0)]
            case .dusk: return [(0x6B4FBB, 0xA690EE), (0xC4467A, 0xE6789F), (0x2C8F8A, 0x4FBDB6)]
            // Like a fountain pen notebook: tasks in ink, the rest in quiet tones.
            case .ink: return [(0x2B2D31, 0xE4E1DB), (0x5A7898, 0x8FA9C4), (0x9A8F80, 0xA39A8C)]
            }
        }
    }

    static var look: Look {
        _ = watcher
        return currentLook
    }
    static var palette: Palette {
        _ = watcher
        return currentPalette
    }
    private static var currentLook = Look(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .auto
    private static var currentPalette = Palette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .classic
    /// Settings are written through @AppStorage: the choice is read again as soon as it is stored, before any
    /// view is drawn with it.
    private static let watcher: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: UserDefaults.didChangeNotification, object: nil, queue: nil
    ) { _ in
        currentLook = Look(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .auto
        currentPalette = Palette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .classic
    }

    /// A color that follows light and dark, and Night's deeper tones.
    static func shaded(_ light: UInt32, _ dark: UInt32, night: UInt32? = nil) -> UIColor {
        UIColor { t in
            guard t.userInterfaceStyle == .dark else { return UIColor(hex: light) }
            return UIColor(hex: look == .night ? night ?? dark : dark)
        }
    }

    static var paper: Color { Color(uiColor: ui("paper")) }
    static var text: Color { Color(uiColor: ui("text")) }
    static var muted: Color { Color(uiColor: ui("muted")) }
    static var rule: Color { Color(uiColor: ui("rule")) }
    static var task: Color { Color(uiColor: ui("task")) }
    static var event: Color { Color(uiColor: ui("event")) }
    static var note: Color { Color(uiColor: ui("note")) }

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color { Color(uiColor: shaded(light, dark)) }
    static func dynamicUI(_ light: UInt32, _ dark: UInt32) -> UIColor { shaded(light, dark) }

    /// UIKit colors by token: the pen's colors ('ink' and the bullets'), and the page's ('paper', 'text',
    /// 'muted', 'rule'). The same instance each time, so the editor can tell whether a line already has its
    /// color; they read the theme and palette when drawn.
    static func ui(_ token: String) -> UIColor {
        if let c = uiCache[token] { return c }
        let c = makeUI(token)
        uiCache[token] = c
        return c
    }

    private static var uiCache: [String: UIColor] = [:]

    private static func bullet(_ k: Int) -> UIColor {
        UIColor { t in
            let c = palette.colors[k]
            return UIColor(hex: t.userInterfaceStyle == .dark ? c.1 : c.0)
        }
    }

    private static func makeUI(_ token: String) -> UIColor {
        switch token {
        case "task": return bullet(0)
        case "event": return bullet(1)
        case "note": return bullet(2)
        case "paper": return shaded(0xFAF8F4, 0x141414, night: 0x000000)
        case "muted": return shaded(0x726D65, 0x8D8A85, night: 0x85827D)
        case "rule": return shaded(0xE6E1D8, 0x2A2A2A, night: 0x222222)
        default: return shaded(0x1F1D1A, 0xECE9E4, night: 0xE6E3DE)  // 'ink', 'text', a heading
        }
    }

    /// Rich Text uses the palette in use, light version (pasted documents are usually white).
    static var exportColors: Export.Colors {
        var c = Export.Colors()
        let hex = { (v: UInt32) in String(format: "#%06X", v) }
        c.task = hex(palette.colors[0].0)
        c.event = hex(palette.colors[1].0)
        c.note = hex(palette.colors[2].0)
        return c
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

/// Behind a floating header: the page shows through, blurred, and the blur fades out at its lower edge.
struct HeaderBlur: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.75), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom)
            )
            .ignoresSafeArea(edges: .top)
    }
}

extension View {
    /// A time page's header floating over its content: the page's width, blurred page behind.
    func floatingHeaderStyle(width: CGFloat = 720) -> some View {
        self
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(HeaderBlur())
    }
}

/// Puts a scroll view's content below a floating header, keeping it at the top if it was there.
func setTopInset(_ view: UIScrollView, _ top: CGFloat) {
    guard view.contentInset.top != top else { return }
    let atTop = view.contentOffset.y <= -view.adjustedContentInset.top + 1
    view.contentInset.top = top
    view.verticalScrollIndicatorInsets.top = top
    if atTop { view.contentOffset.y = -view.adjustedContentInset.top }
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
    static let looks = "Look"
    static let pageLayout = "Pages"
    static let singlePage = "One page"
    static let twoPages = "Two pages"
    static let openBook = "Open book"
    static let closePage = "Close page"
    static let pageDivider = "Divider between pages"
    static let closeRightPage = "Close the right page"
    static let closeLeftPage = "Close the left page"
    static let search = "Search"
    static let searchPrompt = "Entries and collections"
    static let entriesSection = "Entries"
    static let nothingFound = "Nothing found."
    static let done = "Done"
    static let openCount = "Count on Open items"
    static let theme = "Theme"
    static let themes = ["auto": "Automatic", "paper": "Paper", "graphite": "Graphite", "night": "Night"]
    static let themeHints = ["auto": "Follows the system", "paper": "Light", "graphite": "Dark", "night": "Black, for OLED screens"]
    static let palette = "Palette"
    static let paletteHint = "Colors of task, event and note bullets. Each palette has a light and a dark version."
    static let palettes = ["classic": "Classic", "ocean": "Ocean", "forest": "Forest", "dusk": "Dusk", "ink": "Ink"]
    static let doneAnimation = "Done animation"
    static let doneAnimationHint = "Plays when you complete an entry; a quieter version when you cancel one. Tap the bullet to preview."
    static let doneAnimations = [
        "ink": "Ink", "pop": "Pop", "ripple": "Ripple", "sparks": "Sparks", "highlighter": "Highlighter", "settle": "Settle",
        "colorSparks": "Colored sparks",
    ]
    static let doneAnimationHints = [
        "ink": "The mark is drawn like a pen stroke", "pop": "The bullet swells for a moment", "ripple": "A thin ring spreads and fades",
        "sparks": "Six tiny dots burst and fade", "highlighter": "A soft swipe of color across the text",
        "settle": "The line takes a small breath", "colorSparks": "Sparks in red, blue and green",
    ]
    static let previewTask = "Water the plants"
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
    static let drawing = "Drawing"
    static let handwritingPending = "Handwriting, not transcribed yet"
    static let deleteDrawing = "Delete drawing"
    static let due = "Due"
    static let sortByDate = "Sort by date"
    static let dateFormat = "Date format"
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
    static let lasso = "Lasso"
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
