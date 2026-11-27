import Foundation

/// Ritmo del polling dell'app. Un giro costa pochi millisecondi di CPU ma a 5 s fissi sono ~2400
/// risvegli all'ora anche con la lens ferma o in errore, che non cambia da sola: il ritmo segue
/// quanto lo stato è "vivo" e rallenta man mano che resta uguale.
public enum PollPacing {
    /// Si sta aspettando che qualcosa cambi (avvio, riavvio, azione dell'utente).
    public static let active: TimeInterval = 5
    /// Lens in esecuzione, o ferma da poco.
    public static let calm: TimeInterval = 15
    public static let maxBackoff: TimeInterval = 60
    /// Dopo un'azione dell'utente (Avvia/Ferma/Riavvia, apertura del pannello) si torna a `active`
    /// per questo tempo: il pannello non dice quando si chiude, quindi la finestra è a tempo.
    public static let boostWindow: TimeInterval = 30

    /// Famiglie di stati che condividono lo stesso ritmo; il tempo passato nella stessa famiglia
    /// (`stableFor`) fa scendere il ritmo, un cambio di famiglia lo riporta all'inizio.
    public enum Group: Equatable, Sendable {
        case waiting, running, failing, stopped

        public init(_ state: ServiceState) {
            switch state {
            case .checking, .starting, .restarting: self = .waiting
            case .running: self = .running
            case .failed, .unreachable: self = .failing
            case .stopped, .notInstalled: self = .stopped
            }
        }
    }

    /// Secondi fino al prossimo refresh dello stato.
    /// - `stableFor`: da quanto lo stato è nella stessa famiglia.
    /// - `sinceUserAction`: da quanto l'utente ha agito; `nil` se mai.
    /// - `untilUsageRefresh`: quanto manca al refresh dei dati con la lens in esecuzione, perché un
    ///   ritmo lento non lo ritardi (conta solo con `.running`).
    public static func interval(
        group: Group,
        busy: Bool,
        stableFor: TimeInterval,
        sinceUserAction: TimeInterval? = nil,
        untilUsageRefresh: TimeInterval? = nil
    ) -> TimeInterval {
        let boosted = busy || (sinceUserAction.map { $0 < boostWindow } ?? false)
        var seconds: TimeInterval
        if boosted {
            seconds = active
        } else {
            switch group {
            case .waiting: seconds = active
            case .running: seconds = calm
            // un errore può rientrare da solo (KeepAlive, riavvio della lens): prima si guarda spesso
            case .failing: seconds = backoff(stableFor, [(30, active), (120, calm), (300, 30)])
            // fermo, o non installato: cambia solo se l'utente fa qualcosa, e allora c'è `boostWindow`
            case .stopped: seconds = backoff(stableFor, [(300, calm), (900, 30)])
            }
        }
        if group == .running, let untilUsageRefresh {
            seconds = min(seconds, max(untilUsageRefresh, 1))
        }
        return seconds
    }

    private static func backoff(_ stableFor: TimeInterval, _ steps: [(until: TimeInterval, interval: TimeInterval)]) -> TimeInterval {
        steps.first { stableFor < $0.until }?.interval ?? maxBackoff
    }
}
