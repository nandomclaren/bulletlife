// The page editor of Type mode (phase N1): one text view for the whole page, so selection, Scribble, dictation
// and the keyboard work across lines as in a notes app. Each line of the page is a paragraph; bullets and
// chevrons are drawn in the margin. Typing inside a line is left to UIKit; whatever changes the structure
// (Enter, Backspace at a line start, deleting across lines, pasting lines, Tab, a rapid-logging prefix) is
// done on the line model by BulletLifeCore's PageEdit, as in the PWA, and the text is laid out again.
import BulletLifeCore
import SwiftUI
import UIKit

struct PageEditorView: UIViewRepresentable {
    @Binding var lines: [Line]
    var eventStates: Bool
    var doneMark: String
    /// Embedded in a page that scrolls (a Month day, Month tasks, a Year month): no scrolling of its own, as tall
    /// as its text and at least `minHeight`; plain text starts at the margin (no bullet space).
    var embedded = false
    var minHeight: CGFloat = 0
    /// Month day rows (CLAUDE.md 3.6): a phrase that doesn't fit on one line shrinks down to 85% (never below
    /// 14 pt) before it wraps; it is never cut.
    var fitOneLine = false
    /// An entry to scroll to and mark briefly (opened from Open items).
    var highlight: String? = nil
    /// Room for a header floating over the page (the text scrolls under it).
    var topInset: CGFloat = 0
    /// A page to consult (the second of two pages): the text can be selected, not edited; a bullet still
    /// answers a tap and a hold, one entry at a time.
    var readOnly = false
    /// The lines selected (with collapsed children), for the page menu's Export, Copy As and Share.
    var onSelection: ([Line]) -> Void = { _ in }
    var onAction: (LineAction, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EditorTextView {
        let view = EditorTextView(usingTextLayoutManager: false)
        let c = context.coordinator
        view.coordinator = c
        view.delegate = c
        view.backgroundColor = .clear
        // Offers the system's Format menu (Bold, Italic), which writes Markdown marks (EditorTextView).
        view.allowsEditingTextAttributes = true
        view.isEditable = !readOnly
        if embedded {
            view.isScrollEnabled = false
            view.clipsToBounds = false  // a top-level chevron sits just left of the text
            view.textContainerInset = UIEdgeInsets(top: 0, left: EditorLayout.inset(embedded: true), bottom: 0, right: 0)
        } else {
            view.alwaysBounceVertical = true
            view.keyboardDismissMode = .interactive
            view.textContainerInset = UIEdgeInsets(top: 8, left: EditorLayout.inset(embedded: false), bottom: 240, right: 8)
        }
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.textContainer.lineFragmentPadding = 0
        view.autocapitalizationType = .sentences
        view.smartDashesType = .no  // "- " and "o. " are rapid-logging prefixes
        view.smartQuotesType = .default
        c.textView = view
        c.lines = lines
        c.erased = InkPage.erasedInType(lines)
        c.rebuild(caret: nil)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EditorTextView, context: Context) -> CGSize? {
        guard embedded, let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(minHeight, ceil(fit.height), ceil(context.coordinator.inkBottom + 8)))
    }

    func updateUIView(_ view: EditorTextView, context: Context) {
        let c = context.coordinator
        view.isEditable = !readOnly
        let restyle = c.parent.eventStates != eventStates || c.parent.doneMark != doneMark
        c.parent = self
        if c.lines != lines {
            // Another page, a transcription, or a change from the bullet menu: lay the page out again. The
            // keyboard's own undo steps would no longer match the text, so Undo starts afresh.
            let samePage = Set(c.lines.map(\.id)).intersection(lines.map(\.id)).count > 0
            c.lines = lines
            if !samePage { c.erased = InkPage.erasedInType(lines) }
            c.undo.removeAllActions()
            c.rebuild(caret: samePage ? c.currentCaret() : nil)
        } else if restyle {
            c.rebuild(caret: c.currentCaret())
        }
        if !embedded { setTopInset(view, topInset) }
        // Cleared: the same entry can be marked again next time.
        if highlight == nil { c.flashed = nil }
        if let highlight, highlight != c.flashed {
            c.flashed = highlight
            // After the page is laid out (a page just opened, or one beside another, may not be yet).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { c.flash(highlight) }
        }
    }

    // MARK: -

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PageEditorView
        weak var textView: EditorTextView?
        /// The page's lines (all of them); `visible` maps each paragraph to its line (collapsed children are
        /// not in the text).
        var lines: [Line] = []
        var visible: [Int] = []
        /// Handwritten lines whose text was deleted in Type mode, as the page opened: left out of Type mode
        /// (they stay in Pen mode, with their ink).
        var erased: Set<String> = []
        let undo = UndoManager()
        private var bullets: [BulletView] = []
        /// The lowest drawing's bottom, in the text view: the page (or an embedded editor) is at least that tall.
        var inkBottom: CGFloat = 0
        private var chevrons: [UIButton] = []
        /// Text that came in several characters at once (Scribble, dictation): its prefix is read after a pause.
        private var pendingPrefix: (id: String, timer: Timer)?

        init(_ parent: PageEditorView) {
            self.parent = parent
        }

        // MARK: Text from the model

        /// Lays the whole page out from the lines and puts the caret back.
        func rebuild(caret: Caret?) {
            guard let view = textView else { return }
            if lines.isEmpty { lines = [Line()] }
            let hidden = Outline.hidden(lines)
            visible = lines.indices.filter { !hidden[$0] && !erased.contains(lines[$0].id) }
            if visible.isEmpty {
                lines.append(Line())
                visible = [lines.count - 1]
            }
            let text = NSMutableAttributedString()
            for (k, i) in visible.enumerated() {
                let l = lines[i]
                text.append(NSAttributedString(string: l.text + (k < visible.count - 1 ? "\n" : ""), attributes: attributes(l)))
            }
            view.attributedText = text
            if let caret { select(caret) }
            updateTyping()
            layoutDecor()
        }

