import Foundation

/// Risposta di GET /healthz della lens.
public struct LensHealth: Decodable, Equatable, Sendable {
    public let opencode: String

    public init(opencode: String) {
        self.opencode = opencode
    }

    public var opencodeConnected: Bool { opencode == "connected" }
}

/// Esito di GET /healthz.
public enum HealthFetch: Equatable, Sendable {
    case ok(LensHealth)
    /// 503 della modalità diagnostica (lens ≥ 0.30.0): il database non si apre (schema più nuovo
    /// dopo un downgrade, file rovinato) e la lens resta su solo per dirlo. `reason` è `error` del
    /// corpo: completo per un client di loopback, generico altrimenti.
    case diagnostic(reason: String)
    /// Rete, status inatteso o JSON non valido.
    case unavailable

    /// La risposta di una lens sana; `nil` negli altri casi.
    public var lens: LensHealth? {
        if case .ok(let health) = self { health } else { nil }
    }
}

/// Host, porta e token con cui l'app raggiunge la lens; il widget li riceve tramite l'App Group.
public struct LensEndpoint: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let token: String?

    public init(host: String = LensConfig.defaultHost, port: Int, token: String?) {
        self.host = host
        self.port = port
        self.token = token
    }
}

/// Esito di GET /api/budget.
public enum BudgetFetch: Equatable, Sendable {
    case ok(BudgetReport)
    /// Rete, status inatteso o JSON non valido.
    case unavailable
}

/// Una riga di GET /api/breakdown?by=model (solo i campi che servono al pannello).
public struct ModelUsage: Decodable, Equatable, Sendable {
    public let key: String
    public let last: Date?
    /// Token di input, senza la cache letta e scritta.
    public let tokensIn: Double
    /// Token di output, ragionamento compreso: anche quelli sono generati dal modello.
    public let tokensOut: Double
    /// Tutti i token, cache compresa: la stessa misura dei budget per modello.
    public let tokensTotal: Double

    public init(key: String, last: Date?, tokensIn: Double = 0, tokensOut: Double = 0, tokensTotal: Double = 0) {
        self.key = key
        self.last = last
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.tokensTotal = tokensTotal
    }

    private enum CodingKeys: String, CodingKey { case key, last, tokens }
    private struct Tokens: Decodable {
        let input: Double?
        let output: Double?
        let reasoning: Double?
        let total: Double?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tokens = try container.decodeIfPresent(Tokens.self, forKey: .tokens)
        self.init(
            key: try container.decode(String.self, forKey: .key),
            last: try container.decodeIfPresent(Date.self, forKey: .last),
            tokensIn: tokens?.input ?? 0,
            tokensOut: (tokens?.output ?? 0) + (tokens?.reasoning ?? 0),
            tokensTotal: tokens?.total ?? 0
        )
    }
}

public protocol LensReading: Sendable {
    var dashboardURL: URL { get }
    /// La dashboard da aprire nel browser: `dashboardURL` con il token della stessa lens.
    var browserURL: URL { get }
    var endpoint: LensEndpoint { get }
    /// Host, porta e token della lens del LaunchAgent, anche quando si segue un'altra lens.
    var serviceEndpoint: LensEndpoint { get }
    func health() async -> HealthFetch
    func budget() async -> BudgetFetch
    func models(since: Date) async -> [ModelUsage]?
    /// Token di `model` (`provider/modello`, varianti insieme) ora per ora da `from` a `to`; `nil`
    /// se la lens non risponde.
    func hourlyTokens(model: String, from: Date, to: Date) async -> [Double]?
    /// Versione della lens da GET /api/about (`lens.version`); `nil` se non risponde o è più vecchia
    /// dell'endpoint.
    func version() async -> String?
}

