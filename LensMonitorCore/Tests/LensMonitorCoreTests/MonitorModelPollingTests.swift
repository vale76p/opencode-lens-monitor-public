import Foundation
import Testing
@testable import LensMonitorCore

/// Il polling rallenta con la lens ferma o in errore e torna a 5 s a ogni azione dell'utente.
@MainActor
@Suite struct MonitorModelPollingTests {
    @Test func inEsecuzioneQuindiciSecondi() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        #expect(h.model.state.isRunning)
        #expect(h.model.pollInterval == 15)
    }

    /// Il refresh dei dati (60 s) è nel poll: a 15 s non arriva mai più tardi di 15 s, e se manca
    /// poco il giro si accorcia.
    @Test func nonRitardaIlRefreshDeiDati() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        h.clock.now = h.clock.now.addingTimeInterval(55)
        #expect(h.model.pollInterval == 5)
    }

    @Test func fermoDaMoltoRallentaPoiUnAzioneRiportaACinque() async {
        let h = Harness()
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.pollInterval == 15)
        h.clock.now = h.clock.now.addingTimeInterval(1_000)
        await h.model.refresh()
        #expect(h.model.pollInterval == 60)
        // Avvia: occupato mentre converge, e per `boostWindow` dopo
        h.controller.afterStart = .notLoaded
        await h.model.start()
        #expect(h.model.pollInterval == 5)
        h.clock.now = h.clock.now.addingTimeInterval(PollPacing.boostWindow + 1)
        #expect(h.model.pollInterval == 60, "tornato al ritmo dello stato")
    }

    @Test func erroreProlungatoArrivaASessanta() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.lens.healthResult = .diagnostic(reason: "schema")
        await h.model.refresh()
        guard case .failed = h.model.state else {
            Issue.record("atteso .failed")
            return
        }
        #expect(h.model.pollInterval == 5)
        h.clock.now = h.clock.now.addingTimeInterval(400)
        await h.model.refresh()
        #expect(h.model.pollInterval == 60)
    }

    @Test func cambioDiFamigliaRiparteDaCapo() async {
        let h = Harness()
        h.controller.load = .notLoaded
        await h.model.refresh()
        h.clock.now = h.clock.now.addingTimeInterval(1_000)
        await h.model.refresh()
        #expect(h.model.pollInterval == 60)
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        #expect(h.model.pollInterval == 15)
        h.controller.load = .notLoaded
        h.clock.now = h.clock.now.addingTimeInterval(PollPacing.boostWindow + 1)
        await h.model.refresh()
        #expect(h.model.pollInterval == 5, "appena fermata (restarting) si guarda spesso")
    }

    /// L'apertura del pannello sveglia il poll che dorme (anche 60 s) e riporta a 5 s.
    @Test func ilPannelloSvegliaIlPoll() async {
        let controller = FakeController()
        controller.load = .notLoaded
        let model = MonitorModel(
            controller: controller, lens: FakeLens(), discovery: FakeDiscovery(), loginItem: FakeLoginItem(),
            settings: InMemorySettings(), sleep: { try? await Task.sleep(for: $0) }
        )
        model.startPolling()
        await waitUntil { controller.statusCalls >= 1 }
        let before = controller.statusCalls
        await model.panelOpened()
        // La sveglia passa da Task.sleep annullato: serve tempo vero, non solo yield
        for _ in 0..<200 where controller.statusCalls <= before { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.statusCalls > before)
        #expect(model.pollInterval == 5)
        model.stopPolling()
    }
}
