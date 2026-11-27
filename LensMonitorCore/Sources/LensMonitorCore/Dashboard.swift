import Foundation

/// L'app macOS della lens (`extras/macos`, lens ≥ 0.37.0): una finestra sulla dashboard con Dock,
/// notifiche e avvio al login, che sta accanto al Monitor senza avviare né fermare la lens.
public enum CompanionApp {
    public static let bundleIdentifier = "local.opencode-lens.app"
}

/// Dove va «Apri la dashboard» (piede del pannello, impostazioni, clic sui widget).
public enum DashboardDestination: Equatable, Sendable {
    /// L'app OpenCode Lens, al percorso in cui è installata: da attivare.
    case app(URL)
    /// La dashboard nel browser.
    case browser(URL)

    /// L'app segue solo porta e token del plist del LaunchAgent: con una lens di sviluppo
    /// mostrerebbe la produzione, quindi lì si apre sempre il browser. `companionApp` è dove
    /// LaunchServices trova l'app, `nil` se non è installata.
    public static func resolve(target: LensTarget, dashboardURL: URL, companionApp: URL?) -> DashboardDestination {
        if target == .service, let companionApp { return .app(companionApp) }
        return .browser(dashboardURL)
    }
}
