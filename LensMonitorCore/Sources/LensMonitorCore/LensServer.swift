import Foundation

/// La lens che app e widget seguono: quella del LaunchAgent (produzione) o un'altra lens locale,
/// tipicamente un `npm run dev` su un'altra porta.
public enum LensTarget: Hashable, Sendable {
    case service
    case local(host: String, port: Int)

    /// Forma salvata nell'App Group: "service" o "host:porta" (l'host IPv6 contiene ":", quindi
    /// la porta è dopo l'ultimo).
    public var rawValue: String {
        switch self {
        case .service: "service"
        case .local(let host, let port): "\(host):\(port)"
        }
    }

    public init?(rawValue: String) {
        if rawValue == "service" {
            self = .service
            return
        }
        guard let colon = rawValue.lastIndex(of: ":"),
              let port = Int(rawValue[rawValue.index(after: colon)...]), (1...65535).contains(port)
        else { return nil }
        let host = String(rawValue[..<colon])
        guard LensConfig.isValidHost(host) else { return nil }
        self = .local(host: host, port: port)
    }
}

/// Una lens trovata in ascolto su questo Mac.
public struct LensServer: Equatable, Sendable {
    public let host: String
    public let port: Int
    /// Nome breve ricavato dal percorso di `src/main.js` (es. il nome del worktree).
    public let name: String
    /// La lens risponde 503 perché il suo database non si apre (modalità diagnostica): si può
    /// seguire lo stesso, e il pannello dirà il motivo.
    public let diagnostic: Bool

    public init(host: String, port: Int, name: String, diagnostic: Bool = false) {
        self.host = host
        self.port = port
        self.name = name
        self.diagnostic = diagnostic
    }

    /// Il percorso di `src/main.js` nella riga di comando, assoluto o relativo: `npm start` lancia
    /// `node src/main.js` dalla cartella del clone. `nil` se il processo non è una lens.
    public static func script(inCommand command: String) -> String? {
        command.split(separator: " ").map(String.init).last { $0 == "src/main.js" || $0.hasSuffix("/src/main.js") }
    }

    /// Un worktree di Claude Code (`.claude/worktrees/<nome>/src/main.js`) prende il nome del
    /// worktree; altrimenti la cartella che contiene `src` (il clone).
    /// Un percorso relativo si risolve con `cwd`, la cartella di lavoro del processo.
    public static func name(fromCommand command: String, cwd: String? = nil) -> String {
        guard var script = script(inCommand: command) else { return "node" }
        if !script.hasPrefix("/") {
            guard let cwd else { return "node" }
            script = cwd + "/" + script
        }
        let parts = script.split(separator: "/").map(String.init).filter { $0 != "." }
        if let worktrees = parts.firstIndex(of: "worktrees"), worktrees > 0, parts[worktrees - 1] == ".claude",
           worktrees + 1 < parts.count {
            return parts[worktrees + 1]
        }
        guard parts.count >= 3 else { return "node" }
        return parts[parts.count - 3]
    }
}

/// Una voce del menu Server delle impostazioni.
public struct LensServerOption: Equatable, Sendable, Identifiable {
    public let target: LensTarget
    public let title: String
    public let address: String
    /// `false` per la lens scelta in precedenza che ora non risponde.
    public let available: Bool

    public var id: LensTarget { target }

    /// Produzione sempre per prima, poi le lens trovate (quella sulla porta del LaunchAgent è già
    /// Produzione), infine la scelta corrente se non è più in ascolto, per non farla sparire dal menu.
    public static func list(service: LensEndpoint, discovered: [LensServer], selected: LensTarget) -> [LensServerOption] {
        var options = [LensServerOption(target: .service, title: "Produzione (LaunchAgent)", address: address(service.host, service.port), available: true)]
        for server in discovered where server.port != service.port {
            let target = LensTarget.local(host: server.host, port: server.port)
            guard !options.contains(where: { $0.target == target }) else { continue }
            let title = "Sviluppo — \(server.name)" + (server.diagnostic ? " (database non utilizzabile)" : "")
            options.append(LensServerOption(target: target, title: title, address: address(server.host, server.port), available: true))
        }
        if case .local(let host, let port) = selected, !options.contains(where: { $0.target == selected }) {
            options.append(LensServerOption(target: selected, title: "Sviluppo — non in ascolto", address: address(host, port), available: false))
        }
        return options
    }

