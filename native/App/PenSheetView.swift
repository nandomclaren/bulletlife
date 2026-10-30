// Pen mode (CLAUDE.md 5, phase N2): the page as a ruled sheet, written on with PencilKit. PencilKit gets every
// Pencil touch from the system (the PWA's lost strokes) and rejects the palm; the finger scrolls. Where a
// stroke goes, and what erasing does, is BulletLifeCore's (PenRules, InkPage): this view only draws the page
// and reports what the pen did.
import BulletLifeCore
import PencilKit
import SwiftUI
import UIKit

enum PenTool: String, CaseIterable {
    case write, draw, erase, lasso
}

/// Pen sizes, as the stroke's drawn diameter: fine, medium, bold (Fernando's choice after trying them on the iPad;
/// about 30% thicker each).
let penSizes: [Double] = [2.7, 3.5, 4.5]
let defaultPenSize = 2.7
/// The size a stored stroke without `s` has (the PWA's format: its default size, 2.4).
let storedDefaultSize = 2.4

/// Ink of even width (a fine-liner, close to the PWA's "little width change with pressure"). The pen's own
/// ink varies with force and tilt, which a stored stroke can't reproduce, so a stroke thickened when the page
/// was drawn again; with even width the stroke as written and as stored look the same.
let penInk = PKInk.InkType.monoline

/// PencilKit draws a stroke's points larger than the tool's width. This ratio is measured on every stroke
/// (kept on the device) and the tool is set so the drawn stroke has the size asked for.
enum PenCalibration {
    private static let key = "penDrawRatio"
    static var ratio: Double {
        get {
            let r = UserDefaults.standard.double(forKey: key)
            return r > 0 ? r : 2.5  // first guess, corrected by the first stroke
        }
        set { if newValue > 0.5 && newValue < 10 { UserDefaults.standard.set(newValue, forKey: key) } }
    }
}

/// The tool's width for a pen size (a drawn diameter).
func penWidth(_ size: Double) -> CGFloat { CGFloat(size / PenCalibration.ratio) }

struct PenSheetView: UIViewRepresentable {
    @Binding var lines: [Line]
    var tool: PenTool
    var color: String
    var size: Double
    var eventStates: Bool
    var doneMark: String
    /// Bumped by the toolbar's Undo.
    var undoRequests: Int
    /// Room for a header floating over the sheet (it scrolls under it).
    var topInset: CGFloat = 0
    var onCanUndo: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SheetCanvas {
        let canvas = SheetCanvas()
        canvas.drawingPolicy = .pencilOnly
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.alwaysBounceVertical = true
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.delegate = context.coordinator
        let sheet = SheetBackground()
        canvas.insertSubview(sheet, at: 0)
        // The bullets' tap targets, over the ink (the finger taps them; the pen keeps writing).
        let bullets = PassThroughView()
        canvas.addSubview(bullets)
        let coordinator = context.coordinator
        coordinator.canvas = canvas
        coordinator.sheet = sheet
        coordinator.bullets = bullets
        canvas.onWidthChange = { [weak coordinator] in coordinator?.render() }
        return canvas
    }

    func updateUIView(_ canvas: SheetCanvas, context: Context) {
        let c = context.coordinator
        c.parent = self
        setTopInset(canvas, topInset)
        // Only when it changes: a new tool would drop the lasso's selection.
        let toolKey = "\(tool.rawValue)/\(color)/\(size)"
        if toolKey != c.toolKey {
            c.toolKey = toolKey
            canvas.tool = c.pkTool()
            if tool != .lasso && c.stale { c.render() }
        }
        c.sheet?.showsRules = tool != .draw
        if c.lines != lines {
            // A transcription keeps every stroke where it was (it only adds text and colors the bullet): the
            // page is drawn again but Undo keeps its steps. Another page, or other changes, start Undo afresh.
            let sameInk = c.lines.map(\.id) == lines.map(\.id) && c.lines.map { $0.ink?.strokes.map(\.p) } == lines.map { $0.ink?.strokes.map(\.p) }
            c.lines = lines
            if !sameInk {
                c.history.removeAll()
                DispatchQueue.main.async { onCanUndo(false) }
            }
            if sameInk && tool == .lasso {
                // While the lasso may hold a selection, a transcription only updates the sheet (the ink's
                // colors follow when the tool changes).
                c.relayout()
            } else {
                c.render()
            }
        }
        if undoRequests != c.undoSeen {
            c.undoSeen = undoRequests
            // After this update: undoing writes the page back.
            DispatchQueue.main.async { c.undo() }
        }
    }