        func attributes(_ l: Line) -> [NSAttributedString.Key: Any] {
            let stateful = States.stateful(l.type, eventStates: parent.eventStates)
            let faded = stateful && l.state != .open
            let style = NSMutableParagraphStyle()
            let indent = textIndent(l)
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            // Embedded (Month, Year): the line is as tall as the normal text, so a shrunk phrase keeps its baseline
            // level with the day's number beside it.
            style.minimumLineHeight = l.type == .heading ? 32 : parent.embedded ? EditorLayout.font.lineHeight : 27
            style.paragraphSpacing = 5
            // Ink shown in the line (a drawing, or handwriting not transcribed yet) sits above its text.
            // Handwriting not transcribed yet sits above its text; a drawing floats over the page, taking no room
            // (it starts at its line until it is moved).
            if InkPreview.kind(l) == .writing, let f = previewFrame(l) { style.paragraphSpacingBefore = CGFloat(f.height) + 6 }
            var a: [NSAttributedString.Key: Any] = [
                .font: l.type == .heading ? EditorLayout.headingFont : EditorLayout.font,
                .foregroundColor: faded ? Theme.ui("muted") : Theme.ui("text"),
                .paragraphStyle: style,
            ]
            if stateful && l.state == .cancelled { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return a
        }

        /// Where a line's text starts: after the bullet's room (embedded pages start plain text at the margin).
        func textIndent(_ l: Line) -> CGFloat {
            let bulletless = l.type == .text || l.type == .heading
            return parent.embedded && bulletless ? EditorLayout.bulletX(l.indent) : EditorLayout.textX(l.indent)
        }

        /// The ink a line shows in Type mode, sized for the page's width.
        func previewFrame(_ l: Line) -> (width: Double, height: Double, x: Double)? {
            guard l.ink != nil else { return nil }
            let width = (textView?.bounds.width ?? 0) > 0 ? textView!.bounds.width : 600
            let inset = textView.map { $0.textContainerInset.left + $0.textContainerInset.right } ?? 32
            return InkPreview.frame(l, maxWidth: Double(width - inset - textIndent(l) - 8))
        }

        // MARK: Due dates (CLAUDE.md 3.7)

        private var dateOrder: DateOrder { DateOrder(rawValue: UserDefaults.standard.string(forKey: "dateOrder") ?? "") ?? .dmy }

        func resolveDue(in text: String, upTo: Int) -> (text: String, shift: Int)? {
            Due.resolve(text, today: Dates.today(), order: dateOrder, firstDay: Prefs.firstDay, upTo: upTo)
        }

        private var pills: [DuePillView] = []
        private var sortButtons: [UIButton] = []

        private func pill(_ n: Int) -> DuePillView {
            if n < pills.count { return pills[n] }
            let v = DuePillView()
            textView?.addSubview(v)
            pills.append(v)
            return v
        }

        private func sortButton(_ n: Int) -> UIButton {
            if n < sortButtons.count { return sortButtons[n] }
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: "arrow.up.arrow.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)), for: .normal)
            b.setTitle(" " + S.sortByDate, for: .normal)
            b.titleLabel?.font = UIFont(name: "AvenirNext-Medium", size: 12) ?? .systemFont(ofSize: 12)
            b.tintColor = Theme.ui("muted")
            b.addTarget(self, action: #selector(sortTapped(_:)), for: .touchUpInside)
            textView?.addSubview(b)
            sortButtons.append(b)
            return b
        }

        /// Sorts a list by date, only because the user asked (the app never reorders by itself).
        @objc private func sortTapped(_ sender: UIButton) {
            guard !parent.readOnly else { return }
            guard let id = sender.accessibilityIdentifier, let i = lines.firstIndex(where: { $0.id == id }),
                let run = Due.runs(lines).first(where: { $0.items.first == i })
            else { return }
            apply(Edited(lines: Due.sort(lines, run), caret: currentCaret() ?? Caret(index: i, offset: 0)))
        }

        /// The pill was tapped: a calendar to choose another date, written back into the same token.
        func pickDate(lineId: String, tokenStart: Int, from source: UIView) {
            guard !parent.readOnly else { return }
            guard let i = lines.firstIndex(where: { $0.id == lineId }),
                let token = Due.tokens(lines[i].text).first(where: { $0.range.location == tokenStart }),
                let presenter = textView?.window?.rootViewController.map(Self.topmost)
            else { return }
            let picker = DatePickerController(date: Dates.fromIso(token.iso)) { [weak self] date in
                guard let self, let j = self.lines.firstIndex(where: { $0.id == lineId }) else { return }
                var next = self.lines
                next[j].text = (next[j].text as NSString).replacingCharacters(in: token.range, with: "due:\(Dates.toIso(date))")
                self.apply(Edited(lines: next, caret: self.currentCaret() ?? Caret(index: j, offset: 0)))
            }
            picker.modalPresentationStyle = .popover
            picker.popoverPresentationController?.sourceView = source
            picker.popoverPresentationController?.sourceRect = source.bounds
            picker.popoverPresentationController?.delegate = picker
            presenter.present(picker, animated: true)
        }

        static func topmost(_ vc: UIViewController) -> UIViewController {
            var top = vc
            while let next = top.presentedViewController { top = next }
            return top
        }

        // MARK: Drawings in Type mode

        /// The drawing selected (tap it): it can then be sized, moved sideways or deleted.
        var selectedDrawing: String?
        private var inkViews: [InkPreviewView] = []

        func tappedDrawing(_ id: String) {
            selectedDrawing = selectedDrawing == id ? nil : id
            layoutDecor()
        }

        /// A drawing's size and place in Type mode (its strokes never change). It floats over the page, free of
        /// the lines: it may cover text, and it can go below the last line. `y` from the top of the text.
        func setDrawingView(_ id: String, width: Double, x: Double, y: Double?) {
            guard let i = lines.firstIndex(where: { $0.id == id }), lines[i].ink != nil else { return }
            var next = lines
            next[i].ink?.view = Ink.View(w: width.rounded(), x: max(0, x).rounded(), y: y.map { max(0, $0).rounded() })
            apply(Edited(lines: next, caret: currentCaret() ?? Caret(index: i, offset: 0)))
        }

        /// Deletes a drawing (the × of the selected one, Delete, or Backspace on its empty line). Handwriting is
        /// never deleted from Type mode.
        func deleteDrawing(_ id: String) {
            guard let i = lines.firstIndex(where: { $0.id == id }), InkPreview.kind(lines[i]) == .drawing else { return }
            var next = lines
            next[i].ink = nil
            selectedDrawing = nil
            apply(Edited(lines: next, caret: Caret(index: i, offset: 0)))
        }

        private func inkView(_ n: Int) -> InkPreviewView {
            if n < inkViews.count { return inkViews[n] }
            let v = InkPreviewView()
            textView?.addSubview(v)
            inkViews.append(v)
            return v
        }

        // MARK: Places in the text

        /// Where each paragraph starts (UTF-16), from the lines (the text always matches them).
        private func starts() -> [Int] {
            var out: [Int] = []
            var at = 0
            for i in visible {
                out.append(at)
                at += (lines[i].text as NSString).length + 1
            }
            return out
        }

        /// A text location as a caret on a line.
        func caret(at location: Int) -> Caret {
            let s = starts()
            var k = s.count - 1
            while k > 0 && s[k] > location { k -= 1 }
            let i = visible[max(0, k)]
            return Caret(index: i, offset: min(max(0, location - s[max(0, k)]), (lines[i].text as NSString).length))
        }

        func location(of caret: Caret) -> Int {
            let s = starts()
            // A hidden line (inside a collapsed parent): the nearest visible line above.
            let k = visible.lastIndex { $0 <= caret.index } ?? 0
            let len = (lines[visible[k]].text as NSString).length
            return s[k] + (visible[k] == caret.index ? min(caret.offset, len) : len)
        }

        func currentCaret() -> Caret? {
            guard let view = textView, !lines.isEmpty else { return nil }
            return caret(at: view.selectedRange.location)
        }

        func select(_ caret: Caret) {
            textView?.selectedRange = NSRange(location: location(of: caret), length: 0)
        }

        // MARK: Structural edits

        /// Applies an edit to the model: the page before it becomes an Undo step.
        private func apply(_ edited: Edited) {
            remember()
            lines = edited.lines
            rebuild(caret: edited.caret)
            push()
        }

        private func remember() {
            let before = lines
            let caret = currentCaret()
            undo.registerUndo(withTarget: self) { c in c.restore(before, caret: caret) }
        }

        private func restore(_ saved: [Line], caret: Caret?) {
            remember()  // registered while undoing: becomes the redo step
            lines = saved
            rebuild(caret: caret)
            push()
        }

        private func push() {
            parent.lines = lines
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let start = caret(at: range.location)
            let end = caret(at: range.location + range.length)
            let multi = start.index != end.index
            // Return, or text with line breaks (paste, the Scribble palette's return key).
            if text.contains("\n") || text.contains("\r") {
                var base = lines
                var at = start
                // A due date finished by Return is stored as a date too.
                if !multi && range.length == 0, let r = resolveDue(in: base[at.index].text, upTo: at.offset) {
                    base[at.index].text = r.text
                    at.offset += r.shift
                }
                var edited = multi || range.length > 0 ? PageEdit.deleteRange(lines, from: start, to: end) : Edited(lines: base, caret: at)
                edited = text == "\n" ? PageEdit.enter(edited.lines, at: edited.caret) : PageEdit.insertText(edited.lines, at: edited.caret, text)
                apply(edited)
                return false
            }
            // A space at the very start of a line indents it (the iPhone keyboard has no Tab).
            if text == " " && range.length == 0 && start.offset == 0, let shifted = PageEdit.shift(lines, from: start.index, to: start.index, delta: 1) {
                apply(Edited(lines: shifted, caret: start))
                return false
            }
            // Anything spanning several lines is done on the model (handwriting is never deleted from here).
            if multi {
                var edited = PageEdit.deleteRange(lines, from: start, to: end)
                if !text.isEmpty { edited = PageEdit.insertText(edited.lines, at: edited.caret, text) }
                apply(edited)
                return false
            }
            // Backspace with the caret at a line start that came as a deleted line break (some keyboards don't
            // call deleteBackward): the same steps as Backspace at a line start.
            if text.isEmpty && range.length == 1 && (textView.text as NSString).substring(with: range) == "\n"
                && textView.selectedRange == NSRange(location: range.location + 1, length: 0)
            {
                let at = Caret(index: end.index, offset: 0)
                if let edited = PageEdit.backspaceAtStart(lines, at: at) { apply(edited) }
                return false
            }
            if (text as NSString).length > 1 { bulk = true }
            return true
        }

        private var bulk = false

        /// Backspace with the caret at a line start (called by the text view, also at the very top, where UIKit
        /// has nothing to delete). Returns whether it was handled.
        func backspaceAtLineStart() -> Bool {
            guard !parent.readOnly else { return true }
            if let id = selectedDrawing {
                deleteDrawing(id)
                return true
            }
            guard let view = textView, view.selectedRange.length == 0 else { return false }
            let at = caret(at: view.selectedRange.location)
            guard at.offset == 0 else { return false }
            // An empty line holding only a drawing: the first Backspace removes the drawing, like a picture.
            if lines[at.index].text.isEmpty && InkPreview.kind(lines[at.index]) == .drawing {
                deleteDrawing(lines[at.index].id)
                return true
            }
            if let edited = PageEdit.backspaceAtStart(lines, at: at) { apply(edited) }
            return true
        }

        func shiftSelection(_ delta: Int) {
            guard !parent.readOnly else { return }
            guard let view = textView else { return }
            let a = caret(at: view.selectedRange.location)
            let b = caret(at: view.selectedRange.location + view.selectedRange.length)
            guard let shifted = PageEdit.shift(lines, from: a.index, to: b.index, delta: delta) else { return }
            let range = view.selectedRange
            apply(Edited(lines: shifted, caret: a))
            // The text is the same (bar a renumbered list): keep the selection.
            if range.location + range.length <= (view.text as NSString).length { view.selectedRange = range }
        }

        /// ⌘↩: the line's state goes on to the next (open → done → cancelled → open).
        func cycleState() {
            guard !parent.readOnly else { return }
            guard let at = currentCaret(), States.stateful(lines[at.index].type, eventStates: parent.eventStates) else { return }
            var next = lines
            next[at.index].state = States.next(next[at.index].state)
            apply(Edited(lines: next, caret: at))
            celebrate(lines[at.index].id)
        }

        // MARK: Typing inside a line

        func textViewDidChange(_ textView: UITextView) {
            let paragraphs = textView.text.components(separatedBy: "\n")
            guard paragraphs.count == visible.count else {
                // Should not happen (line breaks go through the model); keep the model as the truth.
                rebuild(caret: currentCaret())
                return
            }
            for (k, i) in visible.enumerated() where lines[i].text != paragraphs[k] { lines[i].text = paragraphs[k] }
            if let at = currentCaret() {
                if bulk {
                    // Scribble writes a word at once, then corrects it in place: the prefix waits for a pause.
                    schedulePrefix(lines[at.index].id)
                } else if readTypedPrefix(at) {
                    bulk = false
                    return
                } else if at.offset > 0, let last = (lines[at.index].text as NSString).substring(to: at.offset).last, last.isWhitespace || ",;!?)".contains(last),
                    let r = resolveDue(in: lines[at.index].text, upTo: at.offset - 1)
                {
                    // "due:tomorrow " just finished: stored as the date, so it never drifts (CLAUDE.md 3.7).
                    var next = lines
                    next[at.index].text = r.text
                    bulk = false
                    apply(Edited(lines: next, caret: Caret(index: at.index, offset: at.offset + r.shift)))
                    return
                }
            }
            bulk = false
            push()
            layoutDecor()
        }

        /// ". ", "o. ", "- ", "# ", "* " just typed at the start of a line (CLAUDE.md 3.4).
        private func readTypedPrefix(_ at: Caret) -> Bool {
            let line = lines[at.index]
            guard at.offset <= 5, let m = Rapid.match((line.text as NSString).substring(to: at.offset)), m.length == at.offset else { return false }
            // A lone "* " marks priority only on a line that already has a bullet.
            if m.type == .text && (line.type == .text || line.type == .heading) { return false }
            var next = lines
            convert(&next[at.index], m)
            apply(Edited(lines: next, caret: Caret(index: at.index, offset: 0)))
            return true
        }

        private func convert(_ l: inout Line, _ m: PrefixMatch) {
            l.text = (l.text as NSString).substring(from: min(m.length, (l.text as NSString).length))
            if m.type != .text {
                l.type = m.type
                l.state = .open
            }
            l.priority = m.priority || l.priority
        }

        private func schedulePrefix(_ id: String, after delay: TimeInterval = 1.5) {
            pendingPrefix?.timer.invalidate()
            let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.applyPendingPrefix() }
            pendingPrefix = (id, timer)
        }

        private func applyPendingPrefix() {
            guard let pending = pendingPrefix else { return }
            // Scribble may still hold the text as provisional (marked): wait for it, as an edit now would break it.
            if textView?.markedTextRange != nil {
                schedulePrefix(pending.id, after: 0.5)
                return
            }
            pendingPrefix = nil
            pending.timer.invalidate()
            guard let i = lines.firstIndex(where: { $0.id == pending.id }), let m = Rapid.leading(lines[i].text) else { return }
            if m.type == .text && (lines[i].type == .text || lines[i].type == .heading) { return }
            let at = currentCaret()
            var next = lines
            convert(&next[i], m)
            let caret = at.map { $0.index == i ? Caret(index: i, offset: max(0, $0.offset - m.length)) : $0 }
            apply(Edited(lines: next, caret: caret ?? Caret(index: i, offset: 0)))
        }

        // MARK: Selection and highlight

        /// The selected lines as the model has them: every line the selection touches, with the children of
        /// collapsed ones (collapsing never changes what is exported or copied, CLAUDE.md 7).
        func selectedLines() -> [Line] {
            guard let view = textView, view.selectedRange.length > 0 else { return [] }
            let a = caret(at: view.selectedRange.location)
            let b = caret(at: view.selectedRange.location + view.selectedRange.length)
            let end = Outline.subtreeEnd(lines, b.index)
            let last = lines[b.index].collapsed ? end : b.index + 1
            return Array(lines[a.index..<max(last, a.index + 1)])
        }

        /// Pastes entries (copied from the app, or its Markdown) as entries, at the selection.
        func paste(_ pasted: [Line]) {
            guard !parent.readOnly else { return }
            guard let view = textView else { return }
            let a = caret(at: view.selectedRange.location)
            let b = caret(at: view.selectedRange.location + view.selectedRange.length)
            let cleared = view.selectedRange.length > 0 ? PageEdit.deleteRange(lines, from: a, to: b) : Edited(lines: lines, caret: a)
            apply(PageEdit.paste(cleared.lines, at: cleared.caret, pasted))
        }

        var flashed: String?

        /// Scrolls to an entry and marks it for a moment.
        func flash(_ id: String) {
            guard let view = textView, let i = lines.firstIndex(where: { $0.id == id }), visible.contains(i) else { return }
            let start = location(of: Caret(index: i, offset: 0))
            let range = NSRange(location: start, length: (lines[i].text as NSString).length)
            guard range.location + range.length <= view.textStorage.length else { return }
            view.layoutIfNeeded()
            view.layoutManager.ensureLayout(for: view.textContainer)
            view.scrollRangeToVisible(range)
            let mark = Theme.ui("task").withAlphaComponent(0.16)
            view.textStorage.addAttribute(.backgroundColor, value: mark, range: range)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak view] in
                guard let view, range.location + range.length <= view.textStorage.length else { return }
                view.textStorage.removeAttribute(.backgroundColor, range: range)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.onSelection(selectedLines())
            if selectedDrawing != nil {
                selectedDrawing = nil
                layoutDecor()
            }
            // Leaving a line written by Scribble reads its prefix now.
            if let pendingId = pendingPrefix?.id, let at = currentCaret(), lines[at.index].id != pendingId { applyPendingPrefix() }
            refreshActiveSpans()
            updateTyping()
        }

