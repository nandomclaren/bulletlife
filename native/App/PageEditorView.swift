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
        return CGSize(width: width, height: max(minHeight, ceil(fit.height)))
    }

    func updateUIView(_ view: EditorTextView, context: Context) {
        let c = context.coordinator
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
        if let highlight, highlight != c.flashed {
            c.flashed = highlight
            DispatchQueue.main.async { c.flash(highlight) }
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
            let bulletless = l.type == .text || l.type == .heading
            let indent = parent.embedded && bulletless ? EditorLayout.bulletX(l.indent) : EditorLayout.textX(l.indent)
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            // Embedded (Month, Year): the line is as tall as the normal text, so a shrunk phrase keeps its baseline
            // level with the day's number beside it.
            style.minimumLineHeight = l.type == .heading ? 32 : parent.embedded ? EditorLayout.font.lineHeight : 27
            style.paragraphSpacing = 5
            var a: [NSAttributedString.Key: Any] = [
                .font: l.type == .heading ? EditorLayout.headingFont : EditorLayout.font,
                .foregroundColor: faded ? Theme.ui("muted") : Theme.ui("text"),
                .paragraphStyle: style,
            ]
            if stateful && l.state == .cancelled { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            return a
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
                var edited = multi || range.length > 0 ? PageEdit.deleteRange(lines, from: start, to: end) : Edited(lines: lines, caret: start)
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
            guard let view = textView, view.selectedRange.length == 0 else { return false }
            let at = caret(at: view.selectedRange.location)
            guard at.offset == 0 else { return false }
            if let edited = PageEdit.backspaceAtStart(lines, at: at) { apply(edited) }
            return true
        }

        func shiftSelection(_ delta: Int) {
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
            guard let at = currentCaret(), States.stateful(lines[at.index].type, eventStates: parent.eventStates) else { return }
            var next = lines
            next[at.index].state = States.next(next[at.index].state)
            apply(Edited(lines: next, caret: at))
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
            // Leaving a line written by Scribble reads its prefix now.
            if let pendingId = pendingPrefix?.id, let at = currentCaret(), lines[at.index].id != pendingId { applyPendingPrefix() }
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
                    if (value as? UIFont)?.pointSize != size {
                        uniform = false
                        stop.pointee = true
                    }
                }
                if !uniform { storage.addAttribute(.font, value: font, range: range) }
            }
            // What is typed next comes in at the line's size.
            if let at = currentCaret(), let font = fitted[lines[at.index].id] { view.typingAttributes[.font] = font }
        }

        /// The size each Month day line was fitted to.
        private var fitted: [String: UIFont] = [:]

        /// Keeps every line looking like its type (UIKit types new text with the attributes around the caret, and
        /// Scribble and the keyboard's suggestions bring their own), and a list number like a bullet: bold, in the
        /// color of its root. Skipped while text is being composed (marked), which an edit would break.
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
                storage.enumerateAttributes(in: checked) { a, _, stop in
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
                if wrong { storage.setAttributes(want, range: full) }
                // "1. " / "2) ": the number is styled like a bullet (it stays part of the text).
                if number > 0 {
                    let r = NSRange(location: at, length: number)
                    let color = colors[i] == .text || colors[i] == .heading ? Theme.ui("task") : Theme.ui(colors[i].rawValue)
                    storage.addAttributes([.font: EditorLayout.bulletFont, .foregroundColor: color], range: r)
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
            var next = lines
            next[i].state = States.next(next[i].state)
            apply(Edited(lines: next, caret: currentCaret() ?? Caret(index: i, offset: 0)))
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
            let rest = UIMenu(options: .displayInline, children: [
                UIAction(title: S.priority, state: l.priority ? .on : .off) { _ in act(.togglePriority) },
                UIAction(title: S.inspiration, state: l.inspiration ? .on : .off) { _ in act(.toggleInspiration) },
                UIAction(title: S.explore, state: l.explore ? .on : .off) { _ in act(.toggleExplore) },
                UIAction(title: S.indent) { _ in act(.indent) },
                UIAction(title: S.outdent) { _ in act(.outdent) },
                UIAction(title: S.delete, attributes: .destructive) { _ in act(.delete) },
            ])
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
            Paste.linesType: Paste.json(lines), "public.html": Export.html(doc), "public.utf8-plain-text": Export.plain(doc),
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
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc private func indentLines() { coordinator?.shiftSelection(1) }
    @objc private func outdentLines() { coordinator?.shiftSelection(-1) }
    @objc private func cycleState() { coordinator?.cycleState() }

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