    // MARK: -

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PenSheetView
        weak var canvas: SheetCanvas?
        weak var sheet: SheetBackground?
        weak var bullets: PassThroughView?
        var lines: [Line] = []
        var blocks: [PlacedBlock] = []
        /// Who owns each stroke on the canvas, in the canvas's order.
        var owners: [Owner] = []
        var history: [[Line]] = []
        var undoSeen = 0
        var lastStroke: LastStroke?
        var lastId: String?
        var toolKey = ""
        /// The ink's colors wait for a redraw (see relayout).
        var stale = false
        private var rendering = false

        struct Owner {
            let entryId: String
            let index: Int
            let key: String
        }

        init(_ parent: PenSheetView) {
            self.parent = parent
            undoSeen = parent.undoRequests
        }

        // MARK: Drawing the page

        func render() {
            guard let canvas, let sheet else { return }
            let width = canvas.bounds.width
            guard width > 0 else { return }
            blocks = InkPage.blocks(lines) { sheet.typedRows($0, width: width) }
            let colors = Dictionary(zip(lines.map(\.id), Outline.colorTypes(lines)), uniquingKeysWith: { a, _ in a })
            let byId = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var strokes: [PKStroke] = []
            owners = []
            for (n, ps) in InkPage.strokes(blocks).enumerated() {
                var tint = ps.stroke.b == true ? Theme.ui(colors[ps.entryId]?.rawValue ?? "ink") : Theme.ui(ps.stroke.c)
                // A handwritten line shows its state like a typed one: done and cancelled fade, and the drawn
                // bullet gives way to ×, > or < (drawn on the sheet).
                if let l = byId[ps.entryId], States.stateful(l.type, eventStates: parent.eventStates) {
                    if ps.stroke.b == true, [.done, .migrated, .scheduled].contains(l.state) {
                        tint = tint.withAlphaComponent(0)
                    } else if ps.stroke.b != true, l.state == .done || l.state == .cancelled {
                        tint = tint.withAlphaComponent(0.45)
                    }
                }
                let pk = Self.pkStroke(ps.stroke, color: tint, date: Date(timeIntervalSinceReferenceDate: Double(n)))
                strokes.append(pk)
                owners.append(Owner(entryId: ps.entryId, index: ps.index, key: Self.key(pk)))
            }
            rendering = true
            stale = false
            if parent.tool == .lasso {
                // A selection would stay where the old strokes were (moving it duplicated them): switching the
                // tool lets it go.
                canvas.tool = PKInkingTool(penInk)
                canvas.tool = PKLassoTool()
            }
            canvas.drawing = PKDrawing(strokes: strokes)
            canvas.undoManager?.removeAllActions()
            rendering = false
            layoutSheet()
        }

        /// The sheet again, the strokes untouched (the page is drawn again if lines moved up or down).
        func relayout() {
            guard let canvas, let sheet else { return }
            let width = canvas.bounds.width
            let after = InkPage.blocks(lines) { sheet.typedRows($0, width: width) }
            guard after.map(\.id) == blocks.map(\.id), after.map(\.top) == blocks.map(\.top) else { return render() }
            blocks = after
            stale = true
            layoutSheet()
        }

        /// The sheet behind the ink (rules and typed lines), and room below the last line to keep writing.
        func layoutSheet() {
            guard let canvas, let sheet else { return }
            let width = canvas.bounds.width
            let height = max(CGFloat(InkPage.contentEnd(blocks)) + 12 * CGFloat(inkRow), canvas.bounds.height + CGFloat(inkRow))
            canvas.contentSize = CGSize(width: width, height: height)
            sheet.frame = CGRect(x: 0, y: 0, width: width, height: height)
            sheet.show(lines: lines, blocks: blocks, eventStates: parent.eventStates, doneMark: parent.doneMark)
            layoutBullets(frame: sheet.frame)
        }