        /// The caret takes the color of the line's bullet (CLAUDE.md 8); new text the line's look.
        private func updateTyping() {
            guard let view = textView, let at = currentCaret() else { return }
            let color = Outline.colorTypes(lines)[at.index]
            view.tintColor = color == .text || color == .heading ? Theme.ui("text") : Theme.ui(color.rawValue)
            var typing = attributes(lines[at.index])
            if let font = fitted[lines[at.index].id] { typing[.font] = font }
            view.typingAttributes = typing
        }

        // MARK: Bullets and chevrons in the margin

        /// Month day rows: each plain line shrinks to fit one line, down to 85% (at least 14 pt), then wraps.
        private func fitFonts() {
            guard parent.fitOneLine, let view = textView, view.bounds.width > 0 else { return }
            let storage = view.textStorage
            let width = view.bounds.width - view.textContainerInset.left - view.textContainerInset.right
            var at = 0
            for i in visible {
                let l = lines[i]
                let len = (l.text as NSString).length
                defer { at += len + 1 }
                guard l.type == .text, len > 0, at + len <= storage.length else { continue }
                let base = EditorLayout.font
                let needed = (l.text as NSString).size(withAttributes: [.font: base]).width
                let available = width - EditorLayout.bulletX(l.indent)
                let size = needed <= available ? base.pointSize : max(14, base.pointSize * 0.85, (base.pointSize * available / needed * 10).rounded(.down) / 10)
                let font = base.withSize(size)
                fitted[l.id] = font
                // The whole line takes one size (text just typed comes in at the normal size).
                let range = NSRange(location: at, length: len)
                var uniform = true
                storage.enumerateAttribute(.font, in: range) { value, _, stop in
                    if let f = value as? UIFont, f.pointSize >= 1, f.pointSize != size {
                        uniform = false
                        stop.pointee = true
                    }
                }
                if !uniform {
                    // Each run keeps its bold or italic; hidden markers stay hidden.
                    storage.enumerateAttribute(.font, in: range) { value, r, _ in
                        guard let f = value as? UIFont, f.pointSize >= 1 else { return }
                        storage.addAttribute(.font, value: UIFont(descriptor: f.fontDescriptor, size: size), range: r)
                    }
                }
            }
            // What is typed next comes in at the line's size.
            if let at = currentCaret(), let font = fitted[lines[at.index].id] { view.typingAttributes[.font] = font }
        }

