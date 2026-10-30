// Settings (CLAUDE.md 12): bringing the PWA's data over, the logs that are on, banners, export and print, and the
// settings the pages use. Kept on this device (UserDefaults), as the PWA keeps them per device.
import BulletLifeCore
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    private var handwritingStatus: String {
        switch handwriting.status {
        case .unavailable: return S.hwUnavailable
        case .notDownloaded: return S.hwNotDownloaded
        case .downloading: return S.hwDownloading
        case .ready: return S.hwReady
        case .failed: return S.hwFailed
        }
    }

    @Environment(\.modelContext) private var context
    @AppStorage("firstDay") private var firstDay = 1
    @AppStorage("eventStates") private var eventStates = true
    @AppStorage("doneMark") private var doneMark = "×"
    @State private var importing = false
    @State private var message: String?
    @State private var count = 0
    @AppStorage("handwritingLang") private var handwritingLang = HandwritingLang.ptBR.rawValue
    @AppStorage("logMonthly") private var monthly = true
    @AppStorage("logWeekly") private var weekly = true
    @AppStorage("logDaily") private var daily = true
    @AppStorage("setupBanner") private var setupBanner = true
    @AppStorage("openCount") private var openCount = true
    @AppStorage("prefixTask") private var prefixTask = "."
    @AppStorage("prefixEvent") private var prefixEvent = "o."
    @AppStorage("prefixNote") private var prefixNote = "-"
    @AppStorage("prefixHeading") private var prefixHeading = "#"
    @AppStorage("prefixPriority") private var prefixPriority = "*"
    @AppStorage("closeDay") private var closeDay = true
    @AppStorage("closeDayAt") private var closeDayAt = "20:00"
    @AppStorage("closeDayNotify") private var closeDayNotify = false
    @State private var notificationsOff = false
    @AppStorage("glyphStyle") private var glyphStyle = GlyphStyle.checkboxes.rawValue
    @AppStorage("dateOrder") private var dateOrder = DateOrder.dmy.rawValue
    @AppStorage("theme") private var theme = Theme.Look.auto.rawValue
    @AppStorage("palette") private var palette = Theme.Palette.classic.rawValue
    @AppStorage("doneAnimation") private var doneAnimation = DoneAnimation.ink.rawValue
    @State private var printing: [Any]?
    @ObservedObject private var handwriting = Handwriting.shared

    var body: some View {
        Form {
            Section {
                Button(S.exportEverything) {
                    printing = PageDocs.everything(
                        repo: Repository(context: context), firstDay: firstDay, style: GlyphStyle(rawValue: glyphStyle) ?? .checkboxes)
                }
            } header: {
                Text(S.backup)
            } footer: {
                Text(S.exportEverythingHint)
            }
            Section {
                Button(S.importButton) { importing = true }
                if let message { Text(message).foregroundStyle(.secondary) }
            } header: {
                Text(S.importTitle)
            } footer: {
                Text(S.importHint)
            }
            Section {
                Picker(S.theme, selection: $theme) {
                    ForEach(Theme.Look.allCases) { look in
                        VStack(alignment: .leading) {
                            Text(look.name)
                            Text(look.hint).font(.footnote).foregroundStyle(.secondary)
                        }
                        .tag(look.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)
                Picker(selection: $palette) {
                    ForEach(Theme.Palette.allCases) { p in
                        HStack {
                            Text(p.name)
                            Spacer()
                            PaletteDots(palette: p)
                        }
                        .tag(p.rawValue)
                    }
                } label: {
                    Text(S.palette)
                }
                .pickerStyle(.navigationLink)
                Picker(selection: $doneAnimation) {
                    ForEach(DoneAnimation.allCases) { a in
                        VStack(alignment: .leading) {
                            Text(a.name)
                            Text(a.hint).font(.footnote).foregroundStyle(.secondary)
                        }
                        .tag(a.rawValue)
                    }
                } label: {
                    Text(S.doneAnimation)
                }
                .pickerStyle(.navigationLink)
                DonePreview(animation: doneAnimation, check: doneMark == "✓")
                    .frame(height: 44)
            } header: {
                Text(S.looks)
            } footer: {
                Text(S.paletteHint + " " + S.doneAnimationHint)
            }
            Section {
                // At least one of Month, Week and Day stays on (the last one can't be turned off).
                let active = ActiveLogs(monthly: monthly, weekly: weekly, daily: daily)
                Toggle(S.month, isOn: $monthly).disabled(monthly && !active.canTurnOff(.monthly))
                Toggle(S.week, isOn: $weekly).disabled(weekly && !active.canTurnOff(.weekly))
                Toggle(S.day, isOn: $daily).disabled(daily && !active.canTurnOff(.daily))
            } header: {
                Text(S.logs)
            } footer: {
                Text(S.logsHint)
            }
            Section {
                Toggle(S.setupBanner, isOn: $setupBanner)
                Toggle(S.openCount, isOn: $openCount)
                Toggle(S.closeDay, isOn: $closeDay)
                if closeDay {
                    DatePicker(S.closeDayTime, selection: closeDayTime, displayedComponents: .hourAndMinute)
                    Toggle(S.closeDayNotify, isOn: $closeDayNotify)
                    if notificationsOff { Text(S.notificationsOff).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .onChange(of: closeDayNotify) {
                guard closeDayNotify else { return Reminders.update() }
                Task {
                    let allowed = await Reminders.requestPermission()
                    notificationsOff = !allowed
                    if !allowed { closeDayNotify = false }
                    Reminders.update()
                }
            }
            .onChange(of: closeDay) { Reminders.update() }
            .onChange(of: closeDayAt) { Reminders.update() }
            .onChange(of: daily) { Reminders.update() }
            Section {
                prefixField(S.task, $prefixTask)
                prefixField(S.event, $prefixEvent)
                prefixField(S.note, $prefixNote)
                prefixField(S.heading, $prefixHeading)
                prefixField(S.priority, $prefixPriority)
            } header: {
                Text(S.prefixes)
            } footer: {
                Text(S.prefixesHint)
            }
            Section {
                Picker(S.glyphStyle, selection: $glyphStyle) {
                    Text(S.checkboxes).tag(GlyphStyle.checkboxes.rawValue)
                    Text(S.dotNotation).tag(GlyphStyle.dots.rawValue)
                }
            }
            Section {
                ForEach(PrintRange.allCases) { range in
                    Button(range.name) { printRange(range) }
                }
            } header: {
                Text(S.print)
            } footer: {
                Text(S.printHint)
            }
            Section {
                // How a short due date is typed and shown: day or month first.
                Picker(S.dateFormat, selection: $dateOrder) {
                    Text("DD/MM").tag(DateOrder.dmy.rawValue)
                    Text("MM/DD").tag(DateOrder.mdy.rawValue)
                }
                Picker(S.firstDay, selection: $firstDay) {
                    Text(S.monday).tag(1)
                    Text(S.sunday).tag(0)
                }
                Toggle(isOn: $eventStates) {
                    VStack(alignment: .leading) {
                        Text(S.eventStates)
                        Text(S.eventStatesHint).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Picker(S.doneMark, selection: $doneMark) {
                    Text("×").tag("×")
                    Text("✓").tag("✓")
                }
            }
            Section {
                Picker(S.language, selection: $handwritingLang) {
                    ForEach(HandwritingLang.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Text(handwritingStatus).foregroundStyle(.secondary)
            } header: {
                Text(S.handwriting)
            } footer: {
                Text(S.handwritingHint)
            }
            Section(S.onDevice) {
                Text(S.entries(count)).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(S.settings)
        .sheet(isPresented: Binding(get: { printing != nil }, set: { if !$0 { printing = nil } })) {
            ActivityView(items: printing ?? [])
        }
        .onAppear {
            count = Repository(context: context).entryCount()
            handwriting.prepare(HandwritingLang(rawValue: handwritingLang) ?? .ptBR)
        }
        // A prefix left empty (or clashing) is written back as the one in use, so it can be read later.
        .onDisappear(perform: settlePrefixes)
        .onChange(of: handwritingLang) { handwriting.prepare(HandwritingLang(rawValue: handwritingLang) ?? .ptBR) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let n = try Repository(context: context).importBackup(data)
                message = S.imported(n)
                count = n
            } catch {
                message = S.importFailed
            }
        }
    }

    private func settlePrefixes() {
        let p = Prefs.prefixes
        if prefixTask != p.task { prefixTask = p.task }
        if prefixEvent != p.event { prefixEvent = p.event }
        if prefixNote != p.note { prefixNote = p.note }
        if prefixHeading != p.heading { prefixHeading = p.heading }
        if prefixPriority != p.priority { prefixPriority = p.priority }
    }

    /// A rapid-logging prefix: typed at a line's start, then a space.
    private func prefixField(_ name: String, _ value: Binding<String>) -> some View {
        LabeledContent(name) {
            TextField("", text: value)
                .onSubmit(settlePrefixes)
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: 80)
        }
    }

    /// The Close the day time, stored as "HH:mm".
    private var closeDayTime: Binding<Date> {
        Binding(
            get: {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                return f.date(from: closeDayAt) ?? Date()
            },
            set: {
                let f = DateFormatter()
                f.dateFormat = "HH:mm"
                closeDayAt = f.string(from: $0)
            })
    }

    private func printRange(_ range: PrintRange) {
        let pages = PrintPages.pages(range, repo: Repository(context: context), firstDay: firstDay)
        guard !pages.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(PageMenu.fileName("Bullet Life · \(range.name)", "pdf"))
        try? PdfExport.render(pages, firstDay: firstDay).write(to: url)
        printing = [url]
    }
}

/// A palette's three colors, in the tone the theme shows.
struct PaletteDots: View {
    let palette: Theme.Palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { k in
                let c = palette.colors[k]
                Circle()
                    .fill(Color(uiColor: UIColor(hex: scheme == .dark ? c.1 : c.0)))
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A sample task: tapping its bullet plays the chosen done animation (and cancels on the second tap, as on a page).
struct DonePreview: UIViewRepresentable {
    let animation: String
    let check: Bool

    func makeUIView(context: Context) -> PreviewRow { PreviewRow() }

    func updateUIView(_ row: PreviewRow, context: Context) {
        row.animation = DoneAnimation(rawValue: animation) ?? .ink
        row.check = check
        row.refresh()
    }

    final class PreviewRow: UIView {
        var animation: DoneAnimation = .ink
        var check = false
        private var state: EntryState = .open
        private let bullet = UIView()
        private let glyph = UILabel()
        private let text = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .secondarySystemGroupedBackground
            glyph.textAlignment = .center
            glyph.font = UIFont(name: "AvenirNext-Bold", size: 17) ?? .boldSystemFont(ofSize: 17)
            bullet.addSubview(glyph)
            addSubview(bullet)
            text.font = UIFont(name: "AvenirNext-Regular", size: 17) ?? .systemFont(ofSize: 17)
            addSubview(text)
            bullet.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
            bullet.isAccessibilityElement = true
            bullet.accessibilityTraits = .button
            refresh()
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            bullet.frame = CGRect(x: 0, y: (bounds.height - 44) / 2, width: 44, height: 44)
            glyph.frame = bullet.bounds
            text.sizeToFit()
            text.frame.origin = CGPoint(x: 48, y: (bounds.height - text.frame.height) / 2)
        }

        func refresh() {
            glyph.text = States.glyph(.task, state, eventStates: true, doneMark: check ? "✓" : "×")
            glyph.textColor = Theme.ui("task")
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: state == .open ? Theme.ui("text") : Theme.ui("muted"),
                .strikethroughStyle: state == .cancelled ? NSUnderlineStyle.single.rawValue : 0,
            ]
            text.attributedText = NSAttributedString(string: S.previewTask, attributes: attrs)
            bullet.accessibilityLabel = "\(S.task), \(state.rawValue)"
            setNeedsLayout()
        }

        @objc private func tap() {
            state = States.next(state)
            refresh()
            layoutIfNeeded()
            guard state == .done || state == .cancelled else { return }
            DoneFx.play(
                animation, cancel: state == .cancelled, check: check, bullet: bullet, mark: glyph, color: Theme.ui("task"), host: self,
                textRect: text.frame)
        }
    }
}
