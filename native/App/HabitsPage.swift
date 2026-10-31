// A Habits collection (Fernando's spread from his notebook): one page per month. The days of the month are
// columns (number and weekday initial, a quiet rule between weeks, as in the Month), the habits are rows the
// user writes, and each day of a habit takes a mark: done (× or ✓, as in Settings), not done (a dot) or
// skipped (a dash, no penalty). A tap moves the mark on; holding a day offers the four. Nothing is carried to
// the next month: its habits are written again by hand (CLAUDE.md principle 1).
// Pen mode (iPad): a habit's name is written by hand and kept as ink on its row (transcribed for Type mode, like
// any handwritten line); a mark written on a day is read (a dot, a dash, anything else is done) and shows as the
// app's own symbol, in both modes. The finger still scrolls and taps.
import BulletLifeCore
import PencilKit
import SwiftData
import SwiftUI

struct HabitsPage: View {
    let collection: Log
    var onIndex: () -> Void
    @EnvironmentObject private var nav: Navigator
    @Environment(\.modelContext) private var context
    @Environment(\.pageRole) private var role
    @Environment(\.focusMode) private var focus
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var month = Dates.monthOf(Dates.today())
    @State private var rows: [Entry] = []
    @State private var title = ""
    @State private var newName = ""
    /// The day opened from Open items: its column is marked for a moment.
    @State private var marked: String?
    @State private var removing: Entry?
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false
    @FocusState private var addingFocused: Bool
    @AppStorage("penMode") private var penOn = false
    @AppStorage("handwritingLang") private var handwritingLang = HandwritingLang.ptBR.rawValue
    @ObservedObject private var handwriting = Handwriting.shared
    /// The Apple Pencil's double tap: the eraser for the names, and back.
    @State private var erasing = false
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// Pen mode here: on a tablet, on the main page.
    private var pen: Bool { penOn && isPad && role != .second }