        /// The size each Month day line was fitted to.
        private var fitted: [String: UIFont] = [:]

        /// Keeps every line looking like its type (UIKit types new text with the attributes around the caret, and
        /// Scribble and the keyboard's suggestions bring their own), and a list number like a bullet: bold, in the
        /// color of its root. Skipped while text is being composed (marked), which an edit would break.
        /// How **bold**, *italic* and ==highlight== look on a line (render.ts inline): the words formatted, the
        /// markers hidden, or shown faintly while the caret (or selection) is in their span.
        struct InlineLook {
            var range: NSRange
            var attributes: [NSAttributedString.Key: Any]

            func matches(_ a: [NSAttributedString.Key: Any], _ r: NSRange) -> Bool {
                guard NSIntersectionRange(range, r).length == r.length else { return false }
                let want = attributes[.font] as? UIFont, font = a[.font] as? UIFont
                let traits: UIFontDescriptor.SymbolicTraits = [.traitBold, .traitItalic]
                return font?.fontDescriptor.symbolicTraits.intersection(traits) == want?.fontDescriptor.symbolicTraits.intersection(traits)
                    && ((font?.pointSize ?? 0) < 1) == ((want?.pointSize ?? 0) < 1)
                    && (a[.foregroundColor] as? UIColor) == (attributes[.foregroundColor] as? UIColor)
                    && (a[.backgroundColor] as? UIColor) == (attributes[.backgroundColor] as? UIColor)
            }
        }

        static let highlight = UIColor(red: 0xF2 / 255, green: 0xC9 / 255, blue: 0x4C / 255, alpha: 0.38)
        static let hiddenMarker = UIFont.systemFont(ofSize: 0.01)