    static func address(_ host: String, _ port: Int) -> String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}

public protocol LensDiscovering: Sendable {
    func servers() async -> [LensServer]
}

/// Cerca le lens locali: processi `node` in ascolto (lsof), riconosciuti da `src/main.js` nella
/// riga di comando (ps), assoluto o relativo, e confermati da /healthz senza token (anche con il
/// 503 della modalità diagnostica: la lens c'è, solo senza database). Una lens con `LENS_TOKEN`
/// risponde 401 e non compare: il token è noto solo per quella del LaunchAgent, che è sempre nel menu.
public struct LensDiscovery: LensDiscovering {
    public typealias Probe = @Sendable (_ host: String, _ port: Int) async -> HealthFetch

    private let runner: any CommandRunner
    private let probe: Probe

    public init(
        runner: any CommandRunner = ProcessCommandRunner(timeout: 5),
        probe: @escaping Probe = { host, port in await LensClient(host: host, port: port, token: nil).health() }
    ) {
        self.runner = runner
        self.probe = probe
    }

    public func servers() async -> [LensServer] {
        let lsof = await runner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "node", "-Fpn"])
        let listeners = Self.parseListeners(lsof.stdout)
        guard !listeners.isEmpty else { return [] }
        let pids = Set(listeners.map(\.pid)).sorted().map(String.init).joined(separator: ",")
        let ps = await runner.run("/bin/ps", ["-o", "pid=,command=", "-p", pids])
        let commands = Self.parseCommands(ps.stdout)
        let candidates = listeners.filter { commands[$0.pid].flatMap(LensServer.script(inCommand:)) != nil }
        // Solo per i percorsi relativi serve la cartella di lavoro, per dare un nome alla lens.
        let relative = Set(candidates.map(\.pid).filter { commands[$0].flatMap(LensServer.script(inCommand:))?.hasPrefix("/") == false })
        var cwds: [Int: String] = [:]
        if !relative.isEmpty {
            let list = relative.sorted().map(String.init).joined(separator: ",")
            cwds = Self.parseCwds(await runner.run("/usr/sbin/lsof", ["-a", "-p", list, "-d", "cwd", "-Fn"]).stdout)
        }
        var found: [LensServer] = []
        for listener in candidates {
            guard let command = commands[listener.pid],
                  !found.contains(where: { $0.host == listener.host && $0.port == listener.port })
            else { continue }
            let health = await probe(listener.host, listener.port)
            guard health != .unavailable else { continue }
            found.append(LensServer(
                host: listener.host, port: listener.port,
                name: LensServer.name(fromCommand: command, cwd: cwds[listener.pid]),
                diagnostic: health.lens == nil
            ))
        }
        return found.sorted { $0.port < $1.port }
    }

    struct Listener: Equatable {
        let pid: Int
        let host: String
        let port: Int
    }

    /// Output di `lsof -F pn`: una riga `p<pid>` seguita dalle righe `n<indirizzo>:<porta>` dei
    /// suoi socket. `*` e `0.0.0.0`/`::` (tutte le interfacce) si raggiungono su 127.0.0.1.
    static func parseListeners(_ output: String) -> [Listener] {
        var pid: Int?
        var result: [Listener] = []
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p") {
                pid = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid {
                let address = line.dropFirst()
                guard let colon = address.lastIndex(of: ":"), let port = Int(address[address.index(after: colon)...]) else { continue }
                var host = String(address[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                if host == "*" || host == "0.0.0.0" || host == "::" { host = LensConfig.defaultHost }
                let listener = Listener(pid: pid, host: host, port: port)
                if !result.contains(listener) { result.append(listener) }
            }
        }
        return result
    }

    /// Output di `lsof -d cwd -Fn`: righe `p<pid>` seguite da `n<cartella di lavoro>`.
    static func parseCwds(_ output: String) -> [Int: String] {
        var pid: Int?
        var result: [Int: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p") {
                pid = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// Output di `ps -o pid=,command=`: pid e riga di comando.
    static func parseCommands(_ output: String) -> [Int: String] {
        var result: [Int: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop { $0 == " " }
            guard let space = trimmed.firstIndex(of: " "), let pid = Int(trimmed[..<space]) else { continue }
            result[pid] = String(trimmed[space...].drop { $0 == " " })
        }
        return result
    }
}