        /// Tap targets on the bullets, typed and hand-drawn: a tap moves the state on, holding opens the menu,
        /// as on a typed bullet in Type mode.
        private func layoutBullets(frame: CGRect) {
            guard let bullets else { return }
            bullets.frame = frame
            bullets.subviews.forEach { $0.removeFromSuperview() }
            let byId = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for b in blocks {
                guard let l = byId[b.id] else { continue }
                var center: CGPoint?
                if b.typed {
                    if l.type == .task || l.type == .event || l.type == .note {
                        center = CGPoint(x: SheetBackground.textX(l) - 15, y: CGFloat(b.top) + CGFloat(inkRow) / 2)
                    }
                } else if let box = InkPage.handBullet(l) {
                    center = CGPoint(x: (box.x0 + box.x1) / 2, y: b.top + (box.y0 + box.y1) / 2)
                }
                guard let center else { continue }
                let id = l.id
                let hit = PenBulletView(frame: CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44))
                hit.lineId = id
                hit.accessibilityLabel = "\(l.type.rawValue), \(l.state.rawValue)"
                hit.onTap = { [weak self] in self?.tapped(id) }
                hit.menuProvider = { [weak self] in self?.menu(for: id) }
                bullets.addSubview(hit)
            }
        }

        private func tapped(_ id: String) {
            guard let l = lines.first(where: { $0.id == id }), States.stateful(l.type, eventStates: parent.eventStates) else { return }
            act(.state(States.next(l.state)), id)
            celebrate(id)
        }

        /// The done animation (Settings), on the bullet as the sheet now draws it.
        private func celebrate(_ id: String) {
            guard let i = lines.firstIndex(where: { $0.id == id }), lines[i].state == .done || lines[i].state == .cancelled,
                let sheet
            else { return }
            let hit = bullets?.subviews.first { ($0 as? PenBulletView)?.lineId == id }
            guard let bullet = sheet.glyphs[id] ?? hit else { return }
            let root = Outline.colorTypes(lines)[i]
            let color = Theme.ui(root == .text || root == .heading ? "task" : root.rawValue)
            DoneFx.play(
                cancel: lines[i].state == .cancelled, check: parent.doneMark == "✓", bullet: bullet, mark: sheet.glyphs[id], color: color,
                host: sheet, textRect: sheet.words[id])
        }

        private func act(_ action: LineAction, _ id: String) {
            remember()
            action.apply(to: &lines, id: id, eventStates: parent.eventStates)
            parent.lines = lines
            render()
        }

        /// The bullet menu in Pen mode: type, state, signifiers (indenting and deleting belong to the pen).
        private func menu(for id: String) -> UIMenu? {
            guard let l = lines.first(where: { $0.id == id }) else { return nil }
            let types = UIMenu(options: .displayInline, children: [
                UIAction(title: S.task, state: l.type == .task ? .on : .off) { [weak self] _ in self?.act(.type(.task), id) },
                UIAction(title: S.event, state: l.type == .event ? .on : .off) { [weak self] _ in self?.act(.type(.event), id) },
                UIAction(title: S.note, state: l.type == .note ? .on : .off) { [weak self] _ in self?.act(.type(.note), id) },
            ])
            var states: [UIMenuElement] = []
            if States.stateful(l.type, eventStates: parent.eventStates) {
                states = [
                    UIAction(title: S.migrate) { [weak self] _ in self?.act(.state(.migrated), id) },
                    UIAction(title: S.schedule) { [weak self] _ in self?.act(.state(.scheduled), id) },
                ]
                if l.state != .open { states.append(UIAction(title: S.reopen) { [weak self] _ in self?.act(.state(.open), id) }) }
            }
            let signifiers = UIMenu(options: .displayInline, children: [
                UIAction(title: S.priority, state: l.priority ? .on : .off) { [weak self] _ in self?.act(.togglePriority, id) },
                UIAction(title: S.inspiration, state: l.inspiration ? .on : .off) { [weak self] _ in self?.act(.toggleInspiration, id) },
                UIAction(title: S.explore, state: l.explore ? .on : .off) { [weak self] _ in self?.act(.toggleExplore, id) },
            ])
            return UIMenu(children: [types] + (states.isEmpty ? [] : [UIMenu(options: .displayInline, children: states)]) + [signifiers])
        }

        func pkTool() -> PKTool {
            switch parent.tool {
            case .erase: return PKEraserTool(.vector)
            case .lasso: return PKLassoTool()
            case .write, .draw: return PKInkingTool(penInk, color: Theme.ui(parent.color), width: penWidth(parent.size))
            }
        }

        // MARK: What the pen did

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !rendering else { return }
            let strokes = canvasView.drawing.strokes
            if strokes.count == owners.count + 1, let last = strokes.last, parent.tool != .lasso {
                added(last)
            } else if strokes.count < owners.count {
                erased(strokes)
            } else if strokes.count == owners.count {
                moved(strokes)
            } else {
                // More than one stroke, or a copy pasted with the lasso: the page keeps what was written.
                render()
            }
        }

        /// The lasso moved strokes: they go onto the line they were dropped on (or a new line), in one step.
        private func moved(_ strokes: [PKStroke]) {
            let byKey = Dictionary(owners.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            let tops = Dictionary(blocks.map { ($0.id, $0.top) }, uniquingKeysWith: { a, _ in a })
            let byId = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var picked: [PageStroke] = []
            var pickedKeys: [String] = []
            for pk in strokes {
                guard let o = byKey[Self.key(pk)], let top = tops[o.entryId], let ink = byId[o.entryId]?.ink, o.index < ink.strokes.count,
                    let first = pk.path.first
                else { continue }
                var s = ink.strokes[o.index]
                guard s.p.count >= 2 else { continue }
                // Where PencilKit has the stroke now, against where it was: the move, applied to the stored points.
                let now = first.location.applying(pk.transform)
                let dx = Double(now.x) - s.p[0], dy = Double(now.y) - (s.p[1] + top)
                guard abs(dx) > 1 || abs(dy) > 1 else { continue }
                s.p = s.p.enumerated().map { j, v in j % 3 == 0 ? v + dx : j % 3 == 1 ? v + top + dy : v }
                picked.append(PageStroke(entryId: o.entryId, index: o.index, stroke: s))
                pickedKeys.append(o.key)
            }
            guard !picked.isEmpty else { return }
            let width = canvas?.bounds.width ?? 0
            remember()
            let result = InkPage.move(picked, in: lines) { sheet?.typedRows($0, width: width) ?? 1 }
            lines = result.lines
            lastStroke = nil
            parent.lines = lines
            let before = Dictionary(blocks.map { ($0.id, $0.top) }, uniquingKeysWith: { a, _ in a })
            let after = InkPage.blocks(lines) { sheet?.typedRows($0, width: width) ?? 1 }
            let shifted = after.contains { b in before[b.id].map { $0 != b.top } ?? false }
            guard !shifted, let target = result.entryId, let count = lines.first(where: { $0.id == target })?.ink?.strokes.count else {
                render()
                return
            }
            // Nothing above moved: the canvas keeps the strokes where they were dropped (and the lasso its
            // selection, to move them again); only who owns each stroke changes.
            var gone: [String: [Int]] = [:]
            for m in picked { gone[m.entryId, default: []].append(m.index) }
            let movedTo = Dictionary(zip(pickedKeys, pickedKeys.indices.map { count - pickedKeys.count + $0 }), uniquingKeysWith: { a, _ in a })
            owners = owners.map { o in
                if let i = movedTo[o.key] { return Owner(entryId: target, index: i, key: o.key) }
                let below = gone[o.entryId]?.filter { $0 < o.index }.count ?? 0
                return Owner(entryId: o.entryId, index: o.index - below, key: o.key)
            }
            blocks = after
            layoutSheet()
        }

        private func added(_ pk: PKStroke) {
            var p: [Double] = []
            for point in pk.path {
                let at = point.location.applying(pk.transform)
                // Stored to 0.1 pt and 2-digit pressure, like the PWA.
                p.append((Double(at.x) * 10).rounded() / 10)
                p.append((Double(at.y) * 10).rounded() / 10)
                p.append((min(1, max(0, Double(point.force))) * 100).rounded() / 100)
            }
            guard !p.isEmpty else { return }
            let kind: StrokeKind = parent.tool == .draw ? .drawing : .writing
            // The size PencilKit actually drew (larger than the tool's nominal width), so the stroke looks the
            // same when the page is drawn again from what is stored.
            let sizes = pk.path.map { Double($0.size.width) }.sorted()
            let median = sizes.isEmpty ? parent.size : sizes[sizes.count / 2]
            let drawn = (median * 10).rounded() / 10
            if !sizes.isEmpty, let tool = canvas?.tool as? PKInkingTool, tool.width > 0 {
                // The next strokes come out at the size asked for (this one is stored as it was drawn).
                PenCalibration.ratio = median / Double(tool.width)
            }
            let stroke = Stroke(k: kind, c: parent.color, p: p, pen: true, s: drawn == storedDefaultSize ? nil : drawn)
            let box = stroke.box
            let now = Date().timeIntervalSinceReferenceDate
            let row = max(0, PenRules.strokeRow(box, kind: kind, last: lastStroke, now: now))
            let recentId = lastStroke.map { now - $0.at < 4 } == true ? lastId : nil
            let placement = PenRules.place(blocks, contentEnd: InkPage.contentEnd(blocks), stroke: stroke, row: row, lastId: recentId)
            remember()
            let result = InkPage.add(stroke, placement: placement, to: lines)
            lines = result.lines
            lastStroke = LastStroke(row: row, at: now, box: box)
            lastId = result.entryId
            let before = Dictionary(blocks.map { ($0.id, $0.top) }, uniquingKeysWith: { a, _ in a })
            let width = canvas?.bounds.width ?? 0
            let after = InkPage.blocks(lines) { sheet?.typedRows($0, width: width) ?? 1 }
            // Nothing above moved: the canvas already shows the stroke where it belongs; just note its owner.
            let moved = after.contains { b in before[b.id].map { $0 != b.top } ?? false }
            if moved {
                render()
            } else {
                blocks = after
                let index = (lines.first { $0.id == result.entryId }?.ink?.strokes.count ?? 1) - 1
                owners.append(Owner(entryId: result.entryId, index: index, key: Self.key(pk)))
                layoutSheet()
            }
            parent.lines = lines
        }

        private func erased(_ remaining: [PKStroke]) {
            let keys = Set(remaining.map(Self.key))
            var hits: [String: Set<Int>] = [:]
            for o in owners where !keys.contains(o.key) {
                hits[o.entryId, default: []].insert(o.index)
            }
            if !hits.isEmpty {
                remember()
                lines = InkPage.erase(hits, from: lines)
                parent.lines = lines
            }
            lastStroke = nil
            render()
        }

        private func remember() {
            history.append(lines)
            if history.count > 100 { history.removeFirst() }
            parent.onCanUndo(true)
        }

        func undo() {
            guard let previous = history.popLast() else { return }
            lines = previous
            lastStroke = nil
            parent.lines = lines
            parent.onCanUndo(!history.isEmpty)
            render()
        }

        // MARK: Strokes between PencilKit and the app's format

        static func key(_ pk: PKStroke) -> String {
            "\(pk.path.creationDate.timeIntervalSinceReferenceDate)/\(pk.path.count)"
        }

        static func pkStroke(_ s: Stroke, color: UIColor, date: Date) -> PKStroke {
            let width = CGFloat(s.s ?? storedDefaultSize)
            var points: [PKStrokePoint] = []
            var i = 0
            var t: TimeInterval = 0
            while i + 2 < s.p.count {
                points.append(
                    PKStrokePoint(
                        location: CGPoint(x: s.p[i], y: s.p[i + 1]), timeOffset: t, size: CGSize(width: width, height: width),
                        opacity: 1, force: CGFloat(max(0.2, s.p[i + 2])), azimuth: 0, altitude: .pi / 2))
                i += 3
                t += 0.008
            }
            return PKStroke(ink: PKInk(penInk, color: color), path: PKStrokePath(controlPoints: points, creationDate: date))
        }
    }
}