        func inlineLooks(_ l: Line, at: Int, base: UIFont, color: UIColor) -> [InlineLook] {
            guard l.text.contains("*") || l.text.contains("==") else { return [] }
            let sel = textView?.selectedRange ?? NSRange(location: -1, length: 0)
            return InlineText.runs(l.text).map { run in
                let range = NSRange(location: at + run.location, length: run.length)
                if let span = run.span {
                    let start = at + span.location, end = start + span.length
                    let active = sel.location <= end && sel.location + sel.length >= start
                    return InlineLook(
                        range: range,
                        attributes: active ? [.font: base, .foregroundColor: Theme.ui("muted")] : [.font: Self.hiddenMarker, .foregroundColor: UIColor.clear])
                }
                var traits = base.fontDescriptor.symbolicTraits
                if run.bold { traits.insert(.traitBold) }
                if run.italic { traits.insert(.traitItalic) }
                let font = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
                var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                if run.highlight { a[.backgroundColor] = Self.highlight }
                return InlineLook(range: range, attributes: a)
            }
        }

        /// ⌘B, ⌘I, ⌘⇧H and the system's Bold/Italic: Markdown marks around the selection (within one line), or
        /// taken off when they are already there. The selection stays on the same words.
        func toggleInline(_ mark: String) {
            guard !parent.readOnly else { return }
            guard let view = textView, !lines.isEmpty else { return }
            let r = view.selectedRange
            let start = caret(at: r.location), end = caret(at: r.location + r.length)
            guard start.index == end.index else { return }
            let i = start.index
            let t = InlineText.toggle(lines[i].text, from: start.offset, to: end.offset, mark: mark)
            var next = lines
            next[i].text = t.text
            apply(Edited(lines: next, caret: Caret(index: i, offset: t.to)))
            let from = location(of: Caret(index: i, offset: t.from))
            view.selectedRange = NSRange(location: from, length: t.to - t.from)
            layoutDecor()
        }

        /// The markers show while the caret is in their span: the line is styled again when that changes.
        private var activeSpans: [Int] = []

        private func refreshActiveSpans() {
            guard let view = textView, let at = currentCaret() else { return }
            let l = lines[at.index]
            guard l.text.contains("*") || l.text.contains("==") || !activeSpans.isEmpty else { return }
            let lineStart = location(of: Caret(index: at.index, offset: 0))
            let sel = view.selectedRange
            let now = InlineText.runs(l.text).compactMap { run -> Int? in
                guard let span = run.span else { return nil }
                let start = lineStart + span.location, end = start + span.length
                return sel.location <= end && sel.location + sel.length >= start ? start : nil
            }
            if now != activeSpans {
                activeSpans = now
                restyle()
                fitFonts()
            }
        }

        private func restyle() {
            guard let view = textView, view.markedTextRange == nil else { return }
            let storage = view.textStorage
            let colors = Outline.colorTypes(lines)
            var at = 0
            storage.beginEditing()
            for (k, i) in visible.enumerated() {
                let l = lines[i]
                let len = (l.text as NSString).length
                let full = NSRange(location: at, length: min(len + (k < visible.count - 1 ? 1 : 0), storage.length - at))
                defer { at += len + 1 }
                guard full.length > 0, full.location + full.length <= storage.length else { continue }
                let want = attributes(l)
                let wantFont = want[.font] as? UIFont
                let wantStyle = want[.paragraphStyle] as? NSParagraphStyle
                // A list number has its own look (below): only the rest of the line is checked.
                let number = Outline.numberPrefix(l.text).map { ($0 as NSString).length } ?? 0
                let checked = NSRange(location: full.location + number, length: full.length - number)
                var wrong = false
                let tokens = Due.tokens(l.text).map { NSRange(location: at + $0.range.location, length: $0.range.length) }
                let inline = inlineLooks(l, at: at, base: wantFont ?? EditorLayout.font, color: want[.foregroundColor] as? UIColor ?? Theme.ui("text"))
                storage.enumerateAttributes(in: checked) { a, r, stop in
                    if tokens.contains(where: { NSIntersectionRange($0, r).length > 0 }) { return }
                    if let look = inline.first(where: { NSIntersectionRange($0.range, r).length > 0 }) {
                        // Formatted words and markers: one look per run, as inlineLooks says.
                        if !look.matches(a, r) {
                            wrong = true
                            stop.pointee = true
                        }
                        return
                    }
                    // A highlight left from text that is no longer marked (not the brief flash of an opened entry).
                    if (a[.backgroundColor] as? UIColor) == Self.highlight {
                        wrong = true
                        stop.pointee = true
                        return
                    }
                    let font = a[.font] as? UIFont
                    let fontOK = font?.fontName == wantFont?.fontName || (parent.fitOneLine && font?.familyName == wantFont?.familyName)
                    if !fontOK || (a[.paragraphStyle] as? NSParagraphStyle)?.headIndent != wantStyle?.headIndent
                        || (a[.foregroundColor] as? UIColor) != (want[.foregroundColor] as? UIColor)
                        || (a[.strikethroughStyle] != nil) != (want[.strikethroughStyle] != nil)
                    {
                        wrong = true
                        stop.pointee = true
                    }
                }
                if wrong {
                    storage.setAttributes(want, range: full)
                    for look in inline { storage.addAttributes(look.attributes, range: look.range) }
                }
                // "1. " / "2) ": the number is styled like a bullet (it stays part of the text).
                if number > 0 {
                    let r = NSRange(location: at, length: number)
                    let color = colors[i] == .text || colors[i] == .heading ? Theme.ui("task") : Theme.ui(colors[i].rawValue)
                    storage.addAttributes([.font: EditorLayout.bulletFont, .foregroundColor: color], range: r)
                }
                // A stored due date: its text makes room for the pill drawn over it (the text stays as written).
                for t in tokens {
                    storage.addAttributes([.foregroundColor: UIColor.clear, .font: EditorLayout.pillRoomFont], range: t)
                }
            }
            storage.endEditing()
        }

