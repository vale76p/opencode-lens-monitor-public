import Foundation
import Testing
@testable import LensMonitorCore

@MainActor
@Suite struct MonitorModelTests {
    @Test func refreshNonInstallatoNonInterrogaLaunchctl() async {
        let h = Harness()
        h.controller.isInstalled = false
        await h.model.refresh()
        #expect(h.model.state == .notInstalled)
        #expect(h.controller.statusCalls == 0)
        #expect(h.model.serviceAtLogin == false)
    }

    @Test func refreshInEsecuzione() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.controller.enabledAtLogin = false
        h.loginItem.status = .requiresApproval
        await h.model.refresh()
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.serviceAtLogin == false)
        #expect(h.model.appLogin == .requiresApproval)
    }

    @Test func avvioInCorsoDiventaErroreDopo15Secondi() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.lens.current = nil
        await h.model.refresh()
        #expect(h.model.state == .starting)
        h.clock.now += 10
        await h.model.refresh()
        #expect(h.model.state == .starting)
        h.clock.now += 6
        await h.model.refresh()
        #expect(h.model.state == .failed("in esecuzione ma /healthz non risponde"))
        h.lens.current = LensHealth(opencode: "connected")
        await h.model.refresh()
        #expect(h.model.state == .running(opencodeConnected: true))
        // Il conteggio riparte da zero dopo uno stato stabile.
        h.lens.current = nil
        await h.model.refresh()
        #expect(h.model.state == .starting)
    }

    /// Lens in modalità diagnostica (database che non si apre): errore con il motivo al primo
    /// refresh, senza i 15 s dell'avvio, e nessuna lettura dei dati finché non si riprende.
    @Test func lensDiagnosticaErroreSubitoSenzaDati() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.lens.healthResult = .diagnostic(reason: "database con schema 12, più nuovo di questa lens (11)")
        await h.model.refresh()
        #expect(h.model.state == .failed("database non utilizzabile: database con schema 12, più nuovo di questa lens (11)"))
        #expect(h.model.primaryAction == .stop)
        #expect(h.lens.budgetCalls == 0)
        #expect(h.model.usage == nil)
        #expect(h.model.nextUsageRefresh == nil)
        #expect(h.model.lensVersion == nil)
        h.clock.now += 5
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 0)
        // Installata la lens giusta, il servizio riparte da solo: tutto torna normale.
        h.lens.healthResult = .ok(LensHealth(opencode: "connected"))
        await h.model.refresh()
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.lens.budgetCalls == 1)
        #expect(h.model.usage?.budget == .sample)
    }

    /// Un print che non risponde tiene lo stato di prima, ma un avvio non può durare all'infinito:
    /// scaduti i 15 s si dichiara fallito, come farebbe resolve (che su quel ramo non passa).
    @Test func avvioConPrintSconosciutoScadeComunque() async {
        let h = Harness()
        h.controller.load = .loaded(running: false, pid: nil)
        await h.model.refresh()
        #expect(h.model.state == .starting)
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        h.clock.now += 10
        await h.model.refresh()
        #expect(h.model.state == .starting)
        h.clock.now += 5
        await h.model.refresh()
        #expect(h.model.state == .failed("launchctl non risponde e l'avvio non finisce"))
        h.clock.now += 5
        await h.model.refresh()
        #expect(h.model.state == .failed("launchctl non risponde e l'avvio non finisce"))
    }

    @Test func startConvergeAlPrimoRefresh() async {
        let h = Harness()
        await h.model.start()
        #expect(h.controller.startCalls == 1)
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.busy == false)
        #expect(h.model.lastError == nil)
        #expect(h.sleeps.calls.isEmpty)
    }

    @Test func startCheNonConvergeFa10RefreshE9Attese() async {
        let h = Harness()
        h.controller.afterStart = nil
        await h.model.start()
        #expect(h.controller.statusCalls == MonitorModel.convergeAttempts)
        #expect(h.sleeps.calls == Array(repeating: .seconds(1), count: MonitorModel.convergeAttempts - 1))
        #expect(h.model.state == .stopped)
        #expect(h.model.busy == false)
    }

    @Test func startConErroreMostraIlMessaggio() async {
        let h = Harness()
        h.controller.startError = LaunchctlError(command: "bootstrap", status: 5, stderr: "Bootstrap failed: 5: Input/output error\n")
        await h.model.start()
        #expect(h.model.lastError == "launchctl bootstrap non riuscito (5): Bootstrap failed: 5: Input/output error")
        #expect(h.model.state == .stopped)
        #expect(h.controller.statusCalls == 1)
        #expect(h.model.busy == false)
    }

    @Test func azioneRiuscitaCancellaLErrore() async {
        let h = Harness()
        h.controller.startError = FakeError(message: "boom")
        await h.model.start()
        #expect(h.model.lastError == "boom")
        h.controller.startError = nil
        await h.model.start()
        #expect(h.model.lastError == nil)
    }

    @Test func stopConvergeAFermo() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        await h.model.stop()
        #expect(h.controller.stopCalls == 1)
        #expect(h.model.state == .stopped)
    }

    @Test func startMentreBusyVieneIgnorato() async {
        let h = Harness()
        let gate = Gate()
        h.controller.startGate = gate
        let first = Task { await h.model.start() }
        await waitUntil { h.model.busy }
        await h.model.start()
        await h.model.stop()
        #expect(h.controller.startCalls == 1)
        #expect(h.controller.stopCalls == 0)
        await gate.open()
        await first.value
        #expect(h.model.busy == false)
    }

    @Test func avvioLensAlLogin() async {
        let h = Harness()
        await h.model.setServiceAtLogin(false)
        #expect(h.controller.setEnabledCalls == [false])
        #expect(h.model.serviceAtLogin == false)
        h.controller.setEnabledError = FakeError(message: "negato")
        await h.model.setServiceAtLogin(true)
        #expect(h.model.lastError == "negato")
        #expect(h.model.serviceAtLogin == false)
    }

    @Test func aperturaAppAlLogin() {
        let h = Harness()
        h.model.setAppAtLogin(true)
        #expect(h.model.appLogin == .enabled)
        h.loginItem.error = FakeError(message: "Operation not permitted")
        h.model.setAppAtLogin(false)
        #expect(h.model.lastError == "Operation not permitted")
        #expect(h.model.appLogin == .enabled)
    }

    @Test func messaggioSuUnaRigaEAl120Caratteri() {
        #expect(MonitorModel.message(for: FakeError(message: "prima\nseconda")) == "prima")
        let long = MonitorModel.message(for: FakeError(message: String(repeating: "x", count: 200)))
        #expect(long.count == 120)
        #expect(long.hasSuffix("…"))
    }

    @Test func pollingAggiornaEPoiSiFerma() async {
        let h = Harness()
        h.model.startPolling()
        var spins = 0
        while h.controller.statusCalls < 2 && spins < 1_000 {
            await Task.yield()
            spins += 1
        }
        h.model.stopPolling()
        #expect(h.controller.statusCalls >= 2)
        #expect(h.sleeps.calls.allSatisfy { $0 == .seconds(15) }, "lens ferma da poco: 15 s")
        let calls = h.controller.statusCalls
        for _ in 0..<50 { await Task.yield() }
        #expect(h.controller.statusCalls <= calls + 1)
    }

    @Test func dashboardURLDallaLens() {
        let h = Harness()
        #expect(h.model.dashboardURL.absoluteString == "http://127.0.0.1:4777")
    }

    /// Un poll partito prima di Ferma (es. fermo su /healthz) non deve scrivere il suo stato
    /// vecchio sopra quello dell'azione.
    @Test func refreshSospesoNonSovrascriveFerma() async {
        let h = Harness()
        h.controller.load = .loaded(running: false, pid: 1)
        let gate = Gate()
        h.controller.nextStatusGate = gate
        let poll = Task { await h.model.refresh() }
        await waitUntil { h.controller.statusCalls >= 1 }
        await h.model.stop()
        #expect(h.model.state == .stopped)
        await gate.open()
        await poll.value
        #expect(h.model.state == .stopped)
    }

    /// In attesa di approvazione il login item è registrato: l'interruttore appare acceso e
    /// spegnerlo lo annulla, invece di ripetere register().
    @Test func loginDelMonitorSpegnibileDaInAttesaDiApprovazione() {
        #expect(LoginItemStatus.enabled.isOn)
        #expect(LoginItemStatus.requiresApproval.isOn)
        #expect(!LoginItemStatus.disabled.isOn)
        let h = Harness()
        h.loginItem.status = .requiresApproval
        h.model.setAppAtLogin(false)
        #expect(h.model.appLogin == .disabled)
    }

    /// Durante Avvia (finestra enable → bootstrap → disable) cambiare "Avvia lens al login"
    /// verrebbe annullato dal disable finale: la richiesta passa dalla stessa guardia busy.
    @Test func loginDelServizioNonSiSovrapponeAdAvvia() async {
        let h = Harness()
        let gate = Gate()
        h.controller.startGate = gate
        let start = Task { await h.model.start() }
        await waitUntil { h.controller.startCalls >= 1 }
        #expect(h.model.busy)
        await h.model.setServiceAtLogin(false)
        #expect(h.controller.setEnabledCalls.isEmpty)
        await gate.open()
        await start.value
        await h.model.setServiceAtLogin(false)
        #expect(h.controller.setEnabledCalls == [false])
        #expect(h.model.busy == false)
    }
}
