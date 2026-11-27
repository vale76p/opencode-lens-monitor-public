import AppKit
import LensMonitorCore

/// Clic sui widget (opencode-lens-monitor://dashboard): dashboard se la lens risponde, altrimenti
/// le impostazioni, che apre l'etichetta della barra osservando `settingsRequests`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Impostato dall'app all'avvio, prima che arrivino URL.
    @MainActor static var model: MonitorModel?

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "opencode-lens-monitor" && $0.host() == "dashboard" }) else { return }
        guard let model = Self.model else {
            NSWorkspace.shared.open(AppLens.client().browserURL)
            return
        }
        if let destination = model.widgetClicked() { DashboardOpener.open(destination) }
    }
}
