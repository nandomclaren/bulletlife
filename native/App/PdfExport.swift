// PDF to print (CLAUDE.md 7): A5, plain paper, drawn as vectors from the entries: handwriting where it was
// written (as in Pen mode), drawings, and typed entries with colored bullets (the palette's light version) and
// the done mark from Settings. Each notebook page starts on a new sheet; a Month shows all its days with the
// week rules, a Year its twelve months. From the page menu (one page) or Settings › Print (a period, in
// notebook order: the Year, then each Month with its weeks and days; collections last).
import BulletLifeCore
import UIKit

/// One notebook page to print.
struct PrintPage {
    enum Body {
        case free([Line])
        case month(ym: String, days: [(String, [Line])], tasks: [Line])
        case year(months: [(String, [Line])])
        /// A month of habits: the rows with their marks, and the notes under their days (one landscape sheet).
        case habits(ym: String, rows: [Entry], notes: [Entry])
    }
    var label: String
    var title: String
    var body: Body
    var fileName: String
}

enum PrintRange: String, CaseIterable, Identifiable {
    case thisMonth, thisYear, everything
    var id: String { rawValue }
    var name: String {
        switch self {
        case .thisMonth: return S.thisMonthPrint
        case .thisYear: return S.thisYear
        case .everything: return S.everything
        }
    }
}

enum PrintPages {
    /// The page the menu is on.
    static func pages(for place: Place, repo: Repository, firstDay: Weekday) -> [PrintPage]? {
        switch place {
        case .index: return nil
        case .collection(let id):
            guard let log = repo.collection(id) else { return nil }
            if log.template == Habits.template { return [habits(log, month: Dates.monthOf(Dates.today()), repo: repo)] }
            return [PrintPage(label: S.collections, title: log.title, body: .free(repo.lines(logId: id)), fileName: log.title)]
        case .time(let p): return [page(p, repo: repo, firstDay: firstDay)]
        }
    }

    /// A month of a Habits collection.
    static func habits(_ log: Log, month ym: String, repo: Repository) -> PrintPage {
        PrintPage(
            label: PageView.format("\(ym)-01", "MMMM yyyy"), title: log.title,
            body: .habits(ym: ym, rows: repo.habits(logId: log.id, month: ym), notes: repo.habitNotes(logId: log.id, month: ym)),
            fileName: "\(log.title) \(ym)")
    }

    /// The Habits collections' months within `months` (nil: all) that have something written.
    static func habitPages(_ repo: Repository, months: Set<String>?) -> [PrintPage] {
        repo.collections().filter { $0.template == Habits.template }.flatMap { log in
            repo.habitMonths(logId: log.id).filter { months?.contains($0) ?? true }.map { habits(log, month: $0, repo: repo) }
        }
    }

    static func page(_ p: Period, repo: Repository, firstDay: Weekday) -> PrintPage {
        switch p {
        case .day(let d):
            return PrintPage(label: PageView.format(d, "EEEE"), title: PageView.format(d, "MMMM d, yyyy"), body: .free(repo.lines(logId: p.logId)), fileName: d)
        case .week(let k):
            let start = Dates.weekKeyStart(k, firstDay: firstDay)
            let label = "\(PageView.format(start, "MMM d")) – \(PageView.format(Dates.addDays(start, 6), "MMM d"))"
            return PrintPage(label: label, title: S.weekTitle(Dates.weekNumber(k)), body: .free(repo.lines(logId: p.logId)), fileName: k)
        case .month(let ym):
            let days = Dates.monthDays(ym).map { ($0, repo.lines(logId: p.logId, slot: $0)) }
            return PrintPage(
                label: PageView.format("\(ym)-01", "MMMM"), title: PageView.format("\(ym)-01", "MMMM yyyy"),
                body: .month(ym: ym, days: days, tasks: repo.lines(logId: p.logId)), fileName: ym)
        case .year(let y):
            let months = (0..<12).map { n -> (String, [Line]) in
                let ym = Dates.addMonths("\(y)-01", n)
                return (ym, repo.lines(logId: p.logId, slot: ym))
            }
            return PrintPage(label: S.yearKind, title: y, body: .year(months: months), fileName: y)
        }
    }

