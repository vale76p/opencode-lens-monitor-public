import Foundation

public enum LoadState: Equatable, Sendable {
    case notLoaded
    case loaded(running: Bool, pid: Int?)
    /// `launchctl print` fallito per un motivo diverso da "servizio non trovato" (113), anche per
    /// il timeout del runner: lo stato vero non si sa, e non va scambiato per "fermo".
    case unknown(LaunchctlError)
}

/// `launchctl` uscito con exit ≠ 0. Il messaggio usa solo la prima riga di stderr.
public struct LaunchctlError: Error, Equatable, Sendable, LocalizedError {
    public let command: String
    public let status: Int32
    public let stderr: String

    public init(command: String, status: Int32, stderr: String) {
        self.command = command
        self.status = status
        self.stderr = stderr
    }

    public var errorDescription: String? {
        let detail = stderr.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return "launchctl \(command) non riuscito (\(status))" + (detail.isEmpty ? "" : ": \(detail)")
    }
}

/// Controllo del servizio launchd della lens.
public protocol ServiceControlling: Sendable {
    var isInstalled: Bool { get }
    func status() async -> LoadState
    func isEnabledAtLogin() async -> Bool
    func start() async throws
    func stop() async throws
    func setEnabledAtLogin(_ enabled: Bool) async throws
}

/// Gli stessi comandi di `opencode-lens service` (src/service.js), nel dominio gui/<uid>.
public struct LaunchAgentController: ServiceControlling {
    static let launchctl = "/bin/launchctl"

    private let runner: any CommandRunner
    private let label: String
    private let uid: uid_t
    private let plistURL: URL
    private let fileExists: @Sendable (String) -> Bool

    public init(
        runner: any CommandRunner = ProcessCommandRunner(),
        label: String = Paths.label,
        uid: uid_t = getuid(),
        plistURL: URL = Paths.plist,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.runner = runner
        self.label = label
        self.uid = uid
        self.plistURL = plistURL
        self.fileExists = fileExists
    }

    private var domain: String { "gui/\(uid)" }
    private var target: String { "\(domain)/\(label)" }

    public var isInstalled: Bool { fileExists(plistURL.path) }

    /// Exit di `launchctl print` per un servizio non caricato.
    static let notFound: Int32 = 113

    public func status() async -> LoadState {
        let result = await runner.run(Self.launchctl, ["print", target])
        if result.status == Self.notFound { return .notLoaded }
        guard result.status == 0 else {
            return .unknown(LaunchctlError(command: "print", status: result.status, stderr: result.stderr))
        }
        let info = LaunchctlParser.parsePrint(result.stdout)
        return .loaded(running: info.running, pid: info.pid)
    }

    public func isEnabledAtLogin() async -> Bool {
        let result = await runner.run(Self.launchctl, ["print-disabled", domain])
        return LaunchctlParser.parseDisabled(result.stdout, label: label) != true
    }

    public func start() async throws {
        switch await status() {
        case .loaded:
            try await exec(["kickstart", target])
            return
        case .unknown(let error):
            throw error
        case .notLoaded:
            break
        }
        if await isEnabledAtLogin() {
            do {
                try await exec(["bootstrap", domain, plistURL.path])
            } catch {
                // Senza riga in print-disabled il servizio risulta abilitato, ma launchd può
                // considerarlo disabilitato (Disabled nel plist): si riprova abilitandolo.
                guard (try? await exec(["enable", target])) != nil,
                      (try? await bootstrapOrLoaded()) != nil
                else { throw error }
            }
            return
        }
        // launchd rifiuta il bootstrap di un servizio disabilitato: lo si abilita
        // solo per l'avvio e lo si disabilita subito, così non riparte al login.
        try await exec(["enable", target])
        do {
            try await bootstrapOrLoaded()
        } catch {
            try? await exec(["disable", target])
            throw error
        }
        try await exec(["disable", target])
    }

    public func stop() async throws {
        switch await status() {
        case .notLoaded:
            return
        case .unknown(let error):
            throw error
        case .loaded:
            break
        }
        do {
            try await exec(["bootout", target])
        } catch {
            // bootout aspetta l'uscita del processo e può superare il watchdog del runner mentre
            // launchd lo scarica comunque: se nel frattempo è sparito, non è un errore.
            if await status() == .notLoaded { return }
            throw error
        }
    }

    public func setEnabledAtLogin(_ enabled: Bool) async throws {
        try await exec([enabled ? "enable" : "disable", target])
    }

    /// Il salvataggio delle impostazioni della lens usa un helper che ritenta `launchctl bootstrap`
    /// fino a 10 volte: se Avvia arriva nel frattempo, il nostro `enable` fa riuscire il suo e il
    /// nostro bootstrap fallisce ("già caricato"). Se il servizio risulta caricato non è un errore.
    private func bootstrapOrLoaded() async throws {
        do {
            try await exec(["bootstrap", domain, plistURL.path])
        } catch {
            if case .loaded = await status() { return }
            throw error
        }
    }

    private func exec(_ arguments: [String]) async throws {
        let result = await runner.run(Self.launchctl, arguments)
        guard result.status == 0 else {
            throw LaunchctlError(command: arguments[0], status: result.status, stderr: result.stderr)
        }
    }
}
