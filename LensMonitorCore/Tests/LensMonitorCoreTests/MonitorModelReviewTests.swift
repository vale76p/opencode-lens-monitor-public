import Foundation
import Testing
@testable import LensMonitorCore

/// Casi trovati nel controllo qualità prima della beta.
@MainActor
@Suite struct MonitorModelReviewTests {
    func running() -> Harness {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        return h
    }

    @Test func clicSulWidgetConLensGiuApreLeImpostazioni() async {
        let h = Harness()
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.widgetClicked() == nil)
        #expect(h.model.settingsRequests == 1)
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        #expect(h.model.widgetClicked() == .browser(URL(string: "http://127.0.0.1:4777")!))
        #expect(h.model.settingsRequests == 1)
    }

    @Test func versioneRilettaAOgniRefreshDeiDati() async {
        let h = running()
        h.lens.versionResult = "0.37.0"
        await h.model.refresh()
        #expect(h.model.panel.notice == PanelState.outdatedNotice)
        // aggiornata con un riavvio KeepAlive che il poll non ha visto: sempre "running"
        h.lens.versionResult = "0.44.0"
        h.clock.now += 61
        await h.model.refreshUsage()
        #expect(h.model.lensVersion == "0.44.0")
        #expect(h.model.panel.notice == nil)
        #expect(h.lens.versionCalls == 2)
    }

    /// Un `/api/about` fallito una volta non toglie l'avviso: la versione resta quella di prima.
    @Test func versioneNonLettaTieneLAvviso() async {
        let h = running()
        h.lens.versionResult = "0.37.0"
        await h.model.refresh()
        #expect(h.model.panel.notice == PanelState.outdatedNotice)
        h.lens.versionResult = nil
        h.clock.now += 61
        await h.model.refreshUsage()
        #expect(h.model.lensVersion == "0.37.0")
        #expect(h.model.panel.notice == PanelState.outdatedNotice)
    }

    @Test func primaDelPrimoRefreshVerificaInCorso() {
        let h = Harness()
        #expect(h.model.state == .checking)
        #expect(h.model.primaryAction == nil)
    }

    /// Un print fallito per timeout non deve far sembrare ferma una lens che gira.
    @Test func printSconosciutoTieneLoStatoDiPrima() async {
        let h = running()
        await h.model.refresh()
        #expect(h.model.state == .running(opencodeConnected: true))
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        await h.model.refresh()
        #expect(h.model.state == .running(opencodeConnected: true))
    }

    @Test func printSconosciutoAlPrimoRefreshEUnErrore() async {
        let h = Harness()
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        await h.model.refresh()
        #expect(h.model.state == .failed("launchctl print non riuscito (-1): timeout dopo 15 s"))
    }

    /// L'errore di un print al primo refresh non è un avvio: i 15 s di `starting` partono da quando
    /// il servizio risulta caricato ma non in esecuzione.
    @Test func erroreDelPrintNonFaPartireIlTimeoutDiAvvio() async {
        let h = Harness()
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        await h.model.refresh()
        #expect(h.model.state == .failed("launchctl print non riuscito (-1): timeout dopo 15 s"))
        h.clock.now += 5
        h.controller.load = .loaded(running: false, pid: nil)
        await h.model.refresh()
        #expect(h.model.state == .starting)
        h.clock.now += 11
        await h.model.refresh()
        #expect(h.model.state == .starting)
        h.clock.now += 4
        await h.model.refresh()
        #expect(h.model.state == .failed("caricato ma non in esecuzione: controlla il log"))
    }

    @Test func toggleDelServizioSoloConIlLaunchAgentInstallato() async {
        let h = Harness()
        h.controller.isInstalled = false
        await h.model.selectTarget(.local(host: "127.0.0.1", port: 4790))
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.canToggleServiceAtLogin == false)
        h.controller.isInstalled = true
        await h.model.refresh()
        #expect(h.model.canToggleServiceAtLogin)
    }

    @Test func toggleMostraSubitoIlValoreScelto() async {
        let h = running()
        await h.model.refresh()
        #expect(h.model.serviceAtLogin)
        let gate = Gate()
        h.controller.setEnabledGate = gate
        let task = Task { await h.model.setServiceAtLogin(false) }
        await waitUntil { h.model.busy }
        #expect(h.model.serviceAtLogin == false)
        #expect(h.model.canToggleServiceAtLogin == false)
        await gate.open()
        await task.value
        #expect(h.model.serviceAtLogin == false)
    }

    @Test func erroreSparisceDopoUnMinuto() async {
        let h = Harness()
        h.controller.startError = FakeError(message: "boom")
        await h.model.start()
        #expect(h.model.lastError == "boom")
        h.clock.now += 30
        await h.model.refresh()
        #expect(h.model.lastError == "boom")
        h.clock.now += 31
        await h.model.refresh()
        #expect(h.model.lastError == nil)
    }

    @Test func cambioDiLensMostraVerificaFinoAlRefresh() async {
        let h = running()
        await h.model.selectTarget(.local(host: "127.0.0.1", port: 4790))
        #expect(h.model.state == .running(opencodeConnected: true))
        let gate = Gate()
        h.controller.nextStatusGate = gate
        let calls = h.controller.statusCalls
        let task = Task { await h.model.selectTarget(.service) }
        await waitUntil { h.controller.statusCalls > calls }
        #expect(h.model.state == .checking)
        #expect(h.model.primaryAction == nil)
        await gate.open()
        await task.value
        #expect(h.model.state == .running(opencodeConnected: true))
    }

    /// /api/budget in timeout: i modelli si chiedono dall'inizio del giorno di budget già noto,
    /// non da mezzanotte (con LENS_RESET_HOUR diverso da 0 sarebbero un altro intervallo).
    @Test func budgetNonDisponibileUsaIlGiornoDelReportDiPrima() async {
        let h = running()
        h.clock.now = BudgetReport.sample.now
        await h.model.refresh()
        #expect(h.lens.modelsSince.last == BudgetReport.sample.day.from)
        h.lens.budgetResult = .unavailable
        h.clock.now += 61
        await h.model.refreshUsage()
        #expect(h.lens.modelsSince.last == BudgetReport.sample.day.from)
        // giorno del report finito: si torna a mezzanotte
        h.clock.now = BudgetReport.sample.day.to.addingTimeInterval(120)
        await h.model.refreshUsage()
        #expect(h.lens.modelsSince.last == Calendar.current.startOfDay(for: h.clock.now))
    }
}
