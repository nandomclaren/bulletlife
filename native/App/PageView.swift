// A free page of the notebook (Day or Week): its lines, written straight away, in the page editor (Type mode)
// or on the ruled sheet (Pen mode, iPad).
import BulletLifeCore
import SwiftData
import SwiftUI
import UIKit

struct PageView: View {
    @Binding var period: Period
    /// A collection instead of a time page (its own header: back to the Index, its editable name).
    var collection: Log? = nil
    var onIndex: () -> Void = {}
    @State private var collectionTitle = ""
    /// The floating header's height: the page starts below it and scrolls under it.
    @State private var headerHeight: CGFloat = 0
    /// The toolbar's height above the page: the text and the sheet start below it, but scroll up under it.
    @State private var safeTop: CGFloat = 0
    /// Deleting a collection asks twice.
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false
    @EnvironmentObject private var nav: Navigator
    @Environment(\.pageRole) private var role
    @Environment(\.scenePhase) private var scenePhase
    @State private var saver = PageSaver()
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
    private var logId: String { collection?.id ?? period.logId }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// The second of two pages: read, not written (only a bullet's tap or menu, one entry at a time).
    private var consulting: Bool { role == .second }

    var body: some View {
        Group {
            if penOn && isPad && !consulting { penPage } else { typePage }
        }
        .background(Theme.paper)
        .onAppear(perform: load)
        .onChange(of: period) { load() }
        .onChange(of: collection?.id) { load() }
        // A state changed from Open items: taken into the page, so what it writes next agrees.
        .onReceive(NotificationCenter.default.publisher(for: Repository.changedOutside)) { note in
            _ = note.patch(&lines, logId: logId)
        }
        // Read again when the page is written elsewhere (the page beside, while it is consulted here).
        .onReceive(NotificationCenter.default.publisher(for: Repository.saved)) { note in
            if consulting && note.isAbout(logId: logId) { lines = repo.lines(logId: logId) }
        }
        .onChange(of: lines) { if !consulting { saver.schedule(lines, logId: logId, repo: repo) } }
        .onChange(of: scenePhase) { if scenePhase != .active { saver.flush() } }
        .onDisappear { saver.flush() }
        // Starts again (and so waits again) with every stroke written or erased: a pause in writing.
        .task(id: transcriptionKey) { await transcribe() }
    }

    // MARK: Transcription (N3)

    private var transcriptionKey: String {
        "\(logId)|\(penOn)|\(Transcription.writingTotal(lines))|\(handwritingLang)|\(handwriting.status == .ready)"
    }

    /// Reads the handwriting the last pass didn't, after a pause in writing (at once in Type mode). The ink is
    /// already saved; the text is its transcription, and a correction typed in Type mode is never overwritten.
    private func transcribe() async {
        guard !consulting, !Transcription.jobs(lines).isEmpty else { return }
        if penOn && isPad { try? await Task.sleep(for: .seconds(2.5)) }
        let lang = HandwritingLang(rawValue: handwritingLang) ?? .ptBR
        for job in Transcription.jobs(lines) {
            guard !Task.isCancelled, let text = await handwriting.recognize(job.strokes, lang: lang), !Task.isCancelled else { return }
            if let next = Transcription.apply(id: job.id, n: job.n, text: text, shape: job.shape, to: lines) { lines = next }
        }
    }

    private var penPage: some View {
        ZStack(alignment: .top) {
            PenSheetView(
                lines: $lines, tool: penTool, color: penColor, size: penSize, eventStates: eventStates, doneMark: doneMark,
                undoRequests: undoRequests, topInset: headerHeight + safeTop, onCanUndo: { canUndo = $0 }
            )
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            // The sheet goes up under the toolbar too, so the ink passes under the header and is not cut short.
            .ignoresSafeArea(edges: .top)
            // How far under the toolbar it reaches (the safe area it now covers).
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { safeTop = $0 }
            floatingHeader(width: 760)
        }
        .overlay(alignment: .bottom) {
            PenToolbar(tool: $penTool, color: $penColor, size: $penSize, canUndo: canUndo) { undoRequests += 1 }
                .padding(.bottom, 16)
        }
    }