    /// Settings › Print: a period in notebook order. Months always print (their layout is the notebook's);
    /// weeks and days only when something is written in them.
    static func pages(_ range: PrintRange, repo: Repository, firstDay: Weekday, today: String = Dates.today()) -> [PrintPage] {
        let written = repo.writtenLogIds()
        var seen = Set<String>()
        func month(_ ym: String) -> [PrintPage] {
            var out = [page(.month(ym), repo: repo, firstDay: firstDay)]
            var weeks: [String] = []
            for d in Dates.monthDays(ym) {
                let k = Dates.weekKey(d, firstDay: firstDay)
                if !weeks.contains(k) { weeks.append(k) }
            }
            for k in weeks {
                let w = Period.week(k)
                if written.contains(w.logId) && seen.insert(w.logId).inserted { out.append(page(w, repo: repo, firstDay: firstDay)) }
                for d in Dates.weekDays(k, firstDay: firstDay) where Dates.monthOf(d) == ym {
                    let day = Period.day(d)
                    if written.contains(day.logId) && seen.insert(day.logId).inserted { out.append(page(day, repo: repo, firstDay: firstDay)) }
                }
            }
            return out
        }
        func year(_ y: String, everyMonth: Bool) -> [PrintPage] {
            var out = [page(.year(y), repo: repo, firstDay: firstDay)]
            for n in 0..<12 {
                let ym = Dates.addMonths("\(y)-01", n)
                let hasWriting = written.contains { id in
                    id == "monthly:\(ym)" || id.hasPrefix("daily:\(ym)")
                        || (id.hasPrefix("weekly:") && Dates.monthOf(Dates.weekKeyStart(String(id.dropFirst(7)), firstDay: firstDay)) == ym)
                }
                if everyMonth || hasWriting { out += month(ym) }
            }
            return out
        }
        switch range {
        case .thisMonth:
            return month(Dates.monthOf(today)) + habitPages(repo, months: [Dates.monthOf(today)])
        case .thisYear:
            let y = Dates.yearOf(today)
            return year(y, everyMonth: false) + habitPages(repo, months: Set((0..<12).map { Dates.addMonths("\(y)-01", $0) }))
        case .everything:
            let years = Set(written.compactMap { id -> String? in
                guard let key = id.split(separator: ":", maxSplits: 1).last, !id.hasPrefix("collection:") else { return nil }
                return String(key.prefix(4))
            }).sorted()
            var out = years.flatMap { year($0, everyMonth: false) }
            for c in repo.collections() where written.contains(c.id) {
                if c.template == Habits.template {
                    out += repo.habitMonths(logId: c.id).map { habits(c, month: $0, repo: repo) }
                } else {
                    out.append(PrintPage(label: S.collections, title: c.title, body: .free(repo.lines(logId: c.id)), fileName: c.title))
                }
            }
            return out
        }
    }
}

enum PdfExport {
    static let size = CGSize(width: 419.53, height: 595.28)  // A5
    static let margin: CGFloat = 36
    /// Pen mode's sheet is drawn about this wide; ink is scaled from it to the printed width.
    static let sheetWidth: CGFloat = 720