        func layoutDecor() {
            guard let view = textView else { return }
            restyle()
            fitFonts()
            if parent.embedded { view.invalidateIntrinsicContentSize() }
            let lm = view.layoutManager
            lm.ensureLayout(for: view.textContainer)
            let s = starts()
            let colors = Outline.colorTypes(lines)
            let length = (view.text as NSString).length
            var used = 0
            var usedChevrons = 0
            for (k, i) in visible.enumerated() {
                let l = lines[i]
                // The first line of the paragraph: the empty last line lives in the extra line fragment.
                var rect: CGRect
                if s[k] >= length && length > 0 && k == visible.count - 1 && l.text.isEmpty {
                    rect = lm.extraLineFragmentRect
                } else if length == 0 {
                    rect = lm.extraLineFragmentRect
                } else {
                    rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: min(s[k], length - 1)), effectiveRange: nil)
                }
                rect = rect.offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
                let glyph = States.glyph(l.type, l.state, eventStates: parent.eventStates, doneMark: parent.doneMark)
                if !glyph.isEmpty || l.priority || l.inspiration || l.explore {
                    let b = bullet(used)
                    used += 1
                    b.configure(line: l, glyph: glyph, color: Theme.ui(colors[i].rawValue), coordinator: self)
                    b.frame = CGRect(x: view.textContainerInset.left + EditorLayout.bulletX(l.indent), y: rect.minY, width: EditorLayout.bulletWidth, height: max(27, min(rect.height, 32)))
                }
                if Outline.hasChildren(lines, i) {
                    let c = chevron(usedChevrons)
                    usedChevrons += 1
                    c.setImage(UIImage(systemName: l.collapsed ? "chevron.right" : "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)), for: .normal)
                    c.accessibilityIdentifier = l.id
                    c.frame = CGRect(x: view.textContainerInset.left + EditorLayout.bulletX(l.indent) - 18, y: rect.minY, width: 20, height: max(27, min(rect.height, 32)))
                }
            }
            // Ink in the lines: drawings, and handwriting not transcribed yet.
            var usedInk = 0
            inkBottom = 0
            for (k, i) in visible.enumerated() {
                let l = lines[i]
                guard let f = previewFrame(l), let kind = InkPreview.kind(l) else { continue }
                var rect: CGRect
                if length == 0 || (s[k] >= length && k == visible.count - 1 && l.text.isEmpty) {
                    rect = lm.extraLineFragmentRect
                } else {
                    rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: min(s[k], length - 1)), effectiveRange: nil)
                }
                let v = inkView(usedInk)
                usedInk += 1
                v.configure(line: l, kind: kind, color: colors[i], selected: selectedDrawing == l.id, coordinator: self)
                // A drawing placed by hand stays where it was put; otherwise it starts at its line.
                let top = kind == .drawing ? l.ink?.view?.y.map { CGFloat($0) } : nil
                v.frame = CGRect(
                    x: view.textContainerInset.left + textIndent(l) + CGFloat(f.x), y: view.textContainerInset.top + (top ?? rect.minY + 3),
                    width: CGFloat(f.width), height: CGFloat(f.height))
                if kind == .drawing { inkBottom = max(inkBottom, v.frame.maxY) }
                v.maxWidth = CGFloat(f.width) + max(0, view.bounds.width - view.textContainerInset.left - view.textContainerInset.right - textIndent(l) - 8 - CGFloat(f.width))
                v.setNeedsDisplay()
            }
            for (n, v) in inkViews.enumerated() { v.isHidden = n >= usedInk }
            // Room below the text for a drawing put lower than the last line.
            if !parent.embedded {
                let text = lm.usedRect(for: view.textContainer).maxY + view.textContainerInset.top
                let bottom = max(240, inkBottom + 80 - text)
                if view.textContainerInset.bottom != bottom { view.textContainerInset.bottom = bottom }
            }
            // Due dates as pills; lists out of date order get a quiet "Sort by date".
            var usedPills = 0
            let today = Dates.today()
            for (k, i) in visible.enumerated() {
                let lineId = lines[i].id
                for t in Due.tokens(lines[i].text) {
                    let range = NSRange(location: s[k] + t.range.location, length: t.range.length)
                    guard range.location + range.length <= length else { continue }
                    let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let r = lm.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
                        .offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
                    let p = pill(usedPills)
                    usedPills += 1
                    p.configure(label: Due.label(t.iso, today: today, order: dateOrder), status: Due.status(t.iso, today: today)) { [weak self, weak p] in
                        guard let self, let p else { return }
                        self.pickDate(lineId: lineId, tokenStart: t.range.location, from: p)
                    }
                    let size = p.sizeThatFits(.zero)
                    p.frame = CGRect(x: r.minX, y: r.midY - size.height / 2, width: size.width, height: size.height)
                }
            }
            for (n, p) in pills.enumerated() { p.isHidden = n >= usedPills }
            var usedSorts = 0
            for run in Due.runs(lines) where !run.sorted {
                guard let k = visible.firstIndex(of: run.items[0]), s[k] < max(length, 1) else { continue }
                let rect = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: min(s[k], max(0, length - 1))), effectiveRange: nil)
                    .offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
                let b = sortButton(usedSorts)
                usedSorts += 1
                b.accessibilityIdentifier = lines[run.items[0]].id
                b.sizeToFit()
                b.frame = CGRect(x: view.bounds.width - view.textContainerInset.right - b.bounds.width, y: rect.minY - 18, width: b.bounds.width, height: 18)
            }
            for (n, b) in sortButtons.enumerated() { b.isHidden = n >= usedSorts }
            for (n, b) in bullets.enumerated() { b.isHidden = n >= used }
            for (n, c) in chevrons.enumerated() { c.isHidden = n >= usedChevrons }
        }

        private func bullet(_ n: Int) -> BulletView {
            if n < bullets.count { return bullets[n] }
            let b = BulletView()
            textView?.addSubview(b)
            bullets.append(b)
            return b
        }

        private func chevron(_ n: Int) -> UIButton {
            if n < chevrons.count { return chevrons[n] }
            let c = UIButton(type: .system)
            c.tintColor = Theme.ui("muted")
            c.addTarget(self, action: #selector(toggleCollapsed(_:)), for: .touchUpInside)
            textView?.addSubview(c)
            chevrons.append(c)
            return c
        }

        @objc private func toggleCollapsed(_ sender: UIButton) {
            guard let id = sender.accessibilityIdentifier else { return }
            parent.onAction(.toggleCollapsed, id)
        }

        /// A tap on a bullet: the next state (tasks, and events when Event states is on; notes never).
        func tapped(_ id: String) {
            guard let i = lines.firstIndex(where: { $0.id == id }), States.stateful(lines[i].type, eventStates: parent.eventStates) else { return }
            if parent.readOnly {
                // Written by the page (one entry); the lines come back changed through the binding.
                parent.onAction(.state(States.next(lines[i].state)), id)
                DispatchQueue.main.async { [weak self] in self?.celebrate(id) }
                return
            }
            var next = lines
            next[i].state = States.next(next[i].state)
            apply(Edited(lines: next, caret: currentCaret() ?? Caret(index: i, offset: 0)))
            celebrate(id)
        }

        /// The done animation (Settings), when a tap or ⌘↩ completes or cancels a line.
        func celebrate(_ id: String) {
            guard let i = lines.firstIndex(where: { $0.id == id }), lines[i].state == .done || lines[i].state == .cancelled,
                let view = textView, let b = bullets.first(where: { $0.lineId == id && !$0.isHidden })
            else { return }
            let root = Outline.colorTypes(lines)[i]
            let color = Theme.ui(root == .text || root == .heading ? "task" : root.rawValue)
            b.playDone(cancel: lines[i].state == .cancelled, check: parent.doneMark == "✓", color: color, host: view, textRect: textRect(i))
        }

        /// The words of a line, in the text view's coordinates (its first visual line).
        private func textRect(_ i: Int) -> CGRect? {
            guard let view = textView, !lines[i].text.isEmpty else { return nil }
            let start = location(of: Caret(index: i, offset: 0))
            let length = min((lines[i].text as NSString).length, (view.text as NSString).length - start)
            guard length > 0 else { return nil }
            let lm = view.layoutManager
            let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: start, length: length), actualCharacterRange: nil)
            var line = NSRange()
            _ = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &line)
            let first = NSIntersectionRange(glyphs, line)
            let r = lm.boundingRect(forGlyphRange: first.length > 0 ? first : glyphs, in: view.textContainer)
            return r.offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
        }

        func menu(for id: String) -> UIMenu? {
            guard let l = lines.first(where: { $0.id == id }) else { return nil }
            let act = { [weak self] (a: LineAction) in self?.parent.onAction(a, id) }
            let types = UIMenu(options: .displayInline, children: [
                UIAction(title: S.task) { _ in act(.type(.task)) },
                UIAction(title: S.event) { _ in act(.type(.event)) },
                UIAction(title: S.note) { _ in act(.type(.note)) },
                UIAction(title: S.text) { _ in act(.type(.text)) },
                UIAction(title: S.heading) { _ in act(.type(.heading)) },
            ])
            var states: [UIMenuElement] = []
            if States.stateful(l.type, eventStates: parent.eventStates) {
                states = [
                    UIAction(title: S.migrate) { _ in act(.state(.migrated)) },
                    UIAction(title: S.schedule) { _ in act(.state(.scheduled)) },
                ]
                if l.state != .open { states.append(UIAction(title: S.reopen) { _ in act(.state(.open)) }) }
            }
            var restItems: [UIMenuElement] = [
                UIAction(title: S.priority, state: l.priority ? .on : .off) { _ in act(.togglePriority) },
                UIAction(title: S.inspiration, state: l.inspiration ? .on : .off) { _ in act(.toggleInspiration) },
                UIAction(title: S.explore, state: l.explore ? .on : .off) { _ in act(.toggleExplore) },
            ]
            // A page to consult changes one entry's marks, never the page's structure.
            if !parent.readOnly {
                restItems += [
                    UIAction(title: S.indent) { _ in act(.indent) },
                    UIAction(title: S.outdent) { _ in act(.outdent) },
                    UIAction(title: S.delete, attributes: .destructive) { _ in act(.delete) },
                ]
            }
            let rest = UIMenu(options: .displayInline, children: restItems)
            return UIMenu(children: [types] + (states.isEmpty ? [] : [UIMenu(options: .displayInline, children: states)]) + [rest])
        }
    }
}