/// Client HTTP verso la lens (127.0.0.1 o il `LENS_HOST` del plist). L'endpoint è riletto a ogni
/// richiesta, così un plist cambiato o un altro server scelto valgono subito; una volta sola per
/// richiesta, perché URL e token vengano dalla stessa lens anche se la scelta cambia nel mezzo
/// (il token di produzione non deve arrivare a una lens di sviluppo).
public struct LensClient: LensReading {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Secondi di inattività dopo cui una richiesta fallisce (ogni byte ricevuto azzera il conto).
    public static let requestTimeout: TimeInterval = 2
    /// Secondi totali di una richiesta: `timeoutInterval` è solo di inattività, e una lens che
    /// risponde a gocce terrebbe fermo il polling e `busy` acceso per sempre. Largo per
    /// /api/timeseries, che su un giorno pieno può metterci qualche secondo.
    public static let resourceTimeout: TimeInterval = 15
    /// Byte oltre i quali una risposta è scartata: il JSON atteso è di pochi KB, e un corpo
    /// enorme gonfierebbe l'app (e farebbe uccidere il widget da jetsam).
    public static let maxResponseBytes = 8 << 20

    /// Sessione dedicata invece di `URLSession.shared`, che non ha una scadenza totale (giorni).
    /// I redirect non vengono seguiti: la lens non ne emette, e un 3xx vale come risposta non 200.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }()

    final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse, newRequest _: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    /// Il `fetch` dell'app e del widget: la sessione dedicata, con il corpo letto a pezzi e
    /// scartato oltre `maxResponseBytes` (i chiamanti trattano l'errore come lens non disponibile).
    public static let defaultFetch: Fetch = { request in
        let (bytes, response) = try await session.bytes(for: request)
        return (try await collect(bytes, expected: response.expectedContentLength), response)
    }

