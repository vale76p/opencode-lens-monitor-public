import Foundation

/// Stato del login item dell'app monitor.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval

    /// Stato dell'interruttore: acceso anche in attesa di approvazione (il login item è
    /// registrato), così spegnerlo lo annulla invece di ripetere la registrazione.
    public var isOn: Bool { self != .disabled }
}

/// Avvio dell'app monitor al login; nell'app è SMAppService.mainApp.
@MainActor
public protocol LoginItemControlling {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Login item che annota da dove è stato registrato. SMAppService registra il bundle nel
/// percorso da cui l'app gira: dopo che install.sh la sposta da /Applications a ~/Applications
/// (e la copia vecchia finisce nel Cestino) il login item aprirebbe ancora quella vecchia.
/// Percorso e stato stanno nelle UserDefaults dell'app, dove li legge anche install.sh
/// (`defaults read local.opencode-lens-monitor`): lo stato vero del login item, senza
/// `sfltool dumpbtm`, che a volte resta bloccato.
///
/// Solo un'app in /Applications o ~/Applications annota e sposta il login item: una build di
/// sviluppo ha lo stesso bundle id e le stesse UserDefaults, e lo porterebbe su DerivedData.
@MainActor
public struct RecordedLoginItem: LoginItemControlling {
    public static let pathKey = "loginItemPath"
    public static let statusKey = "loginItemStatus"

    private let base: any LoginItemControlling
    private let defaults: UserDefaults
    private let bundlePath: String
    private let installed: Bool

    public init(base: any LoginItemControlling, defaults: UserDefaults, bundlePath: String, home: String) {
        self.base = base
        self.defaults = defaults
        self.bundlePath = bundlePath
        let folder = (bundlePath as NSString).deletingLastPathComponent
        installed = folder == "/Applications" || folder == (home as NSString).appendingPathComponent("Applications")
    }

    public var status: LoginItemStatus { base.status }

    public func setEnabled(_ enabled: Bool) throws {
        do {
            try base.setEnabled(enabled)
        } catch {
            recordStatus()
            throw error
        }
        record()
    }

    /// All'avvio: un login item registrato da un altro percorso, o da una versione che non lo
    /// annotava (fino alla 0.4.0), viene registrato di nuovo da qui. Se non riesce resta
    /// annotato il percorso vecchio, così al prossimo avvio si riprova.
    public func relocateIfMoved() throws {
        guard installed else { return }
        if base.status != .disabled, defaults.string(forKey: Self.pathKey) != bundlePath {
            do {
                try base.setEnabled(false)
                try base.setEnabled(true)
            } catch {
                recordStatus()
                throw error
            }
        }
        record()
    }

    private func record() {
        guard installed else { return }
        recordStatus()
        if base.status == .disabled {
            defaults.removeObject(forKey: Self.pathKey)
        } else {
            defaults.set(bundlePath, forKey: Self.pathKey)
        }
    }

    private func recordStatus() {
        guard installed else { return }
        let value = switch base.status {
        case .enabled: "enabled"
        case .disabled: "disabled"
        case .requiresApproval: "requiresApproval"
        }
        defaults.set(value, forKey: Self.statusKey)
    }
}