/// Where things sit on a line: the bullet in the margin, the text after it, 24 pt per indent level.
enum EditorLayout {
    static func inset(embedded: Bool) -> CGFloat { embedded ? 0 : 24 }
    static let step: CGFloat = 24
    static let bulletWidth: CGFloat = 26
    static func bulletX(_ indent: Int) -> CGFloat { CGFloat(indent) * step }
    static func textX(_ indent: Int) -> CGFloat { bulletX(indent) + bulletWidth + 4 }
    static let font = UIFont(name: "AvenirNext-Regular", size: 17) ?? .systemFont(ofSize: 17)
    static let headingFont = UIFont(name: "AvenirNext-Bold", size: 21) ?? .boldSystemFont(ofSize: 21)
    static let bulletFont = UIFont(name: "AvenirNext-DemiBold", size: 17) ?? .boldSystemFont(ofSize: 17)
    /// A stored "due:YYYY-MM-DD" is set this small (and clear): about the room its pill takes.
    static let pillRoomFont = UIFont(name: "AvenirNext-Regular", size: 12) ?? .systemFont(ofSize: 12)
}

/// The page's text view: hands Backspace at a line start, Tab and ⌘↩ to the editor, and keeps the page's own
/// Undo (its steps match the line model).
final class EditorTextView: UITextView {
    weak var coordinator: PageEditorView.Coordinator?

    override var undoManager: UndoManager? { coordinator?.undo ?? super.undoManager }

    /// ⌘C and the Copy menu take the selected lines from the model, with collapsed children (CLAUDE.md 7), as
    /// rich text and plain text.
    override func copy(_ sender: Any?) {
        guard let lines = coordinator?.selectedLines(), !lines.isEmpty else { return super.copy(sender) }
        let doc = ExportDoc.selection(lines)
        UIPasteboard.general.setItems([[
            Paste.linesType: Paste.json(lines), "public.html": Export.html(doc, colors: Theme.exportColors), "public.utf8-plain-text": Export.plain(doc),
        ]])
    }

    /// Pasting what the app copied (the exact lines), or Markdown and plain text with bullets, makes entries with
    /// their type, state and indentation; anything else is pasted as text.
    override func paste(_ sender: Any?) {
        let board = UIPasteboard.general
        if let data = board.data(forPasteboardType: Paste.linesType), let lines = Paste.fromJSON(data) {
            coordinator?.paste(lines)
        } else if let text = board.string, let lines = Paste.fromText(text) {
            coordinator?.paste(lines)
        } else {
            super.paste(sender)
        }
    }

    override func deleteBackward() {
        if coordinator?.backspaceAtLineStart() == true { return }
        super.deleteBackward()
    }

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentLines)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentLines)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(cycleState)),
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(toggleBoldface(_:))),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(toggleItalics(_:))),
            UIKeyCommand(input: "h", modifierFlags: [.command, .shift], action: #selector(toggleHighlight)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc private func indentLines() { coordinator?.shiftSelection(1) }
    @objc private func outdentLines() { coordinator?.shiftSelection(-1) }
    @objc private func cycleState() { coordinator?.cycleState() }
    @objc private func toggleHighlight() { coordinator?.toggleInline("==") }

    // The system's Format menu (B / I) writes Markdown marks too, never hidden attributes.
    override func toggleBoldface(_ sender: Any?) { coordinator?.toggleInline("**") }
    override func toggleItalics(_ sender: Any?) { coordinator?.toggleInline("*") }
    override func toggleUnderline(_ sender: Any?) {}

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleUnderline(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            coordinator?.layoutDecor()
        }
    }
    private var lastWidth: CGFloat = 0
}

/// A bullet in the margin: tap for the next state, hold (or right-click) for the bullet menu. Its target is
/// larger than the glyph (CLAUDE.md 8).
final class BulletView: UIView, UIContextMenuInteractionDelegate {
    private let label = UILabel()
    /// Signifiers, just left of the bullet: * priority, ! inspiration, an eye for explore.
    private let signifiers = UILabel()
    private var id = ""
    var lineId: String { id }
    private weak var coordinator: PageEditorView.Coordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = EditorLayout.bulletFont
        addSubview(label)
        signifiers.textAlignment = .right
        addSubview(signifiers)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        addInteraction(UIContextMenuInteraction(delegate: self))
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(line: Line, glyph: String, color: UIColor, coordinator: PageEditorView.Coordinator) {
        id = line.id
        self.coordinator = coordinator
        label.text = glyph
        label.textColor = color
        let marks = NSMutableAttributedString()
        let attrs: [NSAttributedString.Key: Any] = [.font: EditorLayout.bulletFont, .foregroundColor: color]
        if line.priority { marks.append(NSAttributedString(string: "*", attributes: attrs)) }
        if line.inspiration { marks.append(NSAttributedString(string: "!", attributes: attrs)) }
        if line.explore, let eye = UIImage(systemName: "eye", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)) {
            let attachment = NSTextAttachment(image: eye.withTintColor(color, renderingMode: .alwaysOriginal))
            marks.append(NSAttributedString(attachment: attachment))
        }
        signifiers.attributedText = marks
        var parts = ["\(line.type.rawValue)", line.state.rawValue]
        if line.priority { parts.append(S.priority) }
        if line.inspiration { parts.append(S.inspiration) }
        if line.explore { parts.append(S.explore) }
        accessibilityLabel = parts.joined(separator: ", ")
    }

    func playDone(cancel: Bool, check: Bool, color: UIColor, host: UIView, textRect: CGRect?) {
        DoneFx.play(cancel: cancel, check: check, bullet: self, mark: label, color: color, host: host, textRect: textRect)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        signifiers.frame = CGRect(x: -30, y: 0, width: 30, height: bounds.height)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -8, dy: -8).contains(point)
    }

    @objc private func tap() { coordinator?.tapped(id) }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menu = coordinator?.menu(for: id) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu }
    }
}