    /// Raccoglie il corpo finché sta sotto `limit`; `expected` è il Content-Length dichiarato
    /// (-1 se manca), che basta da solo a rifiutare una risposta troppo grande.
    static func collect<Bytes: AsyncSequence>(_ bytes: Bytes, expected: Int64, limit: Int = maxResponseBytes) async throws -> Data where Bytes.Element == UInt8 {
        guard expected <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        data.reserveCapacity(expected > 0 ? Int(expected) : 4096)
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw URLError(.dataLengthExceedsMaximum) }
        }
        return data
    }

    private let resolve: @Sendable () -> LensEndpoint
    private let service: (@Sendable () -> LensEndpoint)?
    private let fetch: Fetch

    /// `service`: la lens del LaunchAgent, se diversa da quella interrogata.
    public init(
        endpoint: @escaping @Sendable () -> LensEndpoint,
        service: (@Sendable () -> LensEndpoint)? = nil,
        fetch: @escaping Fetch = LensClient.defaultFetch
    ) {
        self.resolve = endpoint
        self.service = service
        self.fetch = fetch
    }

    public init(
        host: @escaping @Sendable () -> String = { LensConfig.defaultHost },
        port: @escaping @Sendable () -> Int,
        token: @escaping @Sendable () -> String? = { nil },
        fetch: @escaping Fetch = LensClient.defaultFetch
    ) {
        self.init(endpoint: { LensEndpoint(host: host(), port: port(), token: token()) }, fetch: fetch)
    }

    /// Host, porta e token fissi: il widget li legge dall'App Group.
    public init(host: String = LensConfig.defaultHost, port: Int, token: String?, fetch: @escaping Fetch = LensClient.defaultFetch) {
        self.init(host: { host }, port: { port }, token: { token }, fetch: fetch)
    }

    /// Un IPv6 va tra parentesi quadre; è anche l'header Host che la lens deve accettare. L'interfaccia
    /// di un IPv6 (`fe80::1%en0`) va codificata come `%25`. Un host che non forma un URL ricade su
    /// 127.0.0.1: un plist scritto male non deve far chiudere app e widget a ogni avvio.
    static func baseURL(_ endpoint: LensEndpoint) -> URL {
        let host = endpoint.host.contains(":") ? "[\(endpoint.host.replacingOccurrences(of: "%", with: "%25"))]" : endpoint.host
        return URL(string: "http://\(host):\(endpoint.port)")
            ?? URL(string: "http://\(LensConfig.defaultHost):\(endpoint.port)")!
    }
    public var dashboardURL: URL { Self.baseURL(resolve()) }
    /// Endpoint letto una volta sola, come per le richieste: il token è di quella lens.
    public var browserURL: URL {
        let endpoint = resolve()
        return Self.withToken(Self.baseURL(endpoint), token: endpoint.token)
    }

    /// `base` con `/?token=…`: la lens scambia il token con un cookie e lo toglie dall'indirizzo con
    /// un redirect. Dalla 0.38 `service install` genera sempre un token, e senza il browser avrebbe
    /// un 401. Tutto tranne i caratteri non riservati è codificato (un `+` diventerebbe uno spazio).
    static func withToken(_ base: URL, token: String?) -> URL {
        guard let token, !token.isEmpty,
              let value = token.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        components.path = "/"
        components.percentEncodedQuery = "token=\(value)"
        return components.url ?? base
    }
    public var endpoint: LensEndpoint { resolve() }
    public var serviceEndpoint: LensEndpoint { service?() ?? endpoint }

    /// Un 503 è diagnostico solo con il corpo della lens (`ok` falso e `error`): quello di un
    /// proxy o di un altro servizio sulla porta vale come nessuna risposta.
    public func health() async -> HealthFetch {
        struct Diagnostic: Decodable {
            let ok: Bool
            let error: String
        }
        guard let result = try? await fetch(request("healthz")),
              let status = (result.1 as? HTTPURLResponse)?.statusCode else { return .unavailable }
        switch status {
        case 200:
            guard let health = try? JSONDecoder().decode(LensHealth.self, from: result.0) else { return .unavailable }
            return .ok(health)
        case 503:
            guard let body = try? JSONDecoder().decode(Diagnostic.self, from: result.0), !body.ok else { return .unavailable }
            return .diagnostic(reason: body.error)
        default:
            return .unavailable
        }
    }

    public func budget() async -> BudgetFetch {
        guard let result = try? await fetch(request("api/budget")),
              let status = (result.1 as? HTTPURLResponse)?.statusCode else { return .unavailable }
        guard status == 200, let report = try? LensJSON.decoder.decode(BudgetReport.self, from: result.0) else { return .unavailable }
        return .ok(report)
    }

    /// Modelli usati da `since` in poi; `nil` se la lens non risponde.
    public func models(since: Date) async -> [ModelUsage]? {
        let query = [URLQueryItem(name: "by", value: "model"), URLQueryItem(name: "from", value: Self.milliseconds(since))]
        guard let result = try? await fetch(request("api/breakdown", query: query)),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? LensJSON.decoder.decode([ModelUsage].self, from: result.0)
    }

    /// La lens dà una serie per il modello chiesto; si sommano le serie con la stessa chiave per non
    /// dipendere dalla forma, che il contratto non fissa.
    public func hourlyTokens(model: String, from: Date, to: Date) async -> [Double]? {
        struct Response: Decodable {
            struct Series: Decodable {
                let key: String
                let values: [Double]
            }
            let labels: [String]
            let series: [Series]
        }
        let query = [
            URLQueryItem(name: "from", value: Self.milliseconds(from)),
            URLQueryItem(name: "to", value: Self.milliseconds(to)),
            URLQueryItem(name: "metric", value: "tokens"),
            URLQueryItem(name: "by", value: "model"),
            URLQueryItem(name: "model", value: model),
        ]
        guard let result = try? await fetch(request("api/timeseries", query: query)),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              let response = try? JSONDecoder().decode(Response.self, from: result.0) else { return nil }
        var values = Array(repeating: 0.0, count: response.labels.count)
        for series in response.series where Format.modelKey(series.key) == model {
            for (index, value) in series.values.enumerated() where values.indices.contains(index) {
                values[index] += value
            }
        }
        return values
    }

    static func milliseconds(_ date: Date) -> String {
        // Limitato: una data fuori scala dalla lens manderebbe `Int64(Double)` in trap.
        let ms = date.timeIntervalSince1970 * 1000
        return String(Int64(ms.isNaN ? 0 : min(max(ms.rounded(), -9e15), 9e15)))
    }

    public func version() async -> String? {
        struct About: Decodable {
            struct Lens: Decodable { let version: String }
            let lens: Lens
        }
        guard let result = try? await fetch(request("api/about")),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(About.self, from: result.0).lens.version
    }

    private func request(_ path: String, query: [URLQueryItem] = []) -> URLRequest {
        let endpoint = resolve()
        var url = Self.baseURL(endpoint).appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.requestTimeout
        // Con LENS_TOKEN la lens risponde 401 a ogni richiesta senza autorizzazione, anche a /healthz.
        if let token = endpoint.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

/// Configurazione letta dal plist del LaunchAgent.
public enum LensConfig {
    public static let defaultPort = 4777
    public static let defaultHost = "127.0.0.1"

    /// `EnvironmentVariables.LENS_HOST` del plist. Senza valore, o con un indirizzo di tutte le
    /// interfacce (0.0.0.0, ::), la lens si raggiunge su 127.0.0.1. Un host non locale deve
    /// essere anche in `LENS_ALLOWED_HOSTS` della lens, che altrimenti risponde 403.
    /// Come la lens (`trim()` di JavaScript) toglie anche gli a capo, facili da lasciare
    /// modificando il plist a mano; un valore che non può essere un host vale 127.0.0.1.
    public static func host(fromPlistAt url: URL) -> String {
        guard let raw = plistEnvironment(at: url)["LENS_HOST"] as? String else { return defaultHost }
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return !isValidHost(host) || host == "0.0.0.0" || host == "::" ? defaultHost : host
    }

    /// Nome, IPv4 o IPv6 (anche con `%interfaccia`): niente spazi né caratteri che in un URL
    /// cambierebbero autorità o percorso.
    public static func isValidHost(_ host: String) -> Bool {
        !host.isEmpty && host.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/?#@[]"))) == nil
    }

    /// `LENS_MONITOR_PORT` se presente e valida.
    static func portOverride(environment: [String: String]) -> Int? {
        environment["LENS_MONITOR_PORT"].flatMap(Int.init).flatMap { (1...65535).contains($0) ? $0 : nil }
    }

    /// `LENS_MONITOR_PORT` dell'ambiente dell'app (per provare una lens su un'altra porta),
    /// altrimenti `EnvironmentVariables.LENS_PORT` del plist; 4777 se mancano o non sono valide.
    public static func port(fromPlistAt url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        if let override = portOverride(environment: environment) { return override }
        guard let raw = plistEnvironment(at: url)["LENS_PORT"] as? String,
              let port = Int(raw), (1...65535).contains(port)
        else { return defaultPort }
        return port
    }

    /// La lens da interrogare per `target`: quella del plist, o una lens locale senza token.
    public static func endpoint(for target: LensTarget, plistAt url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> LensEndpoint {
        switch target {
        case .service:
            LensEndpoint(host: host(fromPlistAt: url), port: port(fromPlistAt: url, environment: environment), token: token(fromPlistAt: url))
        case .local(let host, let port):
            LensEndpoint(host: host, port: port, token: nil)
        }
    }

    /// `EnvironmentVariables.LENS_TOKEN` del plist; `nil` se manca o è vuoto.
    public static func token(fromPlistAt url: URL) -> String? {
        guard let token = plistEnvironment(at: url)["LENS_TOKEN"] as? String, !token.isEmpty else { return nil }
        return token
    }

    private static func plistEnvironment(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let env = plist["EnvironmentVariables"] as? [String: Any]
        else { return [:] }
        return env
    }
}
