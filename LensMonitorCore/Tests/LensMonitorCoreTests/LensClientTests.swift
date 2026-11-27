import Foundation
import Testing
@testable import LensMonitorCore

/// Registra le richieste e risponde con status e corpo fissi, oppure con un errore.
final class FakeHTTP: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    var status = 200
    var body = #"{"ok":true,"opencode":"connected"}"#
    var error: (any Error)?

    var requests: [URLRequest] { lock.withLock { recorded } }

    var fetch: LensClient.Fetch {
        { request in
            try self.lock.withLock {
                self.recorded.append(request)
                if let error = self.error { throw error }
                let response = HTTPURLResponse(url: request.url!, statusCode: self.status, httpVersion: nil, headerFields: nil)!
                return (Data(self.body.utf8), response)
            }
        }
    }
}

final class PortBox: @unchecked Sendable {
    var value: Int
    init(_ value: Int) { self.value = value }
}

@Suite struct LensClientTests {
    let http = FakeHTTP()

    func client(port: Int = 4777) -> LensClient {
        LensClient(port: { port }, fetch: http.fetch)
    }

    @Test func healthCollegato() async {
        let health = await client().health()
        #expect(health == .ok(LensHealth(opencode: "connected")))
        #expect(health.lens?.opencodeConnected == true)
        #expect(http.requests.first?.url?.absoluteString == "http://127.0.0.1:4777/healthz")
        #expect(http.requests.first?.timeoutInterval == 2)
    }

    @Test func healthOpenCodeScollegato() async {
        http.body = #"{"ok":true,"opencode":"disconnected"}"#
        #expect(await client().health().lens?.opencodeConnected == false)
    }

    /// Lens ≥ 0.30.0 con il database che non si apre: resta su e dice perché con un 503.
    @Test func health503DiagnosticoDaIlMotivo() async {
        http.status = 503
        http.body = #"{"ok":false,"error":"database con schema 12, più nuovo di questa lens (11): aggiorna opencode-lens"}"#
        #expect(await client().health() == .diagnostic(reason: "database con schema 12, più nuovo di questa lens (11): aggiorna opencode-lens"))
    }

    /// Un 503 di altro tipo (proxy, corpo vuoto, `ok` non falso) non è la modalità diagnostica.
    @Test func health503SenzaJsonNonDisponibile() async {
        http.status = 503
        http.body = "Service Unavailable"
        #expect(await client().health() == .unavailable)
        http.body = #"{"ok":true,"error":"x"}"#
        #expect(await client().health() == .unavailable)
        http.body = #"{"ok":false}"#
        #expect(await client().health() == .unavailable)
    }

    @Test func statusDiversoDa200NonDisponibile() async {
        http.status = 500
        #expect(await client().health() == .unavailable)
        http.status = 401
        #expect(await client().health() == .unavailable)
    }

    @Test func jsonNonValidoNonDisponibile() async {
        http.body = "<html>"
        #expect(await client().health() == .unavailable)
    }

    @Test func erroreDiReteNonDisponibile() async {
        http.error = URLError(.cannotConnectToHost)
        #expect(await client().health() == .unavailable)
    }

    /// Con il modulo IBM Bob acceso /healthz aggiunge `bob`; il Monitor non lo usa, ma la decodifica non cambia.
    @Test func healthConBobResteCompatibile() async throws {
        http.body = #"{"ok":true,"opencode":"connected","bob":"connected"}"#
        #expect(await client().health() == .ok(LensHealth(opencode: "connected")))
        #expect(try JSONDecoder().decode(LensHealth.self, from: Data(#"{"ok":true,"opencode":"disconnected"}"#.utf8)) == LensHealth(opencode: "disconnected"))
    }

