import AppKit
import LensMonitorCore

/// Esegue la scelta di `DashboardDestination` (core, testata): l'app OpenCode Lens della lens o il
/// browser. Un'app già aperta riceve il "riapri" di LaunchServices, lo stesso del clic sul Dock,
/// che le fa rimostrare la finestra della dashboard se era chiusa.
enum DashboardOpener {
    /// Dove LaunchServices trova l'app OpenCode Lens; `nil` se non è installata. Si interroga a
    /// ogni clic, non all'avvio: l'app si installa e si toglie con `app.sh` mentre il Monitor è aperto.
    static func companionApp() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: CompanionApp.bundleIdentifier)
    }

    @MainActor
    static func open(_ destination: DashboardDestination) {
        switch destination {
        case .app(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .browser(let url):
            NSWorkspace.shared.open(url)
        }
    }
}