    static func light(_ token: String) -> UIColor { Theme.ui(token).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)) }

    static func render(_ pages: [PrintPage], firstDay: Weekday) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        return renderer.pdfData { ctx in
            for page in pages {
                if case .habits(let ym, let rows, let notes) = page.body {
                    HabitsSheet(ctx: ctx, firstDay: firstDay).draw(page, ym: ym, rows: rows, notes: notes)
                    continue
                }
                var writer = Writer(ctx: ctx, firstDay: firstDay)
                writer.newSheet()
                writer.header(page)
                switch page.body {
                case .free(let lines): writer.lines(lines)
                case .month(let ym, let days, let tasks): writer.month(ym, days: days, tasks: tasks)
                case .year(let months): writer.year(months)
                case .habits: break
                }
            }
        }
    }

    struct Writer {
        let ctx: UIGraphicsPDFRendererContext
        let firstDay: Weekday
        var y: CGFloat = margin
        let width = size.width - margin * 2
        let eventStates = UserDefaults.standard.object(forKey: "eventStates") as? Bool ?? true
        let doneMark = UserDefaults.standard.string(forKey: "doneMark") ?? "×"

        static func font(_ size: CGFloat, bold: Bool = false) -> UIFont {
            UIFont(name: bold ? "AvenirNext-DemiBold" : "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        }

        mutating func newSheet() {
            ctx.beginPage()
            y = margin
        }

        /// Room for `h` more points, or a new sheet.
        mutating func need(_ h: CGFloat) {
            if y + h > size.height - margin { newSheet() }
        }

        mutating func header(_ page: PrintPage) {
            let label = NSAttributedString(
                string: page.label.uppercased(), attributes: [.font: Self.font(8, bold: true), .foregroundColor: light("muted"), .kern: 1])
            label.draw(at: CGPoint(x: margin, y: y))
            y += 14
            let title = NSAttributedString(string: page.title, attributes: [.font: Self.font(20, bold: true), .foregroundColor: light("text")])
            title.draw(at: CGPoint(x: margin, y: y))
            y += 34
        }

        mutating func sectionTitle(_ text: String) {
            need(30)
            y += 8
            NSAttributedString(string: text.uppercased(), attributes: [.font: Self.font(8, bold: true), .foregroundColor: light("muted"), .kern: 1])
                .draw(at: CGPoint(x: margin, y: y))
            y += 16
        }

        /// A page's lines from `x` (collapsed children included: collapsing never changes what is printed).
        mutating func lines(_ lines: [Line], x: CGFloat = margin, width w: CGFloat? = nil, size: CGFloat = 10.5) {
            let colors = Outline.colorTypes(lines)
            for (i, l) in lines.enumerated() {
                draw(l, color: colors[i], x: x, width: w ?? width, size: size)
            }
        }

        mutating func draw(_ l: Line, color: EntryType, x: CGFloat, width w: CGFloat, size: CGFloat) {
            // Handwriting and drawings print as they were written.
            if let ink = l.ink, !ink.strokes.isEmpty {
                let s = w / sheetWidth
                let h = CGFloat(max(1, ink.rows)) * CGFloat(inkRow) * s
                need(h)
                for stroke in ink.strokes { drawStroke(stroke, type: color, x: x, y: y, scale: s) }
                y += h
                return
            }
            let indent = CGFloat(l.indent) * 14
            let glyph = States.glyph(l.type, l.state, eventStates: eventStates, doneMark: doneMark)
            let stateful = States.stateful(l.type, eventStates: eventStates)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: l.type == .heading ? Self.font(size + 2, bold: true) : Self.font(size),
                .foregroundColor: stateful && l.state != .open ? light("muted") : light("text"),
            ]
            if stateful && l.state == .cancelled { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            let textX = x + indent + (glyph.isEmpty ? 0 : 14)
            let text = NSAttributedString(string: l.text.isEmpty ? " " : l.text, attributes: attrs)
            let box = text.boundingRect(with: CGSize(width: w - (textX - x), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
            let h = max(ceil(box.height), size * 1.45) + 3
            need(h)
            if !glyph.isEmpty {
                NSAttributedString(string: glyph, attributes: [.font: Self.font(size, bold: true), .foregroundColor: light(color.rawValue)])
                    .draw(at: CGPoint(x: x + indent, y: y))
            }
            text.draw(with: CGRect(x: textX, y: y, width: w - (textX - x), height: box.height + 2), options: [.usesLineFragmentOrigin], context: nil)
            y += h
        }

        func drawStroke(_ stroke: Stroke, type: EntryType, x: CGFloat, y top: CGFloat, scale s: CGFloat) {
            guard stroke.p.count >= 3 else { return }
            let path = UIBezierPath()
            var i = 0
            while i + 1 < stroke.p.count {
                let pt = CGPoint(x: x + CGFloat(stroke.p[i]) * s, y: top + CGFloat(stroke.p[i + 1]) * s)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                i += 3
            }
            if stroke.p.count == 3 { path.addLine(to: path.currentPoint) }
            (stroke.b == true ? light(type.rawValue) : light(stroke.c)).setStroke()
            // The fountain pen: each piece as wide as the nib was there.
            if stroke.fountain, let nib = stroke.w, nib.count >= stroke.p.count, stroke.p.count >= 6 {
                var j = 0
                while j + 5 < stroke.p.count {
                    let piece = UIBezierPath()
                    piece.move(to: CGPoint(x: x + CGFloat(stroke.p[j]) * s, y: top + CGFloat(stroke.p[j + 1]) * s))
                    piece.addLine(to: CGPoint(x: x + CGFloat(stroke.p[j + 3]) * s, y: top + CGFloat(stroke.p[j + 4]) * s))
                    piece.lineWidth = max(0.3, CGFloat((nib[j] + nib[j + 1] + nib[j + 3] + nib[j + 4]) / 4) * s)
                    piece.lineCapStyle = .round
                    piece.stroke()
                    j += 3
                }
                return
            }
            path.lineWidth = max(0.4, CGFloat(stroke.s ?? 2.4) * s)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }

        /// All the days on one sheet when they fit: number, initial, the day's lines, week rules.
        mutating func month(_ ym: String, days: [(String, [Line])], tasks: [Line]) {
            let rowFont: CGFloat = 8.5
            for (n, (iso, lines)) in days.enumerated() {
                if n > 0 && Dates.weekday(iso) == firstDay {
                    need(6)
                    let rule = UIBezierPath(rect: CGRect(x: margin, y: y + 2, width: width, height: 0.5))
                    light("rule").setFill()
                    rule.fill()
                    y += 5
                }
                let weekend = [0, 6].contains(Dates.weekday(iso))
                need(rowFont * 1.6)
                let color = weekend ? light("muted") : light("text")
                NSAttributedString(string: String(Int(iso.suffix(2)) ?? 0), attributes: [.font: Self.font(rowFont).withSize(rowFont), .foregroundColor: color])
                    .draw(at: CGPoint(x: margin, y: y))
                NSAttributedString(string: PageView.format(iso, "EEEEE"), attributes: [.font: Self.font(rowFont - 1), .foregroundColor: light("muted")])
                    .draw(at: CGPoint(x: margin + 16, y: y + 0.5))
                if lines.isEmpty {
                    y += rowFont * 1.6
                } else {
                    let start = y
                    self.lines(lines, x: margin + 30, width: width - 30, size: rowFont)
                    y = max(y, start + rowFont * 1.6)
                }
            }
            if !tasks.isEmpty {
                sectionTitle(S.monthTasks)
                lines(tasks)
            }
        }

        mutating func year(_ months: [(String, [Line])]) {
            for (ym, lines) in months {
                sectionTitle(PageView.format("\(ym)-01", "MMMM"))
                if lines.isEmpty { y += 14 } else { self.lines(lines) }
            }
        }
    }
}

/// A month of habits on one A5 sheet turned sideways (31 days need the width): the names, the days with their
/// initials and week rules, the marks, and the notes under their days with a bracket, as on paper.
struct HabitsSheet {
    let ctx: UIGraphicsPDFRendererContext
    let firstDay: Weekday
    static let size = CGSize(width: PdfExport.size.height, height: PdfExport.size.width)
    let margin: CGFloat = 28
    let doneMark = UserDefaults.standard.string(forKey: "doneMark") ?? "×"

    private func light(_ token: String) -> UIColor { PdfExport.light(token) }
    private func font(_ size: CGFloat, bold: Bool = false) -> UIFont { PdfExport.Writer.font(size, bold: bold) }

    private func text(_ s: String, _ size: CGFloat, _ color: UIColor, bold: Bool = false) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font(size, bold: bold), .foregroundColor: color])
    }

    func draw(_ page: PrintPage, ym: String, rows: [Entry], notes: [Entry]) {
        ctx.beginPage(withBounds: CGRect(origin: .zero, size: Self.size), pageInfo: [:])
        let w = Self.size.width - margin * 2
        var y = margin
        NSAttributedString(
            string: page.label.uppercased(), attributes: [.font: font(8, bold: true), .foregroundColor: light("muted"), .kern: 1]
        ).draw(at: CGPoint(x: margin, y: y))
        y += 13
        text(page.title, 17, light("text"), bold: true).draw(at: CGPoint(x: margin, y: y))
        y += 30

        let days = Dates.monthDays(ym)
        let nameWidth: CGFloat = 96
        let cell = (w - nameWidth) / 31
        let gridX = margin + nameWidth
        let noteFont = font(7.5)
        // Notes: their days and lanes, as on the screen.
        let spans: [(note: Entry, first: Int, span: Int, columns: Int)] = notes.compactMap { n in
            guard let d = Habits.noteDays(n.slot) else { return nil }
            let first = Int(d.start.suffix(2)) ?? 1
            let last = Dates.monthOf(d.end) == ym ? Int(d.end.suffix(2)) ?? first : days.count
            let span = max(1, last - first + 1)
            let width = min(140, (n.text as NSString).size(withAttributes: [.font: noteFont]).width + 4)
            return (n, first, span, max(span, Int((width / cell).rounded(.up))))
        }
        let lanes = Habits.lanes(spans.map { (id: $0.note.id, first: $0.first, columns: $0.columns) })
        let laneCount = (lanes.values.max() ?? -1) + 1
        let laneHeight: CGFloat = 26
        let headerHeight: CGFloat = 20
        let room = Self.size.height - margin - y - headerHeight - CGFloat(laneCount) * laneHeight - (laneCount > 0 ? 6 : 0)
        let rowHeight = max(9, min(15, room / CGFloat(max(1, rows.count))))

        // Day numbers and initials.
        for (i, iso) in days.enumerated() {
            let x = gridX + CGFloat(i) * cell
            let weekend = [0, 6].contains(Dates.weekday(iso))
            let n = text(String(i + 1), 6.5, weekend ? light("muted") : light("text"))
            n.draw(at: CGPoint(x: x + (cell - n.size().width) / 2, y: y))
            let initial = text(PageView.format(iso, "EEEEE"), 6, light("muted"))
            initial.draw(at: CGPoint(x: x + (cell - initial.size().width) / 2, y: y + 9))
        }
        let top = y
        y += headerHeight
        let gridBottom = y + CGFloat(rows.count) * rowHeight
        // Week rules, from the header to the last habit.
        light("rule").setFill()
        for (i, iso) in days.enumerated() where i > 0 && Dates.weekday(iso) == firstDay {
            UIBezierPath(rect: CGRect(x: gridX + CGFloat(i) * cell, y: top, width: 0.5, height: gridBottom - top)).fill()
        }
        // The habits and their marks.
        let truncating = NSMutableParagraphStyle()
        truncating.lineBreakMode = .byTruncatingTail
        for row in rows {
            NSAttributedString(string: row.text, attributes: [.font: font(7.5), .foregroundColor: light("text"), .paragraphStyle: truncating])
                .draw(in: CGRect(x: margin, y: y + (rowHeight - 10) / 2, width: nameWidth - 6, height: 10))
            for i in 0..<days.count {
                let cx = gridX + CGFloat(i) * cell + cell / 2
                let cy = y + rowHeight / 2
                switch Habits.mark(row.marks, day: i + 1) {
                case .done:
                    let m = text(doneMark, 8, light("task"), bold: true)
                    m.draw(at: CGPoint(x: cx - m.size().width / 2, y: cy - m.size().height / 2))
                case .missed:
                    light("text").setFill()
                    UIBezierPath(ovalIn: CGRect(x: cx - 1.3, y: cy - 1.3, width: 2.6, height: 2.6)).fill()
                case .skipped:
                    light("muted").setFill()
                    UIBezierPath(rect: CGRect(x: cx - 2.5, y: cy - 0.35, width: 5, height: 0.7)).fill()
                case .empty:
                    light("rule").setFill()
                    UIBezierPath(ovalIn: CGRect(x: cx - 0.6, y: cy - 0.6, width: 1.2, height: 1.2)).fill()
                }
            }
            y += rowHeight
        }
        // The notes under their days.
        y += 6
        for s in spans {
            let x = gridX + CGFloat(s.first - 1) * cell + 1
            let ny = y + CGFloat(lanes[s.note.id] ?? 0) * laneHeight
            let right = x + CGFloat(s.span) * cell - 2
            let bracket = UIBezierPath()
            bracket.move(to: CGPoint(x: x, y: ny))
            bracket.addLine(to: CGPoint(x: x, y: ny + 3))
            bracket.addLine(to: CGPoint(x: right, y: ny + 3))
            bracket.addLine(to: CGPoint(x: right, y: ny))
            bracket.lineWidth = 0.7
            bracket.lineCapStyle = .round
            light("event").setStroke()
            bracket.stroke()
            NSAttributedString(string: s.note.text, attributes: [.font: noteFont, .foregroundColor: light("text")])
                .draw(
                    with: CGRect(x: x, y: ny + 5, width: CGFloat(s.columns) * cell - 2, height: laneHeight - 6),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
    }
}