    @Test func senzaTokenNessunaAutorizzazione() async {
        _ = await client().health()
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func conLensTokenInviaBearer() async {
        let client = LensClient(port: { 4777 }, token: { "segreto-di-prova-1234" }, fetch: http.fetch)
        #expect(await client.health() == .ok(LensHealth(opencode: "connected")))
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer segreto-di-prova-1234")
        #expect(client.dashboardURL.absoluteString == "http://127.0.0.1:4777")
    }

    /// URL e token di una richiesta vengono dallo stesso endpoint: se la scelta cambiasse tra le
    /// due letture, il token di produzione andrebbe alla lens di sviluppo.
    @Test func unSoloEndpointPerRichiesta() async {
        let calls = PortBox(0)
        let client = LensClient(endpoint: {
            calls.value += 1
            return calls.value == 1 ? LensEndpoint(port: 4790, token: nil) : LensEndpoint(port: 4777, token: "segreto-di-prova-1234")
        }, fetch: http.fetch)
        _ = await client.health()
        #expect(calls.value == 1)
        #expect(http.requests.first?.url?.port == 4790)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func versioneDaApiAbout() async {
        http.body = #"{"lens":{"version":"0.9.0","appDir":"/Users/u/Applications/opencode-lens","pid":42365},"files":{}}"#
        #expect(await LensClient(port: 4777, token: "segreto", fetch: http.fetch).version() == "0.9.0")
        #expect(http.requests.last?.url?.path() == "/api/about")
        #expect(http.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer segreto")
        http.status = 404
        #expect(await LensClient(port: 4777, token: nil, fetch: http.fetch).version() == nil)
    }

    @Test func portaRilettaAOgniChiamata() async {
        let port = PortBox(4777)
        let client = LensClient(port: { port.value }, fetch: http.fetch)
        _ = await client.health()
        port.value = 4800
        _ = await client.health()
        #expect(http.requests.map { $0.url!.absoluteString } == [
            "http://127.0.0.1:4777/healthz",
            "http://127.0.0.1:4800/healthz",
        ])
        #expect(client.dashboardURL.absoluteString == "http://127.0.0.1:4800")
    }
    @Test func budgetConToken() async {
        http.body = BudgetReport.sampleJSON
        let result = await LensClient(port: 4777, token: "segreto", fetch: http.fetch).budget()
        #expect(result == .ok(.sample))
        let request = http.requests.first
        #expect(request?.url?.absoluteString == "http://127.0.0.1:4777/api/budget")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer segreto")
        #expect(request?.timeoutInterval == 2)
    }

    @Test func budgetErroriSonoNonDisponibili() async {
        http.status = 404
        #expect(await client().budget() == .unavailable)
        http.status = 500
        #expect(await client().budget() == .unavailable)
        http.status = 200
        http.body = "{}"
        #expect(await client().budget() == .unavailable)
        http.error = URLError(.cannotConnectToHost)
        #expect(await client().budget() == .unavailable)
    }

    @Test func modelliDelGiorno() async {
        http.body = #"[{"key":"opencode/claude-opus-4-8#max","steps":86,"failed":0,"cost":0,"tokens":{"input":1200,"output":300,"reasoning":50,"cacheRead":9000,"cacheWrite":0,"total":10550},"last":1792047600000},{"key":"openai/gpt-5.5","steps":3,"last":null}]"#
        let models = await LensClient(port: 4777, token: "segreto", fetch: http.fetch).models(since: Date(timeIntervalSince1970: 1_791_756_000))
        #expect(models == [
            ModelUsage(key: "opencode/claude-opus-4-8#max", last: Date(timeIntervalSince1970: 1_792_047_600), tokensIn: 1_200, tokensOut: 350, tokensTotal: 10_550),
            ModelUsage(key: "openai/gpt-5.5", last: nil),
        ])
        let request = http.requests.first
        #expect(request?.url?.path() == "/api/breakdown")
        #expect(request?.url?.query() == "by=model&from=1791756000000")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer segreto")
    }

    @Test func modelliNonDisponibili() async {
        http.status = 500
        #expect(await client().models(since: .now) == nil)
        http.status = 200
        http.body = "nope"
        #expect(await client().models(since: .now) == nil)
    }

    @Test func tokenOraPerOraDiUnModello() async {
        http.body = #"{"unit":"hour","labels":["a","b","c"],"series":[{"key":"lmstudio/qwen","values":[1,2,3]},{"key":"lmstudio/qwen#max","values":[10,0,0]},{"key":"altri","values":[5,5,5]}]}"#
        let from = Date(timeIntervalSince1970: 1_792_015_200)
        let values = await client().hourlyTokens(model: "lmstudio/qwen", from: from, to: from.addingTimeInterval(86_400))
        // una lens vecchia ignora model= e dà tutte le serie: si sommano le varianti del modello
        #expect(values == [11, 2, 3])
        let request = http.requests.first
        #expect(request?.url?.path() == "/api/timeseries")
        #expect(request?.url?.query() == "from=1792015200000&to=1792101600000&metric=tokens&by=model&model=lmstudio/qwen")
        #expect(await client().hourlyTokens(model: "x/nessuno", from: from, to: from) == [0, 0, 0])
        http.status = 500
        #expect(await client().hourlyTokens(model: "lmstudio/qwen", from: from, to: from) == nil)
    }

    @Test func endpointCorrente() {
        #expect(LensClient(port: 4800, token: "t").endpoint == LensEndpoint(port: 4800, token: "t"))
        #expect(LensClient(port: 4777, token: nil).endpoint == LensEndpoint(port: 4777, token: nil))
    }

    /// L'host di LENS_HOST: IPv6 tra parentesi quadre, anche nell'URL della dashboard.
    @Test func hostNellUrl() async {
        _ = await LensClient(host: "::1", port: 4777, token: nil, fetch: http.fetch).budget()
        #expect(http.requests.last?.url?.absoluteString == "http://[::1]:4777/api/budget")
        _ = await LensClient(host: "192.168.1.10", port: 4800, token: nil, fetch: http.fetch).health()
        #expect(http.requests.last?.url?.absoluteString == "http://192.168.1.10:4800/healthz")
        #expect(LensClient(host: "::1", port: 4777, token: nil).dashboardURL.absoluteString == "http://[::1]:4777")
        #expect(LensClient(host: "::1", port: 4777, token: nil).endpoint == LensEndpoint(host: "::1", port: 4777, token: nil))
        #expect(LensClient(port: 4777, token: nil).endpoint.host == "127.0.0.1")
        // interfaccia IPv6 codificata; un host che non forma un URL non fa chiudere l'app
        #expect(LensClient(host: "fe80::1%en0", port: 4777, token: nil).dashboardURL.absoluteString == "http://[fe80::1%25en0]:4777")
        #expect(LensClient(host: "my host", port: 4777, token: nil).dashboardURL.absoluteString == "http://127.0.0.1:4777")
    }

    /// Nel browser la dashboard si apre con il token, codificato tutto tranne i caratteri non
    /// riservati; senza token resta l'indirizzo nudo.
    @Test func browserURLConIlToken() {
        #expect(LensClient(port: 4777, token: "abc-_XYZ09").browserURL.absoluteString == "http://127.0.0.1:4777/?token=abc-_XYZ09")
        #expect(LensClient(port: 4777, token: "a+b/c=&d e").browserURL.absoluteString == "http://127.0.0.1:4777/?token=a%2Bb%2Fc%3D%26d%20e")
        #expect(LensClient(host: "::1", port: 4800, token: "t").browserURL.absoluteString == "http://[::1]:4800/?token=t")
        #expect(LensClient(port: 4777, token: nil).browserURL.absoluteString == "http://127.0.0.1:4777")
        #expect(LensClient(port: 4777, token: "").browserURL.absoluteString == "http://127.0.0.1:4777")
        // dashboardURL resta senza token: è anche l'indirizzo mostrato nel pannello
        #expect(LensClient(port: 4777, token: "segreto").dashboardURL.absoluteString == "http://127.0.0.1:4777")
    }

    /// La sessione vera non si prova senza rete: qui si fissano scadenza totale (una lens che
    /// risponde a gocce non deve congelare il polling), inattività e il rifiuto dei redirect.
    @Test func sessioneConScadenzaTotaleESenzaRedirect() {
        let config = LensClient.session.configuration
        #expect(config.timeoutIntervalForRequest == 2)
        #expect(config.timeoutIntervalForResource == 15)
        #expect(LensClient.session.delegate is LensClient.NoRedirect)
        let url = URL(string: "http://127.0.0.1:1/x")!
        let task = LensClient.session.dataTask(with: url)
        let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let followed = PortBox(1)
        LensClient.NoRedirect().urlSession(LensClient.session, task: task, willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: url)) { request in
            followed.value = request == nil ? 0 : 1
        }
        #expect(followed.value == 0)
    }

    /// Il corpo si legge a pezzi e oltre il tetto si butta, anche quando il Content-Length
    /// dichiarato è piccolo o manca.
    @Test func corpoOltreIlTettoScartato() async throws {
        func stream(_ count: Int) -> AsyncStream<UInt8> {
            AsyncStream { continuation in
                for _ in 0..<count { continuation.yield(0x61) }
                continuation.finish()
            }
        }
        #expect(try await LensClient.collect(stream(10), expected: -1, limit: 10) == Data(repeating: 0x61, count: 10))
        #expect(try await LensClient.collect(stream(3), expected: 3, limit: 10).count == 3)
        await #expect(throws: URLError(.dataLengthExceedsMaximum)) {
            try await LensClient.collect(stream(11), expected: -1, limit: 10)
        }
        await #expect(throws: URLError(.dataLengthExceedsMaximum)) {
            try await LensClient.collect(stream(0), expected: 11, limit: 10)
        }
        #expect(LensClient.maxResponseBytes == 8 << 20)
    }

    @Test func lensMonitorPortHaLaPrecedenza() {
        let missing = URL(fileURLWithPath: "/tmp/inesistente-\(UUID()).plist")
        #expect(LensConfig.port(fromPlistAt: missing, environment: ["LENS_MONITOR_PORT": "4778"]) == 4778)
        #expect(LensConfig.port(fromPlistAt: missing, environment: ["LENS_MONITOR_PORT": "0"]) == 4777)
        #expect(LensConfig.port(fromPlistAt: missing, environment: ["LENS_MONITOR_PORT": "x"]) == 4777)
        #expect(LensConfig.port(fromPlistAt: missing, environment: [:]) == 4777)
    }
}