/// A canvas that tells when its width changes (the page is laid out again).
final class SheetCanvas: PKCanvasView {
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            onWidthChange?()
        }
    }
}

/// What sits under the ink: the rules (1 pt, every 40) and the typed lines, each on whole ruled rows.
final class SheetBackground: UIView {
    var showsRules = true {
        didSet { updateRules() }
    }
    private var labels: [UIView] = []
    /// Each line's bullet as drawn on the sheet (the typed glyph, or ×, > or < over a drawn bullet), and where its
    /// words are: what the done animation plays on.
    private(set) var glyphs: [String: UIView] = [:]
    private(set) var words: [String: CGRect] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        updateRules()
        // The rules are an image, so they are redrawn in the new color when light/dark changes.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SheetBackground, _: UITraitCollection) in
            view.updateRules()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func updateRules() {
        guard showsRules else {
            backgroundColor = .clear
            return
        }
        let row = CGFloat(inkRow)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: row))
        let rule = Theme.ui("rule").resolvedColor(with: traitCollection)
        let image = renderer.image { ctx in
            rule.setFill()
            ctx.fill(CGRect(x: 0, y: row - 1, width: 8, height: 1))
        }
        backgroundColor = UIColor(patternImage: image)
    }

    static let font = UIFont(name: "AvenirNext-Regular", size: 17) ?? .systemFont(ofSize: 17)
    static let headingFont = UIFont(name: "AvenirNext-Bold", size: 21) ?? .boldSystemFont(ofSize: 21)

    static func textX(_ l: Line) -> CGFloat { CGFloat(penTextX) + CGFloat(l.indent) * 26 }

    func typedRows(_ l: Line, width: CGFloat) -> Int {
        let text = Self.attributed(l.text.isEmpty ? " " : l.text, heading: l.type == .heading, color: .label, faded: false, struck: false)
        let w = max(40, width - Self.textX(l) - 16)
        let h = text.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).height
        return max(1, Int((h / CGFloat(inkRow)).rounded(.up)))
    }

    static func attributed(_ text: String, heading: Bool, color: UIColor, faded: Bool, struck: Bool) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = CGFloat(inkRow)
        p.maximumLineHeight = CGFloat(inkRow)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: heading ? headingFont : font, .paragraphStyle: p, .foregroundColor: faded ? Theme.ui("muted") : color,
            .baselineOffset: 6,
        ]
        if struck { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: text, attributes: attrs)
    }

    func show(lines: [Line], blocks: [PlacedBlock], eventStates: Bool, doneMark: String) {
        labels.forEach { $0.removeFromSuperview() }
        labels = []
        glyphs = [:]
        words = [:]
        let byId = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let colors = Dictionary(zip(lines.map(\.id), Outline.colorTypes(lines)), uniquingKeysWith: { a, _ in a })
        for b in blocks where !b.typed {
            guard let l = byId[b.id], States.stateful(l.type, eventStates: eventStates), let box = InkPage.handBullet(l) else { continue }
            let cy = CGFloat(b.top + (box.y0 + box.y1) / 2)
            if let w = InkPage.handWords(l) { words[l.id] = CGRect(x: w.x0, y: Double(cy) - inkRow / 2, width: w.x1 - w.x0, height: inkRow) }
            let tint = Theme.ui(colors[l.id]?.rawValue ?? "text")
            if [.done, .migrated, .scheduled].contains(l.state) {
                let mark = UILabel()
                mark.text = States.glyph(l.type, l.state, eventStates: eventStates, doneMark: doneMark)
                mark.font = UIFont(name: "AvenirNext-Bold", size: 21) ?? .boldSystemFont(ofSize: 21)
                mark.textColor = tint
                mark.sizeToFit()
                mark.center = CGPoint(x: CGFloat((box.x0 + box.x1) / 2), y: cy - 1)
                addSubview(mark)
                labels.append(mark)
                glyphs[l.id] = mark
            } else if l.state == .cancelled, let words = InkPage.handWords(l) {
                let strike = UIView(frame: CGRect(x: words.x0, y: Double(cy) - 0.75, width: words.x1 - words.x0, height: 1.5))
                strike.backgroundColor = Theme.ui("muted")
                addSubview(strike)
                labels.append(strike)
            }
        }
        for b in blocks where b.typed {
            guard let l = byId[b.id] else { continue }
            let x = Self.textX(l)
            let stateful = States.stateful(l.type, eventStates: eventStates)
            let tint = Theme.ui(colors[l.id]?.rawValue ?? "text")
            let text = UILabel(frame: CGRect(x: x, y: CGFloat(b.top), width: max(40, bounds.width - x - 16), height: CGFloat(b.height)))
            text.numberOfLines = 0
            text.attributedText = Self.attributed(
                l.text, heading: l.type == .heading, color: Theme.ui("text"), faded: stateful && l.state != .open,
                struck: stateful && l.state == .cancelled)
            addSubview(text)
            labels.append(text)
            if let size = text.attributedText?.size() {
                words[l.id] = CGRect(x: x, y: CGFloat(b.top), width: min(size.width, text.bounds.width), height: CGFloat(inkRow))
            }
            let glyph = States.glyph(l.type, l.state, eventStates: eventStates, doneMark: doneMark)
            if !glyph.isEmpty {
                let bullet = UILabel(frame: CGRect(x: x - 26, y: CGFloat(b.top), width: 22, height: CGFloat(inkRow)))
                bullet.textAlignment = .center
                bullet.attributedText = Self.attributed(glyph, heading: false, color: tint, faded: false, struck: false)
                addSubview(bullet)
                labels.append(bullet)
                glyphs[l.id] = bullet
            }
        }
    }
}

