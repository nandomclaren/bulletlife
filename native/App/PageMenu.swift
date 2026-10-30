// The page menu "…" (CLAUDE.md 7): Export, Copy As and Share, each in Markdown, Rich Text or Plain Text, and
// Export PDF. Built from the stored entries, never from the screen, so collapsed children are always included;
// with lines selected, only those (with their collapsed children).
import BulletLifeCore
import SwiftData
import SwiftUI
import UIKit

/// The lines selected in the page being edited, kept as the selection changes (tapping "…" can clear the
/// native selection before the menu reads it).
enum PageSelection {
    private(set) static var logId = ""
    private(set) static var lines: [Line] = []

    static func set(logId: String, _ lines: [Line]) {
        if lines.isEmpty && logId != self.logId { return }
        self.logId = logId
        self.lines = lines
    }

    /// The selection, if it belongs to this page.
    static func lines(for place: Place) -> [Line]? {
        guard !lines.isEmpty else { return nil }
        switch place {
        case .time(let p): return p.logId == logId ? lines : nil
        case .collection(let id): return id == logId ? lines : nil
        case .index: return nil
        }
    }
}

enum ExportFormat: CaseIterable {
    case markdown, rich, plain
    var name: String {
        switch self {
        case .markdown: return S.markdown
        case .rich: return S.richText
        case .plain: return S.plainText
        }
    }
    var ext: String {
        switch self {
        case .markdown: return "md"
        case .rich: return "html"
        case .plain: return "txt"
        }
    }
}

/// The exportable document of a page, from the stored entries (src/export/pageDoc.ts).
enum PageDocs {
    /// Settings › Export everything (the PWA's backup and everything.ts): the restorable backup (the PWA's JSON
    /// format, which Import reads back) and every written page in one readable Markdown file, Years, Months,
    /// Weeks and Days oldest first, then the collections by name. Files in the temporary folder, to share.
    static func everything(repo: Repository, firstDay: Weekday, style: GlyphStyle, now: Date = Date()) -> [URL] {
        let stamp = Self.stamp(now)
        let dir = FileManager.default.temporaryDirectory
        let json = dir.appendingPathComponent("BulletLife_\(stamp).json")
        let backup = Backup(createdAt: Repository.now(), logs: repo.collections(), entries: repo.allEntries())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? encoder.encode(backup).write(to: json)
        let written = repo.writtenLogIds()
        let kinds = ["future", "monthly", "weekly", "daily"]
        let time: [Place] = kinds.flatMap { kind in
            written.filter { $0.hasPrefix(kind + ":") }.sorted()
                .compactMap { Source(logId: $0, firstDay: firstDay).period.map { Place.time($0) } }
        }
        let collections: [Place] = repo.collections().filter { written.contains($0.id) }.map { .collection($0.id) }
        let pages = (time + collections).compactMap { build($0, repo: repo, firstDay: firstDay)?.doc }
            .filter { doc in doc.sections.contains { !$0.lines.isEmpty } }
        let md = dir.appendingPathComponent("BulletLife_\(stamp).md")
        try? pages.map { Export.markdown($0, style: style) }.joined(separator: "\n").write(to: md, atomically: true, encoding: .utf8)
        return [json, md]
    }

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        return f.string(from: d)
    }

    static func build(_ place: Place, repo: Repository, firstDay: Weekday) -> (doc: ExportDoc, name: String)? {
        switch place {
        case .index:
            return nil
        case .collection(let id):
            guard let log = repo.collection(id) else { return nil }
            return (ExportDoc(title: log.title, sections: [ExportSection(lines: repo.lines(logId: id))]), log.title)
        case .time(let p):
            switch p {
            case .day(let d):
                return (ExportDoc(title: PageView.format(d, "EEEE MMMM d yyyy"), sections: [ExportSection(lines: repo.lines(logId: p.logId))]), d)
            case .week(let k):
                let start = Dates.weekKeyStart(k, firstDay: firstDay)
                let range = "\(PageView.format(start, "MMM d")) – \(PageView.format(Dates.addDays(start, 6), "MMM d yyyy"))"
                return (
                    ExportDoc(title: "\(S.weekPage) \(Dates.weekNumber(k)) · \(range)", sections: [ExportSection(lines: repo.lines(logId: p.logId))]), k
                )
            case .month(let ym):
                let days = Dates.monthDays(ym).map { iso in
                    ExportSection(heading: "\(Int(iso.suffix(2)) ?? 0) \(PageView.format(iso, "EEE"))", lines: repo.lines(logId: p.logId, slot: iso))
                }
                return (
                    ExportDoc(
                        title: PageView.format("\(ym)-01", "MMMM yyyy"),
                        sections: days + [ExportSection(heading: S.monthTasks, lines: repo.lines(logId: p.logId))]), ym
                )
            case .year(let y):
                let months = (0..<12).map { n -> ExportSection in
                    let ym = Dates.addMonths("\(y)-01", n)
                    return ExportSection(heading: PageView.format("\(ym)-01", "MMMM"), lines: repo.lines(logId: p.logId, slot: ym))
                }
                return (ExportDoc(title: y, sections: months), y)
            }
        }
    }

    static func text(_ doc: ExportDoc, _ format: ExportFormat, style: GlyphStyle) -> String {
        switch format {
        case .markdown: return Export.markdown(doc, style: style)
        case .rich: return Export.html(doc, colors: Theme.exportColors)
        case .plain: return Export.plain(doc)
        }
    }
}