    private var repo: Repository { Repository(context: context) }
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Narrower on the iPhone, so a week of days still fits beside the names.
    private var nameWidth: CGFloat { sizeClass == .compact ? 112 : 160 }
    private let cell: CGFloat = 30
    /// One ruled line of the pen (40 pt), so a name is written on a line as on any page.
    private let rowHeight: CGFloat = 40

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                header
                // The names stay put (iPad upright, iPhone); only the days scroll sideways.
                HStack(alignment: .top, spacing: 0) {
                    names
                        .frame(width: nameWidth, alignment: .leading)
                        .overlay(alignment: .trailing) { Theme.rule.frame(width: 1) }
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            grid.padding(.trailing, 24)
                        }
                        .onChange(of: marked) { if let marked { withAnimation { proxy.scrollTo(marked, anchor: .center) } } }
                        .onAppear {
                            // Opens on today's week, when today is in this month.
                            let today = Dates.today()
                            if Dates.monthOf(today) == month { DispatchQueue.main.async { proxy.scrollTo(today, anchor: .center) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.paper)
        .onAppear {
            title = collection.title
            applyFocus()
            load()
        }
        .onChange(of: month) { load() }
        .onChange(of: nav.focus) { applyFocus() }
        .onChange(of: nav.highlight) { applyFocus() }
        .onChange(of: collection.id) {
            title = collection.title
            load()
        }
        .onDisappear(perform: rename)
        .task(id: transcriptionKey) { await transcribe() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if role != .second && !focus {
                HStack(spacing: 12) {
                    Button {
                        rename()
                        onIndex()
                    } label: {
                        Text("‹ \(S.index)")
                    }
                    .font(Theme.body(15))
                    Spacer()
                    Button { month = Dates.addMonths(month, -1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                        .accessibilityLabel(S.previousMonth)
                    Button(S.today) { month = Dates.monthOf(Dates.today()) }
                        .buttonStyle(.bordered)
                        .font(Theme.body(15, weight: .medium))
                    Button { month = Dates.addMonths(month, 1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                        .accessibilityLabel(S.nextMonth)
                    if isPad {
                        Picker("", selection: $penOn) {
                            Image(systemName: "keyboard").accessibilityLabel(S.typeMode).tag(false)
                            Image(systemName: "pencil.tip").accessibilityLabel(S.penMode).tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 96)
                    }
                    Menu {
                        Button(S.deleteCollection, role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(S.collectionMenu)
                }
            }
            Text(PageView.format("\(month)-01", "MMMM yyyy").uppercased())
                .font(Theme.body(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            TextField(S.name, text: $title)
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(Theme.text)
                .submitLabel(.done)
                .onSubmit(rename)
        }
        .confirmationDialog(S.deleteTitle(collection.title), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(S.delete, role: .destructive) { confirmDeleteAgain = true }
        } message: {
            Text(S.deleteMessage(repo.entryCount(logId: collection.id)))
        }
        .alert(S.deleteAgainTitle, isPresented: $confirmDeleteAgain) {
            Button(S.deleteForever, role: .destructive) {
                repo.deleteCollection(id: collection.id)
                onIndex()
            }
            Button(S.cancel, role: .cancel) {}
        } message: {
            Text(S.deleteAgainMessage)
        }
        .confirmationDialog(removing?.text ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(S.deleteHabit, role: .destructive) {
                if let r = removing { repo.deleteHabit(id: r.id) }
                removing = nil
                load()
            }
        }
    }

    // MARK: Grid

    private var days: [String] { Dates.monthDays(month) }

    /// A quiet rule before each new week (as between the Month's weeks).
    private func weekStarts(_ iso: String) -> Bool {
        iso != days.first && Dates.weekday(iso) == firstDay
    }

    /// The fixed column: the habits' names, and the line to write a new one.
    private var names: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: headerHeight)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    nameCell(row)
                        .padding(.trailing, 8)
                        .frame(height: rowHeight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1) }
                        .contextMenu {
                            Button(S.deleteHabit, systemImage: "trash", role: .destructive) { removing = row }
                        }
                }
                if role != .second {
                    Group {
                        if pen {
                            Text(S.newHabit).font(Theme.body(16)).foregroundStyle(Theme.rule)
                        } else {
                            TextField(S.newHabit, text: $newName)
                                .font(Theme.body(16))
                                .focused($addingFocused)
                                .submitLabel(.done)
                                .onSubmit(add)
                        }
                    }
                    .padding(.trailing, 8)
                    .frame(height: rowHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .overlay {
                if pen {
                    HabitNamesCanvas(
                        rows: rows, rowHeight: rowHeight, erasing: erasing,
                        onWrite: write, onErase: erase, onPencilTap: { erasing.toggle() })
                }
            }
        }
    }

    /// A habit's name: typed (or its transcription), or its handwriting. Pen mode shows the handwriting (the
    /// canvas over the column draws it); Type mode the text, or the ink while it is not transcribed yet.
    @ViewBuilder private func nameCell(_ row: Entry) -> some View {
        let hand = row.ink?.hasWriting ?? false
        if pen {
            if !hand { Text(row.text).font(Theme.body(16)).foregroundStyle(Theme.text).lineLimit(1) }
        } else if hand && row.text.isEmpty, let image = HabitInk.image(row, height: rowHeight) {
            Image(uiImage: image).resizable().scaledToFit().frame(height: rowHeight * 0.7)
        } else {
            TextField(S.newHabit, text: name(row))
                .font(Theme.body(16))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
        }
    }

    private let headerHeight: CGFloat = 40

    /// The days: a header of numbers and initials, then one row of marks per habit.
    private var grid: some View {
        let today = Dates.today()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { iso in
                    VStack(spacing: 2) {
                        Text(String(Int(iso.suffix(2)) ?? 0))
                            .font(Theme.body(12, weight: iso == today ? .bold : .medium).monospacedDigit())
                        Text(PageView.format(iso, "EEEEE"))
                            .font(Theme.body(11, weight: .medium))
                    }
                    .foregroundStyle(iso == today ? Theme.task : [0, 6].contains(Dates.weekday(iso)) ? Theme.muted : Theme.text)
                    .frame(width: cell, height: headerHeight)
                    .overlay(alignment: .leading) { if weekStarts(iso) { Theme.rule.frame(width: 1) } }
                    .accessibilityLabel(PageView.format(iso, "EEEE MMMM d"))
                    .id(iso)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element) { i, iso in
                            dayCell(row, day: i + 1, iso: iso, today: today)
                        }
                    }
                    .frame(height: rowHeight)
                    .overlay(alignment: .bottom) { Theme.rule.opacity(0.5).frame(height: 1) }
                }
            }
            .overlay {
                // The pen writes marks on the days (read, then shown as the app's symbols); the finger taps.
                if pen && !rows.isEmpty {
                    HabitMarksCanvas(
                        rows: rows.count, days: days.count, cell: cell, rowHeight: rowHeight,
                        onMark: { r, day, mark in if r < rows.count { set(rows[r], day: day, mark) } },
                        onTap: { r, day in
                            if r < rows.count { set(rows[r], day: day, Habits.mark(rows[r].marks, day: day).next) }
                        })
                }
            }
            if role != .second {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { iso in
                        Color.clear.frame(width: cell, height: rowHeight)
                            .overlay(alignment: .leading) { if weekStarts(iso) { Theme.rule.frame(width: 1) } }
                    }
                }
            }
        }
    }

    private func dayCell(_ row: Entry, day: Int, iso: String, today: String) -> some View {
        let mark = Habits.mark(row.marks, day: day)
        return Button {
            set(row, day: day, mark.next)
        } label: {
            glyph(mark)
                .frame(width: cell, height: rowHeight)
                .background(columnTint(iso, today: today))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) { if weekStarts(iso) { Theme.rule.frame(width: 1) } }
        .contextMenu {
            ForEach([HabitMark.done, .missed, .skipped, .empty], id: \.self) { m in
                Button(S.habitMarks[m] ?? "") { set(row, day: day, m) }
            }
        }
        .accessibilityLabel("\(row.text), \(PageView.format(iso, "MMMM d")): \(S.habitMarks[mark] ?? "")")
    }

    @ViewBuilder private func glyph(_ mark: HabitMark) -> some View {
        switch mark {
        case .done:
            Text(doneMark).font(Theme.body(17, weight: .semibold)).foregroundStyle(Theme.task)
        case .missed:
            Circle().fill(Theme.text).frame(width: 5, height: 5)
        case .skipped:
            Capsule().fill(Theme.muted).frame(width: 11, height: 2)
        case .empty:
            // The paper's dot grid: a faint dot where nothing is marked yet.
            Circle().fill(Theme.rule).frame(width: 3, height: 3)
        }
    }

    private func columnTint(_ iso: String, today: String) -> Color {
        if iso == marked { return Theme.task.opacity(0.14) }
        if iso == today { return Theme.task.opacity(0.06) }
        return .clear
    }

    // MARK: Writing

    private func name(_ row: Entry) -> Binding<String> {
        Binding(
            get: { rows.first { $0.id == row.id }?.text ?? row.text },
            set: { text in
                guard let i = rows.firstIndex(where: { $0.id == row.id }) else { return }
                rows[i].text = text
                repo.saveHabit(rows[i])
            })
    }

    private func set(_ row: Entry, day: Int, _ mark: HabitMark) {
        guard let i = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[i].marks = Habits.setting(rows[i].marks, day: day, to: mark)
        repo.saveHabit(rows[i])
    }

    /// A habit is added only by writing it (one row; nothing is copied from another month).
    private func add() {
        let text = newName.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let order = (try? OrderKey.between(rows.last?.order, nil)) ?? "a\(rows.count)"
        let now = Repository.now()
        let e = Entry(id: ULID.make(), logId: collection.id, slot: month, order: order, text: text, createdAt: now, updatedAt: now)
        repo.saveHabit(e)
        newName = ""
        load()
        addingFocused = true
    }

    /// A stroke written on the names: on a habit's line it joins that habit's name; on the line below the last,
    /// it starts a new habit (as on paper).
    private func write(_ index: Int, _ stroke: Stroke) {
        if index < rows.count {
            var ink = rows[index].ink ?? Ink(strokes: [])
            ink.strokes.append(stroke)
            rows[index].ink = ink
            repo.saveHabit(rows[index])
        } else {
            let order = (try? OrderKey.between(rows.last?.order, nil)) ?? "a\(rows.count)"
            let now = Repository.now()
            let e = Entry(
                id: ULID.make(), logId: collection.id, slot: month, order: order, ink: Ink(strokes: [stroke]), createdAt: now,
                updatedAt: now)
            repo.saveHabit(e)
            rows.append(e)
        }
    }

    /// Strokes erased with the pen (only the pen erases handwriting). A name left with no ink, text or marks goes.
    private func erase(_ hits: [String: Set<Int>]) {
        for (id, gone) in hits {
            guard let i = rows.firstIndex(where: { $0.id == id }), var ink = rows[i].ink else { continue }
            let transcribed = ink.tx != nil && rows[i].text == ink.tx
            ink.strokes = ink.strokes.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            ink.n = nil
            if !ink.hasWriting && transcribed { rows[i].text = "" }
            rows[i].ink = ink.strokes.isEmpty ? nil : ink
            if rows[i].ink == nil && rows[i].text.isEmpty && (rows[i].marks ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                repo.deleteHabit(id: id)
            } else {
                repo.saveHabit(rows[i])
            }
        }
        load()
    }

    // MARK: Transcription (as on any page with handwriting)

    private var transcriptionKey: String {
        let lines = rows.map { Line(id: $0.id, text: $0.text, ink: $0.ink) }
        return "\(collection.id)|\(month)|\(pen)|\(Transcription.writingTotal(lines))|\(Transcription.pending(lines).count)|\(handwritingLang)|\(handwriting.status == .ready)"
    }

    private func transcribe() async {
        var lines = rows.map { Line(id: $0.id, text: $0.text, ink: $0.ink) }
        guard !Transcription.jobs(lines).isEmpty else { return }
        if pen { try? await Task.sleep(for: .seconds(2.5)) }
        let lang = HandwritingLang(rawValue: handwritingLang) ?? .ptBR
        for job in Transcription.jobs(lines) {
            guard !Task.isCancelled, let text = await handwriting.recognize(job.strokes, lang: lang), !Task.isCancelled else { return }
            guard let next = Transcription.apply(id: job.id, n: job.n, text: text, shape: job.shape, to: lines) else { continue }
            lines = next
            guard let line = next.first(where: { $0.id == job.id }), let i = rows.firstIndex(where: { $0.id == job.id }) else { continue }
            rows[i].text = line.text
            rows[i].ink = line.ink
            repo.saveHabit(rows[i])
        }
    }

    private func load() {
        rows = repo.habits(logId: collection.id, month: month)
    }

    private func rename() {
        let next = title.trimmingCharacters(in: .whitespaces)
        if next.isEmpty { title = collection.title } else if next != collection.title { repo.renameCollection(id: collection.id, title: next) }
    }

    /// Opened on a day (from Open items, or a search result's month): that month, with the day's column marked.
    private func applyFocus() {
        // Only a fresh opening with a target (a stale focus from another page is left alone).
        guard nav.highlight != nil, let f = nav.focus, f.count >= 7 else { return }
        let ym = String(f.prefix(7))
        if ym != month { month = ym }
        guard f.count == 10 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            marked = f
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { withAnimation { if marked == f { marked = nil } } }
        }
    }
}