/// The floating pen toolbar: Write, Draw, Eraser; sizes; colors (ink and the app's three); Undo.
struct PenToolbar: View {
    @Binding var tool: PenTool
    @Binding var color: String
    @Binding var size: Double
    let canUndo: Bool
    let onUndo: () -> Void
    /// Write or Draw, whichever was last: a size or color picked under the eraser or lasso goes back to it.
    @State private var lastInking: PenTool = .write

    /// Sizes and colors belong to Write and Draw; under the eraser or lasso none is shown as chosen (they
    /// come back as they were).
    private var inking: Bool { tool == .write || tool == .draw }

    var body: some View {
        HStack(spacing: 4) {
            toolButton(.write, icon: "pencil.tip", label: S.write)
            toolButton(.draw, icon: "scribble", label: S.draw)
            toolButton(.erase, icon: "eraser", label: S.eraser)
            toolButton(.lasso, icon: "lasso", label: S.lasso)
            Divider().frame(height: 24)
            ForEach(Array(penSizes.enumerated()), id: \.offset) { i, s in
                Button {
                    size = s
                    if !inking { tool = lastInking }
                } label: {
                    Capsule()
                        .fill(Theme.text)
                        .frame(width: 18, height: CGFloat(s))
                        .frame(width: 36, height: 36)
                        .background(inking && size == s ? Theme.rule : Color.clear, in: Circle())
                        .contentShape(Circle())  // the whole circle takes the tap, not just the thin line
                }
                .accessibilityLabel(S.sizes[i])
            }
            Divider().frame(height: 24)
            ForEach(["ink", "task", "event", "note"], id: \.self) { c in
                Button {
                    color = c
                    if !inking { tool = lastInking }
                } label: {
                    Circle()
                        .fill(Color(uiColor: Theme.ui(c)))
                        .frame(width: 22, height: 22)
                        .padding(3)
                        .overlay(Circle().stroke(Theme.text, lineWidth: inking && color == c ? 1.5 : 0))
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .accessibilityLabel(S.colorNames[c] ?? c)
            }
            Divider().frame(height: 24)
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .disabled(!canUndo)
            .accessibilityLabel(S.undo)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassBackground(in: Capsule(), interactive: true, clear: true)
        .onChange(of: tool) { if inking { lastInking = tool } }
        .onAppear { if inking { lastInking = tool } }
    }

    private func toolButton(_ t: PenTool, icon: String, label: String) -> some View {
        Button {
            tool = t
        } label: {
            Image(systemName: icon)
                .frame(width: 40, height: 40)
                .background(tool == t ? Theme.rule : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

/// A layer whose own area lets touches through to the canvas; only its subviews (the bullets) take them.
final class PassThroughView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        subviews.contains { !$0.isHidden && $0.frame.contains(point) }
    }
}

/// A bullet on the ruled sheet: tap and hold, like a typed bullet in Type mode.
final class PenBulletView: UIView, UIContextMenuInteractionDelegate {
    var lineId = ""
    var onTap: (() -> Void)?
    var menuProvider: (() -> UIMenu?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        // The finger: a tap of the pen is writing (a dot), never a state change.
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(tap)
        addInteraction(UIContextMenuInteraction(delegate: self))
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func tapped() { onTap?() }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menu = menuProvider?() else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}
