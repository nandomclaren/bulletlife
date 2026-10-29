// Settings (CLAUDE.md 12), the part phase N0 needs: bringing the PWA's data over, and the settings the
// pages already use. Kept on this device (UserDefaults), as the PWA keeps them per device.
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
}