@Suite struct LensConfigTests {
    func plist(_ contents: [String: Any]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lens-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    @Test func portaDalPlist() throws {
        let url = try plist(["Label": "local.opencode-lens", "EnvironmentVariables": ["LENS_PORT": "4800"]])
        #expect(LensConfig.port(fromPlistAt: url) == 4800)
    }

    @Test func senzaLensPortUsaIlDefault() throws {
        let url = try plist(["Label": "local.opencode-lens"])
        #expect(LensConfig.port(fromPlistAt: url) == 4777)
    }

    @Test(arguments: ["abc", "0", "70000", ""])
    func portaNonValidaUsaIlDefault(_ value: String) throws {
        let url = try plist(["EnvironmentVariables": ["LENS_PORT": value]])
        #expect(LensConfig.port(fromPlistAt: url) == 4777)
    }

    /// Indirizzi "tutte le interfacce" o assenti diventano 127.0.0.1; gli altri si usano come sono.
    @Test(arguments: [
        (nil, "127.0.0.1"), ("", "127.0.0.1"), ("0.0.0.0", "127.0.0.1"), ("::", "127.0.0.1"),
        ("127.0.0.1", "127.0.0.1"), ("localhost", "localhost"), ("::1", "::1"),
        ("192.168.1.10", "192.168.1.10"), (" 10.0.0.2 ", "10.0.0.2"), ("[::1]", "::1"),
        ("127.0.0.1\n", "127.0.0.1"), ("my host", "127.0.0.1"), ("box.local/x?", "127.0.0.1"),
        ("fe80::1%en0", "fe80::1%en0"),
    ] as [(String?, String)])
    func hostDalPlist(value: String?, expected: String) throws {
        var env = ["LENS_PORT": "4777"]
        if let value { env["LENS_HOST"] = value }
        #expect(LensConfig.host(fromPlistAt: try plist(["EnvironmentVariables": env])) == expected)
    }

    @Test func tokenDalPlist() throws {
        let url = try plist(["EnvironmentVariables": ["LENS_PORT": "4777", "LENS_TOKEN": "segreto-di-prova-1234"]])
        #expect(LensConfig.token(fromPlistAt: url) == "segreto-di-prova-1234")
    }

    @Test func tokenAssenteOVuoto() throws {
        #expect(LensConfig.token(fromPlistAt: try plist(["EnvironmentVariables": ["LENS_PORT": "4777"]])) == nil)
        #expect(LensConfig.token(fromPlistAt: try plist(["EnvironmentVariables": ["LENS_TOKEN": ""]])) == nil)
        #expect(LensConfig.token(fromPlistAt: URL(fileURLWithPath: "/nonexistent/x.plist")) == nil)
    }

    @Test func plistAssenteOMalformato() throws {
        #expect(LensConfig.port(fromPlistAt: URL(fileURLWithPath: "/nonexistent/x.plist")) == 4777)
        let url = FileManager.default.temporaryDirectory.appending(path: "lens-\(UUID().uuidString).plist")
        try Data("non un plist".utf8).write(to: url)
        #expect(LensConfig.port(fromPlistAt: url) == 4777)
    }
}
