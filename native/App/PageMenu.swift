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
        case .rich: return Export.html(doc)
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
        Menu {
            Menu(S.export) {
                ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.name) { exportFile(f) } }
            }
            Menu(S.copyAs) {
                ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.name) { copy(f) } }
            }
            Menu(S.share) {
                ForEach(ExportFormat.allCases, id: \.self) { f in Button(f.name) { share(f) } }
            }
            Divider()
            Button(S.exportPDF) { exportPDF() }
        } label: {
            Image(systemName: "ellipsis.circle")
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
        case .rich: UIPasteboard.general.setItems([["public.html": Export.html(doc), "public.utf8-plain-text": Export.plain(doc)]])
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
