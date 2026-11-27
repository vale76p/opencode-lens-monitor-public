import Foundation

/// Impostazioni che l'app passa al widget: dal sandbox il widget non può leggere il plist del LaunchAgent.
public struct SharedConfig: Equatable, Sendable {
    public var host: String
    public var port: Int
    /// `LENS_TOKEN` del plist, in chiaro come nel plist stesso.
    public var token: String?
    /// Lens scelta nelle impostazioni; host, porta e token qui sopra sono già quelli risolti.
    public var target: LensTarget
    /// Secondi tra una lettura dei dati e la successiva, uno di `RefreshInterval.choices`.
    /// Solo l'app lo usa: i widget hanno il loro ritmo, limitato da WidgetKit.
    public var refreshInterval: TimeInterval

    public init(
        host: String = LensConfig.defaultHost,
        port: Int,
        token: String?,
        target: LensTarget = .service,
        refreshInterval: TimeInterval = RefreshInterval.default
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.target = target
        self.refreshInterval = refreshInterval
    }

    public static let `default` = SharedConfig(port: LensConfig.defaultPort, token: nil)
}

/// Ogni quanto l'app rilegge budget e modelli. Sotto i 15 s non serve: la lens aggrega i token
/// a ogni messaggio finito, e ogni lettura sono due richieste più il conteggio dei modelli.
public enum RefreshInterval {
    public static let choices: [TimeInterval] = [15, 30, 60, 120, 300]
    public static let `default`: TimeInterval = 60
}

public protocol SharedSettingsStore: Sendable {
    /// Il widget legge queste impostazioni: senza App Group (build ad-hoc) no, e host, porta e
    /// token non vanno copiati, perché lì servirebbero solo a lasciare il token in un plist in più.
    var reachesWidget: Bool { get }
    func load() -> SharedConfig
    func save(_ config: SharedConfig)
}

/// `UserDefaults` dell'App Group condiviso da app e widget.
public struct UserDefaultsSettings: SharedSettingsStore {
    public static let appGroup = "HS87DR6TBX.local.opencode-lens-monitor"
    static let team = "HS87DR6TBX"

    /// La suite di questo processo, letta una volta dalla sua firma.
    public static let defaultSuite: String? = suite(forTeam: CodeSignature.teamIdentifier())

    /// macOS accetta l'App Group HS87DR6TBX.… solo da un processo firmato da quel team. Una build
    /// ad-hoc (scripts/build-clt.sh senza certificato) se lo vede rifiutare da cfprefsd, con un
    /// errore nel log a ogni accesso: usa allora le UserDefaults del processo. L'app ci ritrova la
    /// lens scelta in Server; il widget, che non le vede, resta sui default (127.0.0.1:4777).
    static func suite(forTeam team: String?) -> String? {
        team == Self.team ? appGroup : nil
    }

    /// nil: le UserDefaults del processo.
    private let suiteName: String?
    public let reachesWidget: Bool

    public init(suiteName: String? = UserDefaultsSettings.defaultSuite) {
        self.init(suiteName: suiteName, reachesWidget: suiteName != nil)
    }

    init(suiteName: String?, reachesWidget: Bool) {
        self.suiteName = suiteName
        self.reachesWidget = reachesWidget
    }

    /// Valori mancanti o non validi tornano al default.
    public func load() -> SharedConfig {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return .default }
        let port = defaults.integer(forKey: "port")
        let interval = defaults.double(forKey: "refreshInterval")
        return SharedConfig(
            host: defaults.string(forKey: "host").flatMap { $0.isEmpty ? nil : $0 } ?? LensConfig.defaultHost,
            port: (1...65535).contains(port) ? port : LensConfig.defaultPort,
            token: defaults.string(forKey: "token").flatMap { $0.isEmpty ? nil : $0 },
            target: defaults.string(forKey: "target").flatMap(LensTarget.init(rawValue:)) ?? .service,
            refreshInterval: RefreshInterval.choices.contains(interval) ? interval : RefreshInterval.default
        )
    }

    /// Il widget legge le chiavi da un altro processo, anche a metà scrittura: senza token si toglie
    /// il token prima di cambiare host e porta, con il token lo si scrive dopo. Così il widget non
    /// vede mai l'host di una lens di sviluppo insieme al token di produzione.
    public func save(_ config: SharedConfig) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if reachesWidget {
            if config.token == nil { defaults.removeObject(forKey: "token") }
            defaults.set(config.host, forKey: "host")
            defaults.set(config.port, forKey: "port")
            if let token = config.token { defaults.set(token, forKey: "token") }
        } else {
            // fino alla 0.5.1 si copiavano anche qui
            for key in ["token", "host", "port"] { defaults.removeObject(forKey: key) }
        }
        defaults.set(config.target.rawValue, forKey: "target")
        defaults.set(config.refreshInterval, forKey: "refreshInterval")
    }
}

/// Le impostazioni come le legge il widget. Senza App Group (firma ad-hoc) host, porta e token
/// vengono dal plist del LaunchAgent, che l'entitlement del widget lascia leggere (solo quel file):
/// dalla 0.38 la lens ha sempre un `LENS_TOKEN`, e senza ogni richiesta avrebbe un 401.
public struct WidgetSettings: SharedSettingsStore {
    private let base: any SharedSettingsStore
    private let plist: URL

    public init(base: any SharedSettingsStore = UserDefaultsSettings(), plist: URL = Paths.plist) {
        self.base = base
        self.plist = plist
    }

    public var reachesWidget: Bool { base.reachesWidget }

    public func load() -> SharedConfig {
        var config = base.load()
        guard !base.reachesWidget else { return config }
        // LENS_MONITOR_PORT è dell'app: senza App Group non arriva al widget
        let endpoint = LensConfig.endpoint(for: .service, plistAt: plist, environment: [:])
        config.host = endpoint.host
        config.port = endpoint.port
        config.token = endpoint.token
        return config
    }

    public func save(_ config: SharedConfig) { base.save(config) }
}
