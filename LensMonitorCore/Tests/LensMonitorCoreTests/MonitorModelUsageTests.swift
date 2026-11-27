import Foundation
import Testing
@testable import LensMonitorCore

final class Counter {
    var value = 0
}

@MainActor
@Suite struct MonitorModelUsageTests {
    func running() -> Harness {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        return h
    }

    @Test func daRunningCaricaBudgetEModelli() async {
        let h = running()
        await h.model.refresh()
        #expect(h.model.usage?.budget == .sample)
        #expect(h.model.usage?.models?.count == 1)
        #expect(h.model.usage?.fetchedAt == h.clock.now)
        #expect(h.model.usage?.stale == false)
        #expect(h.model.nextUsageRefresh == h.clock.now.addingTimeInterval(60))
        #expect(h.lens.modelsSince == [BudgetReport.sample.day.from], "un modello solo: niente storia")
        #expect(h.model.usage?.history == nil)
    }

    let settimana = Calendar.current.date(byAdding: .day, value: -7, to: BudgetReport.sample.day.from)!
    func treModelli() -> BudgetFetch {
        .ok(report(day: dayWith(models: (1...3).map {
            ModelBudget(model: "a/m\($0)", used: 0, limit: 10, ratio: 0.5, projectedRatio: nil, pace: .under)
        })))
    }

    @Test func conPiuModelliLeggeLaStoriaDiSetteGiorni() async {
        let h = running()
        h.lens.budgetResult = treModelli()
        h.lens.historyResult = [ModelUsage(key: "a/m1", last: nil, tokensTotal: 5)]
        await h.model.refresh()
        #expect(h.lens.modelsSince == [settimana, BudgetReport.sample.day.from], "prima la storia, poi oggi")
        #expect(h.model.usage?.history == [ModelUsage(key: "a/m1", last: nil, tokensTotal: 5)])
    }

    @Test func storiaFallitaTieneQuellaDiPrima() async {
        let h = running()
        h.lens.budgetResult = treModelli()
        h.lens.historyResult = [ModelUsage(key: "a/m1", last: nil, tokensTotal: 5)]
        await h.model.refresh()
        h.clock.now += 61
        h.lens.historyResult = nil
        await h.model.refresh()
        #expect(h.lens.modelsSince.filter { $0 == settimana }.count == 2, "la seconda lettura è avvenuta")
        #expect(h.model.usage?.history == [ModelUsage(key: "a/m1", last: nil, tokensTotal: 5)])
        #expect(h.model.usage?.stale == false)
    }

