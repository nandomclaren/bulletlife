// A free page of the notebook (Day or Week): its lines, written straight away. Phase N0 edits one line per
// field; the full editor (selection across lines, keyboard rules of the PWA) comes in phase N1.
import BulletLifeCore
import SwiftData
import SwiftUI

struct RootView: View {
    @State private var period: Period = .day(Dates.today())

    var body: some View {
        NavigationStack {
            PageView(period: $period)
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
}

struct PageView: View {
    @Binding var period: Period
    @Environment(\.modelContext) private var context
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var lines: [Line] = []
    @FocusState private var focus: String?

    private var repo: Repository { Repository(context: context) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                header
                    .padding(.bottom, 16)
                let colors = Outline.colorTypes(lines)
                let hidden = Outline.hidden(lines)
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                    if !hidden[i] {
                        LineRow(
                            line: binding(line.id), color: colors[i], hasChildren: Outline.hasChildren(lines, i),
                            eventStates: eventStates, doneMark: doneMark, focus: $focus,
                            onSplit: { split(line.id, rest: $0) }, onAction: { act($0, on: line.id) }
                        )
                    }
                }
                // The rest of the page: tapping it starts a new line (or goes to the empty last one).
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .contentShape(Rectangle())
                    .onTapGesture { writeAtEnd() }
                    .accessibilityLabel(S.newLine)
                    .accessibilityAddTraits(.isButton)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: load)
        .onChange(of: period) { load() }
        .onChange(of: lines) { repo.save(lines, logId: period.logId) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("", selection: levelBinding) {
                    Text(S.day).tag(0)
                    Text(S.week).tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Spacer()
                Button {
                    period = period.moved(-1, firstDay: firstDay)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(S.previous)
                Button(S.today) {
                    period = Period.containing(Dates.today(), like: period, firstDay: firstDay)
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                Button {
                    period = period.moved(1, firstDay: firstDay)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel(S.next)
            }
            .font(Theme.body(15))
            Text(label.uppercased())
                .font(Theme.body(13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            Text(title)
                .font(Theme.body(30, weight: .bold))
                .foregroundStyle(Theme.text)
        }
    }

    private var levelBinding: Binding<Int> {
        Binding(
            get: {
                if case .week = period { return 1 }
                return 0
            },
            set: { level in
                let anchor = period.start(firstDay: firstDay)
                let today = Dates.today()
                let inside = today >= anchor && today <= period.end(firstDay: firstDay)
                let day = inside ? today : anchor
                period = level == 1 ? .week(Dates.weekKey(day, firstDay: firstDay)) : .day(day)
            })
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
        lines = repo.lines(logId: period.logId)
        focus = nil
    }

    private func binding(_ id: String) -> Binding<Line> {
        Binding(
            get: { lines.first { $0.id == id } ?? Line(id: id) },
            set: { new in
                if let i = lines.firstIndex(where: { $0.id == id }) { lines[i] = new }
            })
    }

    private func writeAtEnd() {
        if let last = lines.last, last.text.isEmpty, last.ink == nil {
            focus = last.id
            return
        }
        let fresh = Line(type: lines.last.map { continuation($0.type) } ?? .text, indent: lines.last?.indent ?? 0)
        lines.append(fresh)
        focus = fresh.id
    }

    /// Return in a line: what follows the caret goes to a new line below, of the same kind (a task after a task).
    private func split(_ id: String, rest: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let line = lines[i]
        // Return on an empty bulleted line ends the list: the line becomes plain text.
        if line.text.isEmpty && rest.isEmpty && line.type != .text {
            lines[i].type = .text
            lines[i].state = .open
            return
        }
        let fresh = Line(type: continuation(line.type), indent: line.indent, text: rest)
        let at = line.collapsed ? Outline.subtreeEnd(lines, i) : i + 1
        lines.insert(fresh, at: at)
        focus = fresh.id
    }

    private func continuation(_ type: EntryType) -> EntryType {
        type == .heading ? .text : type
    }

    private func act(_ action: LineAction, on id: String) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        switch action {
        case .type(let t):
            lines[i].type = t
            if !States.stateful(t, eventStates: eventStates) { lines[i].state = .open }
        case .state(let s):
            lines[i].state = s
        case .togglePriority:
            lines[i].priority.toggle()
        case .indent:
            // At most one level below the line above.
            if i > 0 && lines[i].indent <= lines[i - 1].indent {
                for j in i..<Outline.subtreeEnd(lines, i) { lines[j].indent += 1 }
            }
        case .outdent:
            if lines[i].indent > 0 {
                for j in i..<Outline.subtreeEnd(lines, i) { lines[j].indent -= 1 }
            }
        case .toggleCollapsed:
            lines[i].collapsed.toggle()
        case .delete:
            lines.removeSubrange(i..<Outline.subtreeEnd(lines, i))
        }
    }
}

enum LineAction {
    case type(EntryType)
    case state(EntryState)
    case togglePriority, indent, outdent, toggleCollapsed, delete
}

struct LineRow: View {
    @Binding var line: Line
    let color: EntryType
    let hasChildren: Bool
    let eventStates: Bool
    let doneMark: String
    var focus: FocusState<String?>.Binding
    let onSplit: (String) -> Void
    let onAction: (LineAction) -> Void

    private var stateful: Bool { States.stateful(line.type, eventStates: eventStates) }
    private var faded: Bool { stateful && line.state != .open }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            chevron
            bullet
            TextField("", text: $line.text, axis: .vertical)
                .focused(focus, equals: line.id)
                .font(line.type == .heading ? Theme.body(21, weight: .bold) : Theme.body())
                .foregroundStyle(faded ? Theme.muted : Theme.text)
                .strikethrough(stateful && line.state == .cancelled)
                // The caret takes the bullet's color (CLAUDE.md 8).
                .tint(Theme.color(color))
                .textInputAutocapitalization(.sentences)
                .onChange(of: line.text) { _, new in typed(new) }
        }
        .padding(.leading, CGFloat(line.indent) * 26)
        .padding(.vertical, 3)
    }

    private var chevron: some View {
        Button {
            onAction(.toggleCollapsed)
        } label: {
            Image(systemName: line.collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .frame(width: 12)
        .opacity(hasChildren ? 1 : 0)
        .disabled(!hasChildren)
    }

    private var bullet: some View {
        let glyph = States.glyph(line.type, line.state, eventStates: eventStates, doneMark: doneMark)
        return Text(glyph.isEmpty ? " " : glyph)
            .font(Theme.body(17, weight: .bold))
            .foregroundStyle(Theme.color(color))
            .frame(width: line.type == .text || line.type == .heading ? 4 : 22, alignment: .center)
            // A larger target than the glyph (CLAUDE.md 8: 44 pt).
            .frame(minHeight: 28)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture {
                if stateful { line.state = States.next(line.state) }
            }
            .contextMenu { menu }
            .accessibilityLabel("\(line.type.rawValue), \(line.state.rawValue)")
    }

    @ViewBuilder private var menu: some View {
        Section {
            Button(S.task) { onAction(.type(.task)) }
            Button(S.event) { onAction(.type(.event)) }
            Button(S.note) { onAction(.type(.note)) }
            Button(S.text) { onAction(.type(.text)) }
            Button(S.heading) { onAction(.type(.heading)) }
        }
        if stateful {
            Section {
                Button(S.migrate) { onAction(.state(.migrated)) }
                Button(S.schedule) { onAction(.state(.scheduled)) }
                if line.state != .open { Button(S.reopen) { onAction(.state(.open)) } }
            }
        }
        Section {
            Button(S.priority) { onAction(.togglePriority) }
            Button(S.indent) { onAction(.indent) }
            Button(S.outdent) { onAction(.outdent) }
            Button(S.delete, role: .destructive) { onAction(.delete) }
        }
    }

    private func typed(_ new: String) {
        // Return: what follows the line break goes to a new line below.
        if let br = new.firstIndex(of: "\n") {
            let rest = String(new[new.index(after: br)...]).replacingOccurrences(of: "\n", with: " ")
            line.text = String(new[..<br])
            onSplit(rest)
            return
        }
        // Rapid logging: ". " task, "o. " event, "- " note, "# " heading, "* " priority (CLAUDE.md 3.4).
        if line.type == .text || line.type == .heading || new.hasPrefix("* "), let m = Rapid.leading(new) {
            if m.type != .text { line.type = m.type }
            if m.priority { line.priority = true }
            line.state = .open
            line.text = String(new.dropFirst(m.length))
        }
    }
}
