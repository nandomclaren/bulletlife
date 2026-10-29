// A free page of the notebook (Day or Week): its lines, written straight away, in the page editor (Type mode)
// or on the ruled sheet (Pen mode, iPad).
import BulletLifeCore
import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @State private var period: Period = .day(Dates.today())

    var body: some View {
        NavigationStack {
            page
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(S.settings)
                    }
                }
        }
        .tint(Theme.task)
    }

    /// Day and Week are free pages (Type or Pen); Month and Year have their fixed layouts.
    @ViewBuilder private var page: some View {
        switch period {
        case .day, .week: PageView(period: $period)
        case .month(let ym): MonthPage(ym: ym, period: $period)
        case .year(let y): YearPage(year: y, period: $period)
        }
    }
}

struct PageView: View {
    @Binding var period: Period
    @Environment(\.modelContext) private var context
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var lines: [Line] = []
    // Pen mode (iPad): kept on this device, like the PWA's.
    @AppStorage("penMode") private var penOn = false
    @AppStorage("penColor") private var penColor = "ink"
    @AppStorage("penSize") private var penSize = defaultPenSize
    @State private var penTool: PenTool = .write
    @State private var undoRequests = 0
    @State private var canUndo = false
    @AppStorage("handwritingLang") private var handwritingLang = HandwritingLang.ptBR.rawValue
    @ObservedObject private var handwriting = Handwriting.shared

    private var repo: Repository { Repository(context: context) }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        Group {
            if penOn && isPad { penPage } else { typePage }
        }
        .background(Theme.paper)
        .onAppear(perform: load)
        .onChange(of: period) { load() }
        .onChange(of: lines) { repo.save(lines, logId: period.logId) }
        // Starts again (and so waits again) with every stroke written or erased: a pause in writing.
        .task(id: transcriptionKey) { await transcribe() }
    }

    // MARK: Transcription (N3)

    private var transcriptionKey: String {
        "\(period.logId)|\(penOn)|\(Transcription.writingTotal(lines))|\(handwritingLang)|\(handwriting.status == .ready)"
    }

    /// Reads the handwriting the last pass didn't, after a pause in writing (at once in Type mode). The ink is
    /// already saved; the text is its transcription, and a correction typed in Type mode is never overwritten.
    private func transcribe() async {
        guard !Transcription.jobs(lines).isEmpty else { return }
        if penOn && isPad { try? await Task.sleep(for: .seconds(2.5)) }
        let lang = HandwritingLang(rawValue: handwritingLang) ?? .ptBR
        for job in Transcription.jobs(lines) {
            guard !Task.isCancelled, let text = await handwriting.recognize(job.strokes, lang: lang), !Task.isCancelled else { return }
            if let next = Transcription.apply(id: job.id, n: job.n, text: text, shape: job.shape, to: lines) { lines = next }
        }
    }

    private var penPage: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            PenSheetView(
                lines: $lines, tool: penTool, color: penColor, size: penSize, eventStates: eventStates, doneMark: doneMark,
                undoRequests: undoRequests, onCanUndo: { canUndo = $0 })
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            PenToolbar(tool: $penTool, color: $penColor, size: $penSize, canUndo: canUndo) { undoRequests += 1 }
                .padding(.bottom, 16)
        }
    }

    private var typePage: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 8)
            PageEditorView(lines: $lines, eventStates: eventStates, doneMark: doneMark) { act($0, on: $1) }
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    private var header: some View {
        TimeHeader(period: $period, label: label, title: title) {
            if isPad {
                Picker("", selection: $penOn) {
                    Image(systemName: "keyboard").accessibilityLabel(S.typeMode).tag(false)
                    Image(systemName: "pencil.tip").accessibilityLabel(S.penMode).tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }
        }
    }

    private var label: String {
        switch period {
        case .day(let d): return Self.format(d, "EEEE")
        case .week(let k): return "\(Self.format(Dates.weekKeyStart(k, firstDay: firstDay), "MMM d")) – \(Self.format(period.end(firstDay: firstDay), "MMM d"))"
        case .month(let m): return Self.format("\(m)-01", "MMMM")
        case .year(let y): return y
        }
    }

    private var title: String {
        switch period {
        case .day(let d): return Self.format(d, "MMMM d, yyyy")
        case .week(let k): return S.weekTitle(Dates.weekNumber(k))
        case .month(let m): return Self.format("\(m)-01", "MMMM yyyy")
        case .year(let y): return y
        }
    }

    static func format(_ iso: String, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en")
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f.string(from: Dates.fromIso(iso))
    }

    // MARK: Editing

    private func load() {
        if !penSizes.contains(penSize) { penSize = defaultPenSize }  // sizes from an earlier version
        lines = repo.lines(logId: period.logId)
    }

    private func act(_ action: LineAction, on id: String) {
        action.apply(to: &lines, id: id, eventStates: eventStates)
    }
}

enum LineAction {
    case type(EntryType)
    case state(EntryState)
    case togglePriority, indent, outdent, toggleCollapsed, delete

    /// What a bullet menu action (or a chevron) does to the page: always to one line.
    func apply(to lines: inout [Line], id: String, eventStates: Bool) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        switch self {
        case .type(let t):
            lines[i].type = t
            if !States.stateful(t, eventStates: eventStates) { lines[i].state = .open }
        case .state(let s):
            lines[i].state = s
        case .togglePriority:
            lines[i].priority.toggle()
        case .indent:
            if let shifted = PageEdit.shift(lines, from: i, to: i, delta: 1) { lines = shifted }
        case .outdent:
            if let shifted = PageEdit.shift(lines, from: i, to: i, delta: -1) { lines = shifted }
        case .toggleCollapsed:
            lines[i].collapsed.toggle()
        case .delete:
            // Its children move up one level (they are not deleted with it).
            lines = PageEdit.deleteLine(lines, id: id)
        }
    }
}