    private var typePage: some View {
        ZStack(alignment: .top) {
            PageEditorView(
                lines: $lines, eventStates: eventStates, doneMark: doneMark,
                highlight: lines.contains { $0.id == nav.highlight } ? nav.highlight : nil, topInset: headerHeight + safeTop,
                readOnly: consulting, onSelection: { PageSelection.set(logId: logId, $0) }
            ) { act($0, on: $1) }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            // The text goes up under the toolbar too, so it passes under the header and is not cut short.
            .ignoresSafeArea(edges: .top)
            // How far under the toolbar it reaches (the safe area it now covers).
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { safeTop = $0 }
            floatingHeader(width: 720)
        }
    }

    /// The header floats over the page, which scrolls under it, seen blurred through (as in a notes app).
    private func floatingHeader(width: CGFloat) -> some View {
        header
            .floatingHeaderStyle(width: width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if consulting, collection != nil {
            // Consulted: only its name.
            VStack(alignment: .leading, spacing: 10) {
                Text(S.collections.uppercased())
                    .font(Theme.body(13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                Text(collectionTitle.isEmpty ? S.untitled : collectionTitle)
                    .font(Theme.body(30, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 44)
        } else if collection != nil {
            collectionHeader
        } else {
            TimeHeader(period: $period, label: label, title: title) { penPicker }
        }
    }

    @ViewBuilder private var penPicker: some View {
        if isPad {
            Picker("", selection: $penOn) {
                Image(systemName: "keyboard").accessibilityLabel(S.typeMode).tag(false)
                Image(systemName: "pencil.tip").accessibilityLabel(S.penMode).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
        }
    }

    /// A collection: back to the Index, then its name, which can be edited in place.
    private var collectionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    renameCollection()
                    onIndex()
                } label: {
                    Text("‹ \(S.index)")
                }
                .font(Theme.body(15))
                Spacer()
                penPicker
                Menu {
                    Button(S.deleteCollection, role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(S.collectionMenu)
            }
            Text(S.collections.uppercased())
                .font(Theme.body(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            TextField(S.name, text: $collectionTitle)
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(renameCollection)
        }
        .onDisappear(perform: renameCollection)
        .confirmationDialog(S.deleteTitle(collection?.title ?? ""), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(S.delete, role: .destructive) { confirmDeleteAgain = true }
        } message: {
            Text(S.deleteMessage(collection.map { repo.entryCount(logId: $0.id) } ?? 0))
        }
        .alert(S.deleteAgainTitle, isPresented: $confirmDeleteAgain) {
            Button(S.deleteForever, role: .destructive) { deleteCollection() }
            Button(S.cancel, role: .cancel) {}
        } message: {
            Text(S.deleteAgainMessage)
        }
    }

    private func deleteCollection() {
        guard let collection else { return }
        saver.flush()
        repo.deleteCollection(id: collection.id)
        onIndex()
    }

    private func renameCollection() {
        guard let collection else { return }
        let next = collectionTitle.trimmingCharacters(in: .whitespaces)
        if next.isEmpty { collectionTitle = collection.title } else if next != collection.title { repo.renameCollection(id: collection.id, title: next) }
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
        saver.flush()  // what was written on the page before goes to that page
        if !penSizes.contains(penSize) { penSize = defaultPenSize }  // sizes from an earlier version
        lines = repo.lines(logId: logId)
        collectionTitle = collection?.title ?? ""
    }

    private func act(_ action: LineAction, on id: String) {
        if consulting, action != .toggleCollapsed {
            repo.consult(action, id: id, eventStates: eventStates)
        } else {
            action.apply(to: &lines, id: id, eventStates: eventStates)
        }
    }
}

enum LineAction: Equatable {
    case type(EntryType)
    case state(EntryState)
    case togglePriority, toggleInspiration, toggleExplore, indent, outdent, toggleCollapsed, delete

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
        case .toggleInspiration:
            lines[i].inspiration.toggle()
        case .toggleExplore:
            lines[i].explore.toggle()
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