// MARK: - The pen on a habits page

extension Habits {
    /// Today's habits are owed only from the evening check-in (Settings › Close the day's time, 20:00 by default).
    static var todayDue: Bool {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date()) >= (UserDefaults.standard.string(forKey: "closeDayAt") ?? "20:00")
    }
}

enum HabitInk {
    /// A PencilKit stroke in the app's format (as the pen page stores it).
    static func stroke(_ pk: PKStroke, dy: Double = 0) -> Stroke {
        var p: [Double] = []
        for point in pk.path {
            let at = point.location.applying(pk.transform)
            p.append((Double(at.x) * 10).rounded() / 10)
            p.append(((Double(at.y) - dy) * 10).rounded() / 10)
            p.append((min(1, max(0, Double(point.force))) * 100).rounded() / 100)
        }
        return Stroke(k: .writing, c: "ink", p: p, pen: true)
    }

    /// A name's handwriting as a picture (Type mode, until it is transcribed).
    static func image(_ row: Entry, height: CGFloat) -> UIImage? {
        guard let strokes = row.ink?.strokes.filter({ $0.k == .writing }), !strokes.isEmpty else { return nil }
        let pks = strokes.enumerated().map { n, s in
            PenSheetView.Coordinator.pkStroke(s, color: Theme.ui(s.c), date: Date(timeIntervalSinceReferenceDate: Double(n)))
        }
        let drawing = PKDrawing(strokes: pks)
        let bounds = drawing.bounds.insetBy(dx: -2, dy: -2)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return drawing.image(from: bounds, scale: UIScreen.main.scale)
    }