struct PageMenu: View {
    let place: Place
    @Environment(\.modelContext) private var context
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("glyphStyle") private var glyphStyle = GlyphStyle.checkboxes.rawValue
    @State private var sharing: [Any]?

    var body: some View {
        // Everything here takes the page out of the app (a file, the clipboard, another app): the system's
        // share icon says so better than "…".
        Menu {
            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.name) { share(f) } }
            } label: {
                Label(S.share, systemImage: "square.and.arrow.up")
            }
            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.name) { copy(f) } }
            } label: {
                Label(S.copyAs, systemImage: "doc.on.doc")
            }
            Menu {
                ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.name) { exportFile(f) } }
            } label: {
                Label(S.export, systemImage: "arrow.down.doc")
            }
            Divider()
            Button {
                exportPDF()
            } label: {
                Label(S.exportPDF, systemImage: "printer")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel(S.pageMenu)
        .disabled(place == .index)
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            ActivityView(items: sharing ?? [])
        }
    }

    private var style: GlyphStyle { GlyphStyle(rawValue: glyphStyle) ?? .checkboxes }

    /// The page, or the selected lines when there are some.
    private func current() -> (doc: ExportDoc, name: String)? {
        guard let built = PageDocs.build(place, repo: Repository(context: context), firstDay: firstDay) else { return nil }
        if let selected = PageSelection.lines(for: place) { return (ExportDoc.selection(selected), built.name) }
        return built
    }

    private func exportFile(_ f: ExportFormat) {
        guard let built = current() else { return }
        let (doc, name) = built
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName(name, f.ext))
        try? PageDocs.text(doc, f, style: style).write(to: url, atomically: true, encoding: .utf8)
        sharing = [url]
    }

    private func copy(_ f: ExportFormat) {
        guard let doc = current()?.doc else { return }
        switch f {
        case .rich: UIPasteboard.general.setItems([["public.html": Export.html(doc, colors: Theme.exportColors), "public.utf8-plain-text": Export.plain(doc)]])
        default: UIPasteboard.general.string = PageDocs.text(doc, f, style: style)
        }
    }

    private func share(_ f: ExportFormat) {
        guard let doc = current()?.doc else { return }
        sharing = [PageDocs.text(doc, f, style: style)]
    }

    private func exportPDF() {
        guard let pages = PrintPages.pages(for: place, repo: Repository(context: context), firstDay: firstDay), let first = pages.first else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(Self.fileName(first.fileName, "pdf"))
        try? PdfExport.render(pages, firstDay: firstDay).write(to: url)
        sharing = [url]
    }

    static func fileName(_ name: String, _ ext: String) -> String {
        let clean = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        return "\(clean.isEmpty ? "Bullet Life" : clean).\(ext)"
    }
}

/// The system share sheet (Save to Files, AirDrop, Mail, Print…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