    @Test func datiOgni60Secondi() async {
        let h = running()
        await h.model.refresh()
        h.clock.now += 30
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 1)
        h.clock.now += 31
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 2)
    }

    @Test func intervalloSceltoNelleImpostazioni() async {
        let h = running()
        h.settings.config.refreshInterval = 30
        let model = MonitorModel(
            controller: h.controller, lens: h.lens, discovery: h.discovery, loginItem: h.loginItem,
            settings: h.settings, now: { h.clock.now }, sleep: { _ in }
        )
        #expect(model.usageInterval == 30)
        await model.refresh()
        #expect(model.nextUsageRefresh == h.clock.now.addingTimeInterval(30))
        h.clock.now += 31
        await model.refresh()
        #expect(h.lens.budgetCalls == 2)
    }

    /// Il conto alla rovescia segue subito la scelta, senza aspettare la scadenza del vecchio.
    @Test func cambiareIntervalloRipianificaIlRefresh() async {
        let h = running()
        await h.model.refresh()
        let started = h.clock.now
        h.clock.now += 20
        h.model.setUsageInterval(15)
        #expect(h.model.usageInterval == 15)
        #expect(h.settings.config.refreshInterval == 15)
        #expect(h.model.nextUsageRefresh == started.addingTimeInterval(15))
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 2)
        h.model.setUsageInterval(300)
        #expect(h.model.nextUsageRefresh == h.clock.now.addingTimeInterval(300))
    }

    /// Al reset del giorno di budget il pannello toglie il giorno finito (non è più "oggi"): il
    /// prossimo refresh non può aspettare l'intervallo intero, come già fa il widget, altrimenti
    /// card Oggi, percentuale e riga del reset sparirebbero fino a 5 minuti senza spiegazione.
    @Test func alResetDelGiornoRicaricaSubito() async {
        let h = running()
        let reset = BudgetReport.sample.day.to
        h.clock.now = reset.addingTimeInterval(-10)
        await h.model.refresh()
        #expect(h.model.nextUsageRefresh == reset.addingTimeInterval(1))
        h.model.setUsageInterval(300)
        #expect(h.model.nextUsageRefresh == reset.addingTimeInterval(1), "neanche un intervallo nuovo supera il reset")
        h.clock.now = reset.addingTimeInterval(-5)
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 1)
        let nextDay = BudgetPeriod(from: reset, to: reset.addingTimeInterval(86_400), models: BudgetReport.sample.day.models)
        h.lens.budgetResult = .ok(report(day: nextDay, now: reset.addingTimeInterval(5)))
        h.clock.now = reset.addingTimeInterval(5)
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 2)
        #expect(h.model.usage?.budget?.day.from == reset)
        #expect(h.model.panel.today != nil)
        #expect(h.model.nextUsageRefresh == h.clock.now.addingTimeInterval(300))
    }

    /// Un report di un giorno già finito (lens ferma sul passato) non deve far rileggere a ogni poll.
    @Test func giornoGiaFinitoNonAccorciaLIntervallo() async {
        let h = running()
        h.clock.now = BudgetReport.sample.day.to.addingTimeInterval(120)
        await h.model.refresh()
        #expect(h.model.nextUsageRefresh == h.clock.now.addingTimeInterval(60))
    }

    @Test func intervalloNonInListaIgnorato() {
        let h = Harness()
        h.model.setUsageInterval(7)
        #expect(h.model.usageInterval == 60)
        #expect(h.settings.saves == 0)
    }

    @Test func servizioFermoNonChiedeDati() async {
        let h = Harness()
        await h.model.refresh()
        await h.model.refreshUsage()
        #expect(h.lens.budgetCalls == 0)
        #expect(h.model.nextUsageRefresh == nil)
    }

    @Test func tornaInEsecuzioneERicaricaSubito() async {
        let h = running()
        await h.model.refresh()
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.nextUsageRefresh == nil)
        h.controller.load = .loaded(running: true, pid: 2)
        h.clock.now += 5
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 2)
    }

    @Test func dopoAvviaCaricaIDati() async {
        let h = Harness()
        await h.model.start()
        #expect(h.model.usage?.budget == .sample)
    }

    @Test func erroreLasciaIlDatoVecchio() async {
        let h = running()
        await h.model.refresh()
        let first = h.model.usage?.fetchedAt
        h.clock.now += 61
        h.lens.budgetResult = .unavailable
        await h.model.refresh()
        #expect(h.model.usage?.budget == .sample)
        #expect(h.model.usage?.stale == true)
        #expect(h.model.usage?.fetchedAt == first)
        #expect(h.model.lastError == nil)
    }

    /// Budget riuscito e modelli falliti: l'ora del budget avanza, quella dei modelli no.
    @Test func oraDellUltimoDatoPerFonte() async {
        let h = running()
        await h.model.refresh()
        let first = h.clock.now
        h.clock.now += 61
        h.lens.modelsResult = nil
        await h.model.refresh()
        #expect(h.model.usage?.fetchedAt == h.clock.now)
        #expect(h.model.usage?.modelsFetchedAt == first)
        #expect(h.model.usage?.stale == true)
    }

    /// Aprire il pannello durante il refresh automatico non deve raddoppiare le richieste.
    @Test func refreshSovrappostiNonRaddoppianoLeRichieste() async {
        let h = running()
        await h.model.refresh()
        let gate = Gate()
        h.lens.budgetGate = gate
        let first = Task { await h.model.refreshUsage() }
        await waitUntil { h.lens.budgetCalls >= 2 }
        let second = Task { await h.model.refreshUsage() }
        for _ in 0..<100 { await Task.yield() }
        #expect(h.lens.budgetCalls == 2)
        await gate.open()
        await first.value
        await second.value
        await h.model.refreshUsage()
        #expect(h.lens.budgetCalls == 3)
    }

    @Test func callbackSoloQuandoCambia() async {
        let h = running()
        let calls = Counter()
        h.model.onUsageChange = { calls.value += 1 }
        await h.model.refresh()
        #expect(calls.value == 1)
        await h.model.refreshUsage()
        #expect(calls.value == 1)
        h.lens.budgetResult = .unavailable
        await h.model.refreshUsage()
        #expect(calls.value == 1, "il widget legge la lens da solo: un errore dell'app non lo riguarda")
    }

    /// Ogni refresh porta un `now` e un `fetchedAt` nuovi: ricaricare i widget ogni minuto
    /// esaurirebbe il budget di WidgetKit. Si ricarica solo se cambia ciò che il widget mostra.
    @Test func widgetRicaricatiSoloSeCambiaCioCheMostrano() async {
        let h = running()
        let calls = Counter()
        h.model.onUsageChange = { calls.value += 1 }
        await h.model.refresh()
        #expect(calls.value == 1)
        h.clock.now += 61
        h.lens.budgetResult = .ok(report(now: BudgetReport.sample.now.addingTimeInterval(61)))
        await h.model.refresh()
        #expect(h.lens.budgetCalls == 2)
        #expect(calls.value == 1, "stessi numeri, solo un momento diverso")
        h.clock.now += 61
        h.lens.budgetResult = .ok(report(day: dayWith(models: [ModelBudget(model: "lmstudio/qwen3.5-9b-mlx", used: 600, limit: 1000, ratio: 0.6, pace: .under)])))
        await h.model.refresh()
        #expect(calls.value == 2, "la percentuale di un modello è cambiata")
        h.clock.now += 61
        h.lens.modelsResult = [ModelUsage(key: "openai/gpt-5.5#high", last: nil)]
        await h.model.refresh()
        #expect(calls.value == 3, "un modello nuovo nel riepilogo")
    }

    @Test func widgetRicaricatiQuandoCambiaLaPorta() async {
        let h = Harness()
        let calls = Counter()
        h.model.onUsageChange = { calls.value += 1 }
        await h.model.refresh()
        #expect(calls.value == 0)
        h.lens.endpoint = LensEndpoint(port: 4800, token: nil)
        await h.model.refresh()
        #expect(calls.value == 1)
    }

    @Test func portaETokenNellAppGroup() async {
        let h = Harness()
        h.lens.endpoint = LensEndpoint(port: 4800, token: "segreto")
        await h.model.refresh()
        #expect(h.settings.config.port == 4800)
        #expect(h.settings.config.token == "segreto")
        await h.model.refresh()
        #expect(h.settings.saves == 1, "salva solo quando cambia")
        h.lens.endpoint = LensEndpoint(host: "::1", port: 4800, token: "segreto")
        await h.model.refresh()
        #expect(h.settings.config.host == "::1")
    }

    @Test func senzaAppGroupIlTokenNonSiCopia() async {
        let h = Harness()
        h.settings.reachesWidget = false
        let calls = Counter()
        h.model.onUsageChange = { calls.value += 1 }
        h.lens.endpoint = LensEndpoint(port: 4800, token: "segreto")
        await h.model.refresh()
        await h.model.refresh()
        #expect(h.settings.saves == 0)
        #expect(h.settings.config.token == nil)
        #expect(calls.value == 0, "il widget non legge queste impostazioni: niente reload")
    }

    @Test func indirizzoDellaLensPerIlPopover() {
        #expect(Harness().model.lensAddress == "127.0.0.1:4777")
    }
}
