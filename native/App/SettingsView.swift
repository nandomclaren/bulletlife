// Settings (CLAUDE.md 12): bringing the PWA's data over, the logs that are on, banners, export and print, and the
// settings the pages use. Kept on this device (UserDefaults), as the PWA keeps them per device.
import BulletLifeCore
import SwiftData
import SwiftUI
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
    @AppStorage("closeDay") private var closeDay = true
    @AppStorage("closeDayAt") private var closeDayAt = "20:00"
    @AppStorage("glyphStyle") private var glyphStyle = GlyphStyle.checkboxes.rawValue
    @AppStorage("dateOrder") private var dateOrder = DateOrder.dmy.rawValue
    @State private var printing: [Any]?
    @ObservedObject private var handwriting = Handwriting.shared

    var body: some View {
        Form {
            Section {
                Button(S.importButton) { importing = true }
                if let message { Text(message).foregroundStyle(.secondary) }
            } header: {
                Text(S.importTitle)
            } footer: {
                Text(S.importHint)
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
                Toggle(S.closeDay, isOn: $closeDay)
                if closeDay {
                    DatePicker(S.closeDayTime, selection: closeDayTime, displayedComponents: .hourAndMinute)
                }
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