/// A line's ink in Type mode: handwriting not transcribed yet (smaller, as written), or a drawing in a box that
/// can be selected (tap), sized (drag the corner), moved sideways (drag it) and deleted (×).
final class InkPreviewView: UIView {
    private var ink: Ink?
    private var id = ""
    private var kind: InkPreview.Kind = .writing
    private var colorType: EntryType = .text
    private weak var coordinator: PageEditorView.Coordinator?
    /// The widest the drawing can be from where its box starts (the page's text column).
    var maxWidth: CGFloat = 600
    private let close = UIButton(type: .system)
    private let handle = UIView()
    private var start: CGRect = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        layer.cornerRadius = 6
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = Theme.ui("muted")
        close.addTarget(self, action: #selector(remove), for: .touchUpInside)
        close.accessibilityLabel = S.deleteDrawing
        handle.backgroundColor = Theme.ui("muted")
        handle.layer.cornerRadius = 3
        addSubview(close)
        addSubview(handle)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resize(_:))))
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(line: Line, kind: InkPreview.Kind, color: EntryType, selected: Bool, coordinator: PageEditorView.Coordinator) {
        ink = line.ink
        id = line.id
        self.kind = kind
        colorType = color
        self.coordinator = coordinator
        let editable = kind == .drawing && !coordinator.parent.readOnly
        isUserInteractionEnabled = editable
        close.isHidden = !(editable && selected)
        handle.isHidden = !(editable && selected)
        gestureRecognizers?.forEach { if $0 is UIPanGestureRecognizer { $0.isEnabled = editable && selected } }
        layer.borderWidth = editable && selected ? 1 : 0
        layer.borderColor = Theme.ui("muted").cgColor
        accessibilityLabel = kind == .drawing ? S.drawing : S.handwritingPending
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        close.frame = CGRect(x: bounds.width - 14, y: -14, width: 28, height: 28)
        handle.frame = CGRect(x: bounds.width - 10, y: bounds.height - 10, width: 14, height: 14)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -16, dy: -16).contains(point)
    }

    override func draw(_ rect: CGRect) {
        guard let ink, let b = InkPreview.bounds(ink) else { return }
        let s = bounds.width / CGFloat(max(1, b.x1 - b.x0))
        for stroke in ink.strokes where stroke.p.count >= 3 {
            let path = UIBezierPath()
            var i = 0
            while i + 1 < stroke.p.count {
                let pt = CGPoint(x: CGFloat(stroke.p[i] - b.x0) * s, y: CGFloat(stroke.p[i + 1] - b.y0) * s)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                i += 3
            }
            if stroke.p.count == 3 { path.addLine(to: path.currentPoint) }
            path.lineWidth = max(0.6, CGFloat(stroke.s ?? storedDefaultSize) * s)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            (stroke.b == true ? Theme.ui(colorType.rawValue) : Theme.ui(stroke.c)).setStroke()
            path.stroke()
        }
    }

    @objc private func tap() { coordinator?.tappedDrawing(id) }
    @objc private func remove() { coordinator?.deleteDrawing(id) }

    /// Anywhere on the page: it floats over the text (it may cover some) and can go below the last line.
    @objc private func drag(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: superview)
        switch g.state {
        case .began:
            start = frame
            superview?.bringSubviewToFront(self)
        case .changed:
            frame.origin = CGPoint(x: start.minX + t.x, y: max(0, start.minY + t.y))
        case .ended, .cancelled:
            let x = max(0, frame.minX - start.minX + offsetInColumn)
            let inset = (superview as? UITextView)?.textContainerInset.top ?? 0
            coordinator?.setDrawingView(id, width: Double(bounds.width), x: Double(x), y: Double(frame.minY - inset))
        default: break
        }
    }

    /// Its offset in the column when the drag began (the frame's x includes the line's start).
    private var offsetInColumn: CGFloat { CGFloat(ink?.view?.x ?? 0) }

    /// The corner: wider or narrower, keeping its proportions.
    @objc private func resize(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began: start = frame
        case .changed:
            let w = min(max(CGFloat(InkPreview.minDrawingWidth), start.width + g.translation(in: superview).x), maxWidth)
            frame = CGRect(x: start.minX, y: start.minY, width: w, height: start.height * w / start.width)
            setNeedsDisplay()
        case .ended, .cancelled:
            coordinator?.setDrawingView(id, width: Double(bounds.width), x: Double(offsetInColumn), y: ink?.view?.y)
        default: break
        }
    }
}

/// A due date as a pill: a calendar and "Today" / "Tomorrow" / "23 Oct", colored by how near it is.
final class DuePillView: UIButton {
    private var onTap: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8)
        config.image = UIImage(systemName: "calendar", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        configuration = config
        addAction(UIAction { [weak self] _ in self?.onTap() }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(label: String, status: DueStatus, onTap: @escaping () -> Void) {
        self.onTap = onTap
        let color: UIColor
        switch status {
        case .overdue: color = Theme.ui("task")
        case .today: color = Theme.ui("event")
        case .future: color = Theme.ui("muted")
        }
        var config = configuration ?? .filled()
        var title = AttributedString(label)
        title.font = UIFont(name: "AvenirNext-DemiBold", size: 12) ?? .systemFont(ofSize: 12, weight: .semibold)
        config.attributedTitle = title
        config.baseForegroundColor = color
        config.baseBackgroundColor = color.withAlphaComponent(0.13)
        configuration = config
        accessibilityLabel = "\(S.due) \(label)"
    }
}

/// The calendar a due pill opens.
final class DatePickerController: UIViewController, UIPopoverPresentationControllerDelegate {
    private let picker = UIDatePicker()
    private let onPick: (Date) -> Void

    init(date: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        super.init(nibName: nil, bundle: nil)
        picker.date = date
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onPick(self.picker.date)
            self.dismiss(animated: true)
        }, for: .valueChanged)
        view.addSubview(picker)
        picker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])
        preferredContentSize = CGSize(width: 340, height: 360)
    }

    /// A popover on iPhone too, not a full-screen sheet.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
}
