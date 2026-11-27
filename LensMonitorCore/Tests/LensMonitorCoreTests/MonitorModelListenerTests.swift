import Foundation
import Testing
@testable import LensMonitorCore

/// Il Bearer va solo al processo del job: la porta presa da un altro non riceve richieste.
@MainActor
@Suite struct MonitorModelListenerTests {
    func running(pid: Int = 85289) -> Harness {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: pid)
        h.lens.endpoint = LensEndpoint(port: 4800, token: "segreto")
        return h
    }

    @Test func listenerDelJobProcede() async {
        let h = running()
        await h.model.refresh()
        #expect(h.model.state.isRunning)
        #expect(h.listener.calls == [[85289, 4800]])
        #expect(h.lens.healthCalls == 1)
    }

    /// Un lsof a ogni riavvio della lens (pid nuovo), zero per ciclo.
    @Test func esitoMemorizzatoPerPidEPorta() async {
        let h = running()
        await h.model.refresh()
        await h.model.refresh()
        await h.model.refresh()
        #expect(h.listener.calls.count == 1)
        h.controller.load = .loaded(running: true, pid: 99)
        await h.model.refresh()
        #expect(h.listener.calls.count == 2, "pid nuovo, lens riavviata")
        h.lens.endpoint = LensEndpoint(port: 4801, token: "segreto")
        await h.model.refresh()
        #expect(h.listener.calls.last == [99, 4801], "porta cambiata nel plist")
        #expect(h.listener.calls.count == 3)
    }

    @Test func listenerEstraneoFailENonInviaIlToken() async {
        let h = running()
        h.listener.result = .foreign
        await h.model.refresh()
        #expect(h.model.state == .failed(ServiceState.foreignListenerMessage))
        #expect(h.model.state.statusText.contains("porta occupata da un altro processo"))
        #expect(h.lens.healthCalls == 0, "nessuna richiesta, quindi nessun Authorization")
        #expect(h.lens.budgetCalls == 0)
        #expect(h.model.usage == nil)
        // non si memorizza: appena la porta si libera si riparte
        h.listener.result = .verified
        await h.model.refresh()
        #expect(h.model.state.isRunning)
        #expect(h.listener.calls.count == 2)
    }

    /// lsof muto: chiuso, niente richieste; lo stato è quello di un avvio senza risposta, non "porta occupata".
    @Test func lsofMutoNonInviaIlToken() async {
        let h = running()
        h.listener.result = .unverified
        await h.model.refresh()
        #expect(h.model.state == .starting)
        #expect(h.lens.healthCalls == 0)
        h.clock.now = h.clock.now.addingTimeInterval(ServiceState.startTimeout + 1)
        await h.model.refresh()
        #expect(h.model.state == .failed("in esecuzione ma /healthz non risponde"))
        #expect(h.lens.healthCalls == 0)
        #expect(h.listener.calls.count == 2, "ritentato a ogni giro")
    }

    @Test func conUnaLensDiSviluppoNonSiControlla() async {
        let h = Harness()
        await h.model.selectTarget(.local(host: "127.0.0.1", port: 4790))
        #expect(h.listener.calls.isEmpty)
    }
}
