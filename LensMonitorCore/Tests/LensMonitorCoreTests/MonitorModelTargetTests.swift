import Foundation
import Testing
@testable import LensMonitorCore

@MainActor
@Suite struct MonitorModelTargetTests {
    static let dev = LensTarget.local(host: "127.0.0.1", port: 4790)

    @Test func targetDalleImpostazioni() {
        let h = Harness()
        #expect(h.model.lensTarget == .service)
        h.settings.config.target = Self.dev
        let model = MonitorModel(controller: FakeController(), lens: FakeLens(), discovery: FakeDiscovery(), loginItem: FakeLoginItem(), settings: h.settings)
        #expect(model.lensTarget == Self.dev)
    }

    @Test func lensDiSviluppoIgnoraIlLaunchAgent() async {
        let h = Harness()
        h.controller.load = .notLoaded
        await h.model.selectTarget(Self.dev)
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.controller.statusCalls == 0)
        #expect(h.model.primaryAction == nil)
        #expect(h.model.usage?.budget == .sample)

        h.lens.current = nil
        h.clock.now += 30
        await h.model.refresh()
        #expect(h.model.state == .unreachable)
        #expect(h.model.primaryAction == nil)
    }

    /// Una lens di sviluppo con il database rotto dice perché, invece di "server non raggiungibile",
    /// e resta senza Avvia/Ferma e senza dati.
    @Test func lensDiSviluppoDiagnosticaMostraIlMotivo() async {
        let h = Harness()
        h.lens.healthResult = .diagnostic(reason: "file rovinato")
        await h.model.selectTarget(Self.dev)
        #expect(h.model.state == .failed("database non utilizzabile: file rovinato"))
        #expect(h.model.primaryAction == nil)
        #expect(h.controller.statusCalls == 0)
        #expect(h.lens.budgetCalls == 0)
        #expect(h.model.usage == nil)
    }

    @Test func sceltaSalvataEDatiAzzerati() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        #expect(h.model.usage != nil)
        #expect(h.model.primaryAction == .stop)

        h.lens.current = nil
        await h.model.selectTarget(Self.dev)
        #expect(h.settings.config.target == Self.dev)
        #expect(h.model.usage == nil)
        #expect(h.model.state == .unreachable)

        h.lens.current = LensHealth(opencode: "connected")
        await h.model.selectTarget(.service)
        #expect(h.settings.config.target == .service)
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.primaryAction == .stop)
    }

    @Test func datiInArrivoDallaLensPrecedenteScartati() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        let gate = Gate()
        h.lens.budgetGate = gate
        h.clock.now += 61
        let slow = Task { await h.model.refreshUsage() }
        await waitUntil { h.lens.budgetCalls >= 2 }
        // la lettura della lens nuova parte subito, senza aspettare quella vecchia
        let select = Task { await h.model.selectTarget(Self.dev) }
        await waitUntil { h.lens.budgetCalls >= 3 }
        #expect(h.model.usage == nil)
        let other = report(day: dayWith(models: []))
        h.lens.budgetResult = .ok(other)
        await gate.open()
        await slow.value
        await select.value
        #expect(h.model.usage?.budget == other)
        // e il refresh successivo non resta bloccato dalla lettura scartata
        h.clock.now += 61
        await h.model.refreshUsage()
        #expect(h.lens.budgetCalls == 4)
    }

    @Test func versioneInArrivoDallaLensPrecedenteNonRicaricaIWidget() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        let gate = Gate()
        h.lens.nextVersionGate = gate
        let slow = Task { await h.model.refresh() }
        await waitUntil { h.lens.versionCalls >= 1 }
        let calls = Counter()
        h.model.onUsageChange = { calls.value += 1 }
        // la lens nuova mostra altro: i widget si ricaricano una volta, per lei
        h.lens.budgetResult = .ok(report(day: dayWith(models: [])))
        await h.model.selectTarget(Self.dev)
        #expect(calls.value == 1)
        await gate.open()
        await slow.value
        #expect(calls.value == 1)
        // e la chiave resta quella della lens nuova: un refresh uguale non ricarica
        h.clock.now += 61
        await h.model.refreshUsage()
        #expect(calls.value == 1)
    }

    @Test func avviaEFermaIgnoratiConUnaLensDiSviluppo() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.selectTarget(Self.dev)
        await h.model.stop()
        await h.model.start()
        #expect(h.controller.stopCalls == 0)
        #expect(h.controller.startCalls == 0)
        #expect(h.sleeps.calls.isEmpty)
    }

    @Test func opzioniDalleLensTrovate() async {
        let h = Harness()
        h.discovery.found = [LensServer(host: "127.0.0.1", port: 4790, name: "lens-live")]
        #expect(h.model.serverOptions.map(\.target) == [.service])
        await h.model.discoverServers()
        #expect(h.model.serverOptions.map(\.target) == [.service, Self.dev])
        #expect(h.model.discovering == false)
    }
}