    static func pencilTool() -> PKTool { PKInkingTool(penInk, color: Theme.ui("ink"), width: penWidth(defaultPenSize)) }
}

/// The pen over the habits' names: a stroke on a habit's line joins its name; below the last, a new habit. The
/// finger passes through (it scrolls); the Apple Pencil's double tap switches to the eraser and back.
struct HabitNamesCanvas: UIViewRepresentable {
    let rows: [Entry]
    let rowHeight: CGFloat
    var erasing: Bool
    var onWrite: (Int, Stroke) -> Void
    var onErase: ([String: Set<Int>]) -> Void
    var onPencilTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        canvas.tool = HabitInk.pencilTool()
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)
        context.coordinator.canvas = canvas
        context.coordinator.render()
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if erasing != c.erasing {
            c.erasing = erasing
            canvas.tool = erasing ? PKEraserTool(.vector) : HabitInk.pencilTool()
        }
        if c.signature != Coordinator.signature(rows) { c.render() }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        var parent: HabitNamesCanvas
        weak var canvas: PKCanvasView?
        var erasing = false
        var signature = ""
        /// Who each drawn stroke belongs to (entry id, index in its ink), by the stroke's key.
        private var owners: [(key: String, id: String, index: Int)] = []
        private var rendering = false

        init(_ parent: HabitNamesCanvas) { self.parent = parent }

        static func signature(_ rows: [Entry]) -> String {
            rows.map { "\($0.id):\($0.ink?.strokes.count ?? 0)" }.joined(separator: ",")
        }

        func render() {
            guard let canvas else { return }
            var strokes: [PKStroke] = []
            owners = []
            for (r, row) in parent.rows.enumerated() {
                for (i, s) in (row.ink?.strokes ?? []).enumerated() where s.k == .writing {
                    var moved = s
                    moved.p = s.p.enumerated().map { j, v in j % 3 == 1 ? v + Double(r) * Double(parent.rowHeight) : v }
                    let pk = PenSheetView.Coordinator.pkStroke(
                        moved, color: Theme.ui(s.c), date: Date(timeIntervalSinceReferenceDate: Double(strokes.count)))
                    strokes.append(pk)
                    owners.append((PenSheetView.Coordinator.key(pk), row.id, i))
                }
            }
            signature = Self.signature(parent.rows)
            rendering = true
            canvas.drawing = PKDrawing(strokes: strokes)
            rendering = false
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !rendering else { return }
            let strokes = canvas.drawing.strokes
            if strokes.count > owners.count {
                for pk in strokes[owners.count...] {
                    let b = pk.renderBounds
                    let r = max(0, min(parent.rows.count, Int(b.midY / parent.rowHeight)))
                    parent.onWrite(r, HabitInk.stroke(pk, dy: Double(r) * Double(parent.rowHeight)))
                }
            } else if strokes.count < owners.count {
                let kept = Set(strokes.map(PenSheetView.Coordinator.key))
                var hits: [String: Set<Int>] = [:]
                for o in owners where !kept.contains(o.key) { hits[o.id, default: []].insert(o.index) }
                if !hits.isEmpty { parent.onErase(hits) }
            }
        }

        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { tapped() }

        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { tapped() }

        private func tapped() {
            if UIPencilInteraction.preferredTapAction == .switchEraser || UIPencilInteraction.preferredTapAction == .switchPrevious {
                parent.onPencilTap()
            }
        }
    }
}

