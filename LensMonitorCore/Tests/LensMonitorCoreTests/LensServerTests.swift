import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct LensServerTests {
    @Test func targetRawValue() {
        #expect(LensTarget.service.rawValue == "service")
        #expect(LensTarget(rawValue: "service") == .service)
        #expect(LensTarget(rawValue: "127.0.0.1:4790") == .local(host: "127.0.0.1", port: 4790))
        #expect(LensTarget(rawValue: "::1:4790") == .local(host: "::1", port: 4790))
        #expect(LensTarget.local(host: "::1", port: 4790).rawValue == "::1:4790")
        #expect(LensTarget(rawValue: "") == nil)
        #expect(LensTarget(rawValue: ":4790") == nil)
        #expect(LensTarget(rawValue: "127.0.0.1:0") == nil)
        #expect(LensTarget(rawValue: "127.0.0.1") == nil)
        #expect(LensTarget(rawValue: "my host:4790") == nil)
        #expect(LensTarget(rawValue: "a/b:4790") == nil)
        #expect(LensTarget(rawValue: "fe80::1%en0:4790") == .local(host: "fe80::1%en0", port: 4790))
    }

    @Test func nomeDalComando() {
        #expect(LensServer.name(fromCommand: "/opt/homebrew/Cellar/node/26.11.1/bin/node --disable-warning=ExperimentalWarning /Users/v/GitHub/opencode-lens/.claude/worktrees/lens-live/src/main.js") == "lens-live")
        #expect(LensServer.name(fromCommand: "/opt/homebrew/opt/node/bin/node /Users/u/src/opencode-lens/src/main.js") == "opencode-lens")
        #expect(LensServer.name(fromCommand: "node /x/libexec/src/main.js") == "libexec")
        #expect(LensServer.name(fromCommand: "node /Users/v/code/lens-clone/src/main.js") == "lens-clone")
        #expect(LensServer.name(fromCommand: "node server.js") == "node")
        // npm start: percorso relativo, risolto con la cartella di lavoro
        #expect(LensServer.name(fromCommand: "node --disable-warning=ExperimentalWarning src/main.js", cwd: "/Users/v/GitHub/opencode-lens") == "opencode-lens")
        #expect(LensServer.name(fromCommand: "node ./src/main.js", cwd: "/r/.claude/worktrees/lens-live") == "lens-live")
        #expect(LensServer.name(fromCommand: "node src/main.js") == "node")
        #expect(LensServer.script(inCommand: "node xsrc/main.js") == nil)
    }

    @Test func opzioniConProduzionePrima() {
        let service = LensEndpoint(port: 4777, token: "t")
        let discovered = [
            LensServer(host: "127.0.0.1", port: 4777, name: "opencode-lens"),
            LensServer(host: "127.0.0.1", port: 4790, name: "lens-live"),
        ]
        let options = LensServerOption.list(service: service, discovered: discovered, selected: .service)
        #expect(options.map(\.title) == ["Produzione (LaunchAgent)", "Sviluppo — lens-live"])
        #expect(options.map(\.address) == ["127.0.0.1:4777", "127.0.0.1:4790"])
        #expect(options.map(\.target) == [.service, .local(host: "127.0.0.1", port: 4790)])
        #expect(options.allSatisfy { $0.available })
    }

    @Test func sceltaNonPiuInAscoltoResta() {
        let options = LensServerOption.list(service: LensEndpoint(port: 4777, token: nil), discovered: [], selected: .local(host: "::1", port: 4790))
        #expect(options.count == 2)
        #expect(options[1].target == .local(host: "::1", port: 4790))
        #expect(options[1].address == "[::1]:4790")
        #expect(options[1].available == false)
    }

    @Test func endpointPerTarget() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "lens-server-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let plist: [String: Any] = ["EnvironmentVariables": ["LENS_PORT": "4800", "LENS_TOKEN": "segreto"]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        #expect(LensConfig.endpoint(for: .service, plistAt: url, environment: [:]) == LensEndpoint(port: 4800, token: "segreto"))
        #expect(LensConfig.endpoint(for: .local(host: "127.0.0.1", port: 4790), plistAt: url, environment: [:]) == LensEndpoint(port: 4790, token: nil))
    }

    @Test func parseListeners() {
        let output = "p42365\nn127.0.0.1:4777\np66104\nn*:4790\nn[::1]:4791\nn[::]:4792\np1\nnabc\n"
        #expect(LensDiscovery.parseListeners(output) == [
            .init(pid: 42365, host: "127.0.0.1", port: 4777),
            .init(pid: 66104, host: "127.0.0.1", port: 4790),
            .init(pid: 66104, host: "::1", port: 4791),
            .init(pid: 66104, host: "127.0.0.1", port: 4792),
        ])
    }

    @Test func parseCommands() {
        let output = "42365 /opt/homebrew/opt/node/bin/node /x/src/main.js\n  700 node  a b\nnope\n"
        #expect(LensDiscovery.parseCommands(output) == [42365: "/opt/homebrew/opt/node/bin/node /x/src/main.js", 700: "node  a b"])
    }

    @Test func discoveryTieneSoloLeLensCheRispondono() async {
        let runner = FakeRunner()
        runner.on(["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "node", "-Fpn"],
                  CommandResult(status: 0, stdout: "p10\nn127.0.0.1:4777\np20\nn127.0.0.1:4790\nn127.0.0.1:4791\np30\nn127.0.0.1:5173\n"))
        runner.on(["-o", "pid=,command=", "-p", "10,20,30"],
                  CommandResult(status: 0, stdout: "10 node /Users/u/opencode-lens/src/main.js\n20 node /r/.claude/worktrees/lens-live/src/main.js\n30 node vite\n"))
        // 4791: lo stesso processo dev ascolta anche su un'altra porta che non è la dashboard.
        let discovery = LensDiscovery(runner: runner) { _, port in port != 4791 ? .ok(LensHealth(opencode: "connected")) : .unavailable }
        #expect(await discovery.servers() == [
            LensServer(host: "127.0.0.1", port: 4777, name: "opencode-lens"),
            LensServer(host: "127.0.0.1", port: 4790, name: "lens-live"),
        ])
    }

    /// Una lens di sviluppo con il database che non si apre risponde 503 ed è comunque una lens:
    /// resta nel menu Server, segnata, così si vede il motivo nel pannello scegliendola.
    @Test func discoveryTieneLaLensDiagnostica() async {
        let runner = FakeRunner()
        runner.on(["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "node", "-Fpn"],
                  CommandResult(status: 0, stdout: "p20\nn127.0.0.1:4790\np21\nn127.0.0.1:4791\n"))
        runner.on(["-o", "pid=,command=", "-p", "20,21"],
                  CommandResult(status: 0, stdout: "20 node /r/.claude/worktrees/lens-live/src/main.js\n21 node /r/.claude/worktrees/lens-rotta/src/main.js\n"))
        let discovery = LensDiscovery(runner: runner) { _, port in port == 4791 ? .diagnostic(reason: "file rovinato") : .ok(LensHealth(opencode: "connected")) }
        #expect(await discovery.servers() == [
            LensServer(host: "127.0.0.1", port: 4790, name: "lens-live"),
            LensServer(host: "127.0.0.1", port: 4791, name: "lens-rotta", diagnostic: true),
        ])
        let options = LensServerOption.list(service: LensEndpoint(port: 4777, token: nil), discovered: await discovery.servers(), selected: .service)
        #expect(options.map(\.title) == ["Produzione (LaunchAgent)", "Sviluppo — lens-live", "Sviluppo — lens-rotta (database non utilizzabile)"])
        #expect(options.allSatisfy { $0.available })
    }

    @Test func discoveryConNpmStart() async {
        let runner = FakeRunner()
        runner.on(["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "node", "-Fpn"], CommandResult(status: 0, stdout: "p40\nn127.0.0.1:4778\n"))
        runner.on(["-o", "pid=,command=", "-p", "40"], CommandResult(status: 0, stdout: "40 node --disable-warning=ExperimentalWarning src/main.js\n"))
        runner.on(["-a", "-p", "40", "-d", "cwd", "-Fn"], CommandResult(status: 0, stdout: "p40\nfcwd\nn/Users/v/GitHub/opencode-lens\n"))
        #expect(await LensDiscovery(runner: runner) { _, _ in .ok(LensHealth(opencode: "connected")) }.servers() == [LensServer(host: "127.0.0.1", port: 4778, name: "opencode-lens")])
    }

    @Test func discoverySenzaNodeNonChiamaPs() async {
        let runner = FakeRunner()
        runner.on(["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "node", "-Fpn"], CommandResult(status: 1))
        #expect(await LensDiscovery(runner: runner) { _, _ in .ok(LensHealth(opencode: "connected")) }.servers() == [])
        #expect(runner.calls.count == 1)
    }
}
