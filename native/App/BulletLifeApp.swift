// Bullet Life, native (iPad and iPhone). Phase N0: the notebook's pages as lines, stored on the device, and
// the PWA's data brought over from its backup file (CLAUDE.md 17).
import SwiftData
import SwiftUI

@main
struct BulletLifeApp: App {
    let container: ModelContainer = {
        // iCloud sync is off until the app has an Apple Developer team with iCloud (phase N5): then
        // `.automatic` with the iCloud capability; the models are already shaped for it.
        let config = ModelConfiguration(cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: EntryRecord.self, LogRecord.self, configurations: config)
        } catch {
            fatalError("Could not open the notebook: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .commands { NotebookCommands() }
    }
}
