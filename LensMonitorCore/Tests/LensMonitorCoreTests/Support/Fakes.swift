import Foundation
@testable import LensMonitorCore

struct FakeError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Sospende chi chiama `wait()` finché non si chiama `open()`, che sblocca tutti.
actor Gate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func open() {
        opened = true
        continuations.forEach { $0.resume() }
        continuations = []
    }
}

final class FakeController: ServiceControlling, @unchecked Sendable {
    @Locked var isInstalled = true
    @Locked var load: LoadState = .notLoaded
    @Locked var enabledAtLogin = true
    @Locked var startError: (any Error)? = nil
    @Locked var stopError: (any Error)? = nil
    @Locked var setEnabledError: (any Error)? = nil
    /// Stato dopo un `start()` riuscito; `nil` lascia `load` com'è.
    @Locked var afterStart: LoadState? = .loaded(running: true, pid: 1)
    /// Stato dopo uno `stop()`, anche fallito (un bootout in timeout può aver scaricato o no il
    /// job); `nil` lascia `load` com'è.
    @Locked var afterStop: LoadState? = .notLoaded
    @Locked var startGate: Gate? = nil
    @Locked var setEnabledGate: Gate? = nil
    @Locked private(set) var statusCalls = 0
    @Locked private(set) var startCalls = 0
    @Locked private(set) var stopCalls = 0
    @Locked private(set) var setEnabledCalls: [Bool] = []

    /// Se impostato, la prossima `status()` legge lo stato subito e aspetta il cancello prima di
    /// restituirlo, come un `launchctl print` lento; vale per una sola chiamata.
    @Locked var nextStatusGate: Gate? = nil

    func status() async -> LoadState {
        statusCalls += 1
        let value = load
        if let gate = nextStatusGate {
            nextStatusGate = nil
            await gate.wait()
        }
        return value
    }

    func isEnabledAtLogin() async -> Bool { enabledAtLogin }

    func start() async throws {
        startCalls += 1
        if let startGate { await startGate.wait() }
        if let startError { throw startError }
        if let afterStart { load = afterStart }
    }

    func stop() async throws {
        stopCalls += 1
        if let afterStop { load = afterStop }
        if let stopError { throw stopError }
    }

    func setEnabledAtLogin(_ enabled: Bool) async throws {
        setEnabledCalls.append(enabled)
        if let setEnabledGate { await setEnabledGate.wait() }
        if let setEnabledError { throw setEnabledError }
        enabledAtLogin = enabled
    }
}

final class FakeLens: LensReading, @unchecked Sendable {
    @Locked var healthResult: HealthFetch = .ok(LensHealth(opencode: "connected"))
    /// Scorciatoia dei test: la lens sana con questa risposta, o (`nil`) che non risponde.
    var current: LensHealth? {
        get { healthResult.lens }
        set { healthResult = newValue.map { .ok($0) } ?? .unavailable }
    }
    @Locked var budgetResult: BudgetFetch = .ok(.sample)
    @Locked var modelsResult: [ModelUsage]? = [ModelUsage(key: "opencode/claude-opus-4-8", last: nil)]
    @Locked var endpoint = LensEndpoint(port: 4777, token: nil)
    @Locked var serviceEndpoint = LensEndpoint(port: 4777, token: nil)
    /// Se impostato, `budget()` aspetta che si apra (dopo aver contato la chiamata).
    @Locked var budgetGate: Gate? = nil
    let dashboardURL = URL(string: "http://127.0.0.1:4777")!
    var browserURL: URL { LensClient.withToken(dashboardURL, token: endpoint.token) }
    @Locked private(set) var budgetCalls = 0
    @Locked var versionResult: String? = "0.44.0"
    @Locked private(set) var versionCalls = 0
    /// Se impostato, la prossima `version()` aspetta che si apra; vale per una chiamata sola.
    @Locked var nextVersionGate: Gate? = nil
    @Locked private(set) var modelsSince: [Date] = []

    @Locked private(set) var healthCalls = 0

    func health() async -> HealthFetch {
        healthCalls += 1
        return healthResult
    }

    func budget() async -> BudgetFetch {
        budgetCalls += 1
        if let budgetGate { await budgetGate.wait() }
        return budgetResult
    }

    func version() async -> String? {
        versionCalls += 1
        if let gate = nextVersionGate {
            nextVersionGate = nil
            await gate.wait()
        }
        return versionResult
    }

    /// La storia di 7 giorni del giorno d'esempio; altre date ricevono `modelsResult`.
    @Locked var historyResult: [ModelUsage]? = []

    func models(since: Date) async -> [ModelUsage]? {
        modelsSince.append(since)
        return since == Calendar.current.date(byAdding: .day, value: -7, to: BudgetReport.sample.day.from) ? historyResult : modelsResult
    }

    @Locked var hourlyResult: [Double]? = [100, 300, 0]
    @Locked private(set) var hourlyAsked: [String] = []

    func hourlyTokens(model: String, from: Date, to: Date) async -> [Double]? {
        hourlyAsked.append(model)
        return hourlyResult
    }
}

final class FakeListener: ListenerVerifying, @unchecked Sendable {
    @Locked var result = ListenerCheck.verified
    @Locked private(set) var calls: [[Int]] = []

    func check(pid: Int, port: Int) async -> ListenerCheck {
        calls.append([pid, port])
        return result
    }
}

final class FakeDiscovery: LensDiscovering, @unchecked Sendable {
    @Locked var found: [LensServer] = []
    func servers() async -> [LensServer] { found }
}

@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: LoginItemStatus = .disabled
    var error: (any Error)?
    private(set) var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if let error { throw error }
        status = enabled ? .enabled : .disabled
    }
}

final class TestClock: @unchecked Sendable {
    @Locked var now = Date(timeIntervalSince1970: 1_000)
}

final class SleepRecorder: @unchecked Sendable {
    @Locked var calls: [Duration] = []
}

/// Dov'è installata l'app OpenCode Lens della lens; `nil` se manca.
final class CompanionAppBox: @unchecked Sendable {
    @Locked var value: URL? = nil
}

/// Modello con tutte le dipendenze finte.
@MainActor
struct Harness {
    let controller = FakeController()
    let lens = FakeLens()
    let discovery = FakeDiscovery()
    let listener = FakeListener()
    let loginItem = FakeLoginItem()
    let settings = InMemorySettings()
    let clock = TestClock()
    let sleeps = SleepRecorder()
    let companionApp = CompanionAppBox()
    let model: MonitorModel

    init() {
        let clock = clock
        let sleeps = sleeps
        let companionApp = companionApp
        model = MonitorModel(
            controller: controller,
            lens: lens,
            discovery: discovery,
            loginItem: loginItem,
            settings: settings,
            listener: listener,
            companionApp: { companionApp.value },
            now: { clock.now },
            sleep: { duration in
                sleeps.calls.append(duration)
                await Task.yield()
            }
        )
    }
}

final class InMemorySettings: SharedSettingsStore, @unchecked Sendable {
    var config = SharedConfig.default
    var reachesWidget = true
    private(set) var saves = 0

    func load() -> SharedConfig { config }

    func save(_ config: SharedConfig) {
        self.config = config
        saves += 1
    }
}
