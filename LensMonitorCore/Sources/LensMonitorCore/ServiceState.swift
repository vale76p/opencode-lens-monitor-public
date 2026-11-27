import Foundation

/// Stato del servizio mostrato nella barra.
public enum ServiceState: Equatable, Sendable {
    case notInstalled
    case stopped
    /// Caricato ma non in esecuzione, o in esecuzione senza risposta da /healthz.
    case starting
    /// `starting` che dura da più di `startTimeout`.
    case failed(String)
    case running(opencodeConnected: Bool)
    /// Stato non ancora noto: all'avvio dell'app e subito dopo un cambio di lens.
    case checking
    /// Lens di sviluppo scelta nelle impostazioni che non risponde a /healthz.
    case unreachable
    /// Era caricata e qualcun altro l'ha scaricata (di solito le Impostazioni della lens, che si
    /// riavviano con bootout + bootstrap): per `externalRestartGrace` secondi si aspetta che torni.
    case restarting

    /// `.failed` quando sulla porta della lens ascolta un altro processo (`ListenerVerifying`).
    public static let foreignListenerMessage = "porta occupata da un altro processo"
    public static let startTimeout: TimeInterval = 15
    /// Secondi dal primo "non caricata" in cui uno stop fuori dal Monitor è ancora un riavvio.
    public static let externalRestartGrace: TimeInterval = 20

    /// `startingFor`: da quanti secondi lo stato è `starting` (0 se non lo era).
    public static func resolve(installed: Bool, load: LoadState, health: HealthFetch, startingFor: TimeInterval) -> ServiceState {
        guard installed else { return .notInstalled }
        let timedOut = startingFor >= startTimeout
        switch load {
        case .notLoaded:
            return .stopped
        case .loaded(running: false, _):
            return timedOut ? .failed("caricato ma non in esecuzione: controlla il log") : .starting
        case .loaded(running: true, _):
            switch health {
            case .ok(let health):
                return .running(opencodeConnected: health.opencodeConnected)
            case .diagnostic(let reason):
                // La lens è su e ha già detto cosa non va: aspettare i 15 s dell'avvio nasconderebbe il motivo.
                return .failed(diagnosticMessage(reason))
            case .unavailable:
                return timedOut ? .failed("in esecuzione ma /healthz non risponde") : .starting
            }
        case .unknown(let error):
            return .failed(error.localizedDescription)
        }
    }

    /// Lens di sviluppo (`LensTarget.local`): niente launchctl, conta solo /healthz.
    public static func resolve(local health: HealthFetch) -> ServiceState {
        switch health {
        case .ok(let health): .running(opencodeConnected: health.opencodeConnected)
        case .diagnostic(let reason): .failed(diagnosticMessage(reason))
        case .unavailable: .unreachable
        }
    }

    /// A un client non locale la lens dà già "database non utilizzabile (dettagli su questo
    /// computer)": il prefisso non va ripetuto.
    static func diagnosticMessage(_ reason: String) -> String {
        reason.hasPrefix("database non utilizzabile") ? reason : "database non utilizzabile: \(reason)"
    }
}

public enum ServiceAction: Equatable, Sendable {
    case start
    case stop
}

extension ServiceState {
    /// SF Symbol della card di stato.
    public var symbolName: String {
        switch self {
        case .running(opencodeConnected: true): "eye.fill"
        case .running(opencodeConnected: false), .starting, .checking, .restarting: "eye"
        case .stopped, .unreachable: "eye.slash"
        case .notInstalled, .failed: "eye.trianglebadge.exclamationmark"
        }
    }

    public var statusText: String {
        switch self {
        case .running(opencodeConnected: true): "OpenCode Lens — attivo (OpenCode collegato)"
        case .running(opencodeConnected: false): "OpenCode Lens — attivo (OpenCode non collegato)"
        case .starting: "OpenCode Lens — avvio in corso…"
        case .checking: "OpenCode Lens — verifica in corso…"
        case .stopped: "OpenCode Lens — fermo"
        case .notInstalled: "Non installato: installa opencode-lens con bash install.sh"
        case .failed(let message): "OpenCode Lens — errore: \(message)"
        case .unreachable: "OpenCode Lens — server di sviluppo non raggiungibile"
        case .restarting: "OpenCode Lens — si sta riavviando fuori dal Monitor"
        }
    }

    /// Avvia se fermo, Ferma se caricato in qualunque modo, niente se non installato o se la
    /// lens di sviluppo non risponde (non è il LaunchAgent: il Monitor non la controlla).
    public var primaryAction: ServiceAction? {
        switch self {
        case .notInstalled, .unreachable, .checking: nil
        case .stopped, .restarting: .start
        case .starting, .failed, .running: .stop
        }
    }

    public var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    /// Stato breve per l'intestazione del pannello, accanto al pallino di `statusDot`: con la lens
    /// attiva il collegamento a OpenCode lo dice solo il colore.
    public var shortText: String {
        switch self {
        case .running: "OpenCode"
        case .starting: "avvio in corso…"
        case .checking: "verifica…"
        case .stopped: "lens ferma"
        case .notInstalled: "lens non installata"
        case .failed: "errore"
        case .unreachable: "server non raggiungibile"
        case .restarting: "riavvio in corso…"
        }
    }

    /// Pallino dell'intestazione: verde con OpenCode collegato, arancio se la lens è attiva ma
    /// OpenCode no, grigio se la lens non è attiva, giallo se manca o è in errore.
    public var statusDot: StatusColor {
        switch self {
        case .running(opencodeConnected: true): .green
        case .running(opencodeConnected: false): .orange
        case .starting, .stopped, .unreachable, .checking, .restarting: .gray
        case .notInstalled, .failed: .warning
        }
    }

    /// Titolo della card mostrata al posto dei dati quando la lens non è attiva.
    public var cardTitle: String {
        switch self {
        case .running: "Lens attiva"
        case .starting: "Avvio in corso…"
        case .checking: "Verifica in corso…"
        case .stopped: "Lens ferma"
        case .failed: "Errore della lens"
        case .notInstalled: "Lens non installata"
        case .unreachable: "Server non raggiungibile"
        case .restarting: "Riavvio in corso…"
        }
    }
}

/// Note sotto lo stato quando la lens è stata fermata fuori dal Monitor e non è ripartita entro
/// `ServiceState.externalRestartGrace`. Esistono perché il salvataggio delle Impostazioni della
/// lens (`reloadService`) fa bootout + bootstrap senza `enable`: un job che il Monitor ha lasciato
/// disabilitato all'accesso launchd rifiuta di caricarlo, e la lens resta giù senza dire perché.
public enum ExternalStop {
    public static let disabledNote = "launchd non l'ha riavviata: è disabilitata all'accesso. Se hai appena salvato le Impostazioni della lens, premi Avvia."
    public static let otherNote = "Fermata fuori dal Monitor."
}