/// The pen over the days: each stroke is read as a mark on the day it was written on (a dot: not done; a flat
/// dash: skipped; anything else: done) and then taken away, so the day shows the app's own symbol. A finger's
/// tap moves the day's mark on, as in Type mode; the finger still scrolls.
struct HabitMarksCanvas: UIViewRepresentable {
    let rows: Int
    let days: Int
    let cell: CGFloat
    let rowHeight: CGFloat
    var onMark: (Int, Int, HabitMark) -> Void
    var onTap: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        canvas.tool = HabitInk.pencilTool()
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        canvas.addGestureRecognizer(tap)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: HabitMarksCanvas
        private var clearing = false

        init(_ parent: HabitMarksCanvas) { self.parent = parent }

        private func place(_ p: CGPoint) -> (row: Int, day: Int)? {
            let row = Int(p.y / parent.rowHeight), day = Int(p.x / parent.cell) + 1
            guard row >= 0, row < parent.rows, day >= 1, day <= parent.days else { return nil }
            return (row, day)
        }

        func canvasViewDrawingDidChange(_ canvas: PKCanvasView) {
            guard !clearing, !canvas.drawing.strokes.isEmpty else { return }
            for pk in canvas.drawing.strokes {
                let b = pk.renderBounds
                guard let at = place(CGPoint(x: b.midX, y: b.midY)) else { continue }
                parent.onMark(at.row, at.day, Habits.mark(written: HabitInk.stroke(pk)))
            }
            DispatchQueue.main.async { [weak self, weak canvas] in
                self?.clearing = true
                canvas?.drawing = PKDrawing()
                self?.clearing = false
            }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let at = place(g.location(in: g.view)) else { return }
            parent.onTap(at.row, at.day)
        }
    }
}
