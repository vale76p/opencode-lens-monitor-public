import Foundation

/// Se chi ascolta sulla porta della lens è il suo job.
public enum ListenerCheck: Equatable, Sendable {
    /// Ascolta solo il processo del job: il token può andare.
    case verified
    /// Sulla porta ascolta un altro processo (o anche un altro): il token non deve arrivargli.
    case foreign
    /// Non si sa: nessuno ascolta ancora, o `lsof` non ha risposto. Vale come `foreign` per il token.
    case unverified
}

/// Prima di mandare `LENS_TOKEN` a 127.0.0.1:<porta> il Monitor controlla che il processo in ascolto
/// sia quello del job: una porta presa da un altro programma (lens che non è riuscita a legarsi,
/// servizio qualunque dello stesso utente) altrimenti riceverebbe il Bearer a ogni richiesta.
public protocol ListenerVerifying: Sendable {
    /// `pid`: quello di `launchctl print` del job; `port`: quella a cui andrebbero le richieste.
    func check(pid: Int, port: Int) async -> ListenerCheck
}

/// Nessun controllo: per i test e per chi non vuole `lsof`. L'app usa `LsofListenerVerifier`.
public struct NoListenerCheck: ListenerVerifying {
    public init() {}
    public func check(pid: Int, port: Int) async -> ListenerCheck { .verified }
}

/// `lsof -nP -iTCP:<porta> -sTCP:LISTEN -Fp` (~30 ms): righe `p<pid>`, una per processo in ascolto.
///
/// Fallimenti: se `lsof` non parte, scade o non dà nessun pid il risultato è `.unverified`, cioè
/// **chiuso**: niente token, e la lens sembra non rispondere (per `ServiceState.resolve` diventa
/// "in esecuzione ma /healthz non risponde" dopo 15 s, e il giro dopo si riprova). Meglio un falso
/// allarme temporaneo che il token a un estraneo; l'esito non viene memorizzato.
///
/// Con `LENS_MONITOR_PORT` nell'ambiente l'utente ha scelto a mano la porta (per provare un'altra lens,
/// README "Prove con un'altra lens") e il processo non è per definizione quello del job: non si
/// controlla.
public struct LsofListenerVerifier: ListenerVerifying {
    private let runner: any CommandRunner
    private let portOverridden: Bool

    public init(
        runner: any CommandRunner = ProcessCommandRunner(timeout: 5),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.runner = runner
        self.portOverridden = LensConfig.portOverride(environment: environment) != nil
    }

    public func check(pid: Int, port: Int) async -> ListenerCheck {
        if portOverridden { return .verified }
        let result = await runner.run("/usr/sbin/lsof", ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"])
        let pids = Set(result.stdout.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("p") ? Int(line.dropFirst()) : nil
        })
        if pids.isEmpty { return .unverified }
        return pids == [pid] ? .verified : .foreign
    }
}
