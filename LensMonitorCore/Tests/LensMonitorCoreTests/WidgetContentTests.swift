import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct WidgetContentTests {
    let rome = TimeZone(identifier: "Europe/Rome")!
    let qwen = "lmstudio/qwen3.5-9b-mlx"

    func budget(_ model: String, used: Double, limit: Double = 1000, pace: Pace = .under) -> ModelBudget {
        ModelBudget(model: model, used: used, limit: limit, ratio: used / limit, pace: pace)
    }

    /// La percentuale è token di oggi su budget: a metà giornata 400 su 1000 resta 40%, non conta
    /// quanto manca al reset.
    @Test func modelloConBudget() {
        let day = ModelDay.make(key: qwen, report: .sample, models: nil)
        #expect(day == ModelDay(key: qwen, name: "qwen3.5-9b-mlx", percent: "40%", progress: 0.4, used: "400", budget: "400 / 1k", pace: .under, reset: BudgetReport.sample.day.to))
        #expect(day.resetLine(at: BudgetReport.sample.now, timeZone: rome) == "Reset in 12h 00m alle 00:00")
    }

    @Test func modelloSenzaBudgetMostraIToken() {
        let models = [
            ModelUsage(key: "openai/gpt-5.5", last: nil, tokensTotal: 1_500),
            ModelUsage(key: "openai/gpt-5.5#high", last: nil, tokensTotal: 700),
            ModelUsage(key: "openai/altro", last: nil, tokensTotal: 9_000),
        ]
        let day = ModelDay.make(key: "openai/gpt-5.5", report: .sample, models: models)
        #expect(day.percent == nil)
        #expect(day.progress == nil)
        #expect(day.budget == nil)
        #expect(day.used == "2,2k")
        #expect(day.pace == .noLimit)
    }

    @Test func andamentoFinoAllOraInCorso() {
        // il giorno d'esempio inizia a mezzanotte di Roma, `now` è alle 12
        let values = (0..<24).map(Double.init)
        let trend = DayTrend.make(values: values, key: qwen, report: .sample, timeZone: rome)
        #expect(trend.hours == 24)
        #expect(trend.points.count == 13)
        #expect(trend.points.first == DayTrend.Point(hour: 0.5, value: 0))
        #expect(trend.points.last == DayTrend.Point(hour: 12.5, value: 12))
        #expect(trend.average == 1000.0 / 24)
        #expect(trend.ticks.map(\.label) == ["00", "06", "12", "18", "00"])
        #expect(trend.ticks.map(\.hour) == [0, 6, 12, 18, 24])
    }

    /// Nel giorno del ritorno all'ora solare il giorno di budget dura 25 ore: dominio e tick
    /// seguono la durata, non il numero di valori (una lens vecchia ne dà 24, con l'ora ripetuta
    /// deduplicata), così l'ultimo tick dice "05" e la riga del reset "06:00", non "05" e "06:00"
    /// spostati di un'ora.
    @Test func giornoDi25OreColCambioDOra() {
        // 24/10/2026 06:00 CEST → 25/10/2026 06:00 CET: il cambio è alle 03:00 del 25
        let from = Date(timeIntervalSince1970: 1_792_814_400)
        let to = Date(timeIntervalSince1970: 1_792_904_400)
        #expect(to.timeIntervalSince(from) == 25 * 3600)
        #expect(Format.clock(to, timeZone: rome) == "06:00")
        let day = BudgetPeriod(from: from, to: to, models: BudgetReport.sample.day.models)
        let r = report(day: day, now: from.addingTimeInterval(24.5 * 3600))
        let full = DayTrend.make(values: (0..<25).map(Double.init), key: qwen, report: r, timeZone: rome)
        #expect(full.hours == 25)
        #expect(full.points.count == 25)
        #expect(full.points.last == DayTrend.Point(hour: 24.5, value: 24))
        #expect(full.ticks.map(\.label) == ["06", "12", "18", "00", "05"])
        #expect(full.ticks.map(\.hour) == [0, 6, 12, 18, 24])
        #expect(full.average == 1000.0 / 25)
        let old = DayTrend.make(values: (0..<24).map(Double.init), key: qwen, report: r, timeZone: rome)
        #expect(old.hours == 25, "una lens che deduplica l'ora ripetuta non accorcia il giorno")
        #expect(old.points.count == 24)
    }

    /// Un giorno o un `now` fuori scala (date in ms oltre ogni anno ragionevole) non devono andare in
    /// trap né generare milioni di tick: l'asse resta di poche ore.
    @Test(arguments: [1e300, -1e300, 1e15] as [Double])
    func andamentoConDateFuoriScala(ms: Double) {
        let day = BudgetReport.sample.day
        let wild = BudgetPeriod(from: day.from, to: Date(timeIntervalSince1970: ms), models: day.models)
        let trend = DayTrend.make(values: [1, 2, 3], key: qwen, report: report(day: wild, now: Date(timeIntervalSince1970: ms)), timeZone: rome)
        #expect(trend.hours >= 1 && trend.hours <= 48)
        #expect(trend.ticks.count <= 9)
    }

    @Test func andamentoSenzaBudgetNienteRiferimento() {
        let trend = DayTrend.make(values: [], key: "openai/gpt-5.5", report: .sample, timeZone: rome)
        #expect(trend.average == nil)
        #expect(trend.points.isEmpty)
        #expect(trend.hours == 24)
    }

    @Test func ilModelloMaiVistoNonESceltoDaSolo() {
        let r = report(day: dayWith(models: [
            ModelBudget(model: "x/never", used: 0, limit: 1000, ratio: 0, pace: .exceeded, seen: false),
            budget("a/qwen", used: 1),
        ]))
        #expect(WidgetModels.resolve(nil, report: r) == "a/qwen")
    }

    @Test func sceltaDeiModelli() {
        let r = report(day: dayWith(models: [budget("b/qwen", used: 1), budget("a/qwen", used: 1), budget("x/llama", used: 1)]))
        #expect(WidgetModels.choices(r).map(\.name) == ["a/qwen", "b/qwen", "llama"])
        #expect(WidgetModels.choices(r).map(\.key) == ["a/qwen", "b/qwen", "x/llama"])
    }

    /// Senza scelta il widget segue il modello messo peggio: prima il ritmo, poi la percentuale.
    @Test func modelloPredefinito() {
        let r = report(day: dayWith(models: [
            budget("a/uno", used: 900),
            budget("b/due", used: 300, pace: .over),
            budget("c/tre", used: 500, pace: .over),
        ]))
        #expect(WidgetModels.resolve(nil, report: r) == "c/tre")
        #expect(WidgetModels.resolve("a/uno", report: r) == "a/uno")
        #expect(WidgetModels.resolve("z/tolto", report: r) == "z/tolto", "la scelta resta anche senza budget")
        #expect(WidgetModels.resolve(nil, report: report(day: dayWith(models: nil))) == nil)
    }

    @Test func caricaIlWidgetMedio() async {
        let settings = InMemorySettings()
        settings.config = SharedConfig(port: 4790, token: nil)
        let lens = FakeLens()
        var asked: SharedConfig?
        let now = BudgetReport.sample.now
        let loaded = await WidgetContent.load(.trend, model: nil, now: now, settings: settings, timeZone: rome) { config in
            asked = config
            return lens
        }
        #expect(asked?.port == 4790)
        #expect(lens.hourlyAsked == [qwen])
        #expect(lens.modelsSince.isEmpty, "con un budget i token vengono da /api/budget")
        guard case .model(let day, let trend) = loaded.content else {
            Issue.record("atteso .model")
            return
        }
        #expect(day.percent == "40%")
        #expect(trend?.points.map(\.value) == [100, 300, 0])
        #expect(loaded.nextUpdate == now.addingTimeInterval(WidgetContent.refreshInterval))
    }

    @Test func caricaIlWidgetPiccoloSenzaAndamento() async {
        let lens = FakeLens()
        let loaded = await WidgetContent.load(.ring, model: "opencode/claude-opus-4-8", now: BudgetReport.sample.now, settings: InMemorySettings(), timeZone: rome) { _ in lens }
        #expect(lens.hourlyAsked.isEmpty)
        #expect(lens.modelsSince == [BudgetReport.sample.day.from], "senza budget i token vengono da /api/breakdown")
        guard case .model(let day, nil) = loaded.content else {
            Issue.record("atteso .model senza andamento")
            return
        }
        #expect(day.name == "claude-opus-4-8")
    }

    @Test func andamentoNonDisponibile() async {
        let lens = FakeLens()
        lens.hourlyResult = nil
        let loaded = await WidgetContent.load(.trend, now: BudgetReport.sample.now, settings: InMemorySettings()) { _ in lens }
        guard case .model(_, nil) = loaded.content else {
            Issue.record("atteso .model senza andamento")
            return
        }
    }

    @Test func caricaIlRiepilogo() async {
        let lens = FakeLens()
        let now = BudgetReport.sample.now
        let loaded = await WidgetContent.load(.summary, now: now, settings: InMemorySettings(), timeZone: rome) { _ in lens }
        guard case .summary(let summary) = loaded.content else {
            Issue.record("atteso .summary")
            return
        }
        #expect(summary.rows.map(\.name) == ["claude-opus-4-8", "qwen3.5-9b-mlx"])
        #expect(summary.rows.last?.percent == "40%")
        #expect(summary.resetLine(at: now, timeZone: rome) == "Reset in 12h 00m alle 00:00")
        lens.modelsResult = []
        lens.budgetResult = .ok(report(day: dayWith(models: nil)))
        #expect(await WidgetContent.load(.summary, now: now, settings: InMemorySettings()) { _ in lens }.content == .message(WidgetContent.noModels))
    }

    /// Nel widget medio entrano 4 righe, ma un modello sopra il ritmo non resta mai fuori.
    @Test func riepilogoAlMassimoQuattroModelli() {
        let budgets = (1...6).map { budget("p/m\($0)", used: 1) } + [budget("p/m7", used: 900, pace: .over)]
        let summary = DaySummary.make(report: report(day: dayWith(models: budgets)), models: [])
        #expect(summary.rows.count == 4)
        #expect(summary.rows.contains { $0.name == "m7" })
    }

    @Test func messaggi() async {
        let lens = FakeLens()
        let now = BudgetReport.sample.now
        lens.budgetResult = .ok(report(day: dayWith(models: [])))
        #expect(await WidgetContent.load(.ring, now: now, settings: InMemorySettings()) { _ in lens }.content == .message(WidgetContent.noBudgets))
        lens.budgetResult = .unavailable
        #expect(await WidgetContent.load(.trend, now: now, settings: InMemorySettings()) { _ in lens }.content == .message(WidgetContent.unreachable))
        #expect(await WidgetContent.load(.summary, now: now, settings: InMemorySettings()) { _ in lens }.content == .message("Lens non raggiungibile"))
    }

    @Test func modelliPerIlMenuDelWidget() async {
        let lens = FakeLens()
        #expect(await WidgetModels.load(settings: InMemorySettings()) { _ in lens } == [WidgetModels.Choice(key: qwen, name: "qwen3.5-9b-mlx")])
        lens.budgetResult = .unavailable
        #expect(await WidgetModels.load(settings: InMemorySettings()) { _ in lens }.isEmpty)
    }

    /// Una voce per minuto fino al prossimo aggiornamento: il tempo al reset non resta indietro.
    @Test func vociDellaTimelineOgniMinuto() {
        let now = Date(timeIntervalSince1970: 1_792_058_430)
        let dates = WidgetContent.entryDates(from: now, until: now.addingTimeInterval(15 * 60))
        #expect(dates.count == 16)
        #expect(dates.first == now)
        #expect(dates[1] == Date(timeIntervalSince1970: 1_792_058_460))
        #expect(dates.last == Date(timeIntervalSince1970: 1_792_059_300))
        #expect(WidgetContent.entryDates(from: now, until: now.addingTimeInterval(10)) == [now])
    }

    /// Il widget si riaggiorna ogni 15 minuti, ma subito dopo il reset del giorno se arriva prima:
    /// altrimenti mostrerebbe il giorno passato fino a 15 minuti.
    @Test func prossimoAggiornamentoAlResetDelGiorno() {
        let reset = BudgetReport.sample.day.to
        let now = BudgetReport.sample.now
        #expect(WidgetContent.nextUpdate(after: now, fetch: .ok(.sample)) == now.addingTimeInterval(15 * 60))
        let late = reset.addingTimeInterval(-5 * 60)
        #expect(WidgetContent.nextUpdate(after: late, fetch: .ok(.sample)) == reset.addingTimeInterval(1))
        // report di un giorno già finito, o nessun dato: i soliti 15 minuti
        let after = reset.addingTimeInterval(60)
        #expect(WidgetContent.nextUpdate(after: after, fetch: .ok(.sample)) == after.addingTimeInterval(15 * 60))
        // lens non raggiungibile o dati a metà: si riprova presto, non dopo 15 minuti
        #expect(WidgetContent.retryInterval == 120)
        #expect(WidgetContent.nextUpdate(after: late, fetch: .unavailable) == late.addingTimeInterval(WidgetContent.retryInterval))
        #expect(WidgetContent.nextUpdate(after: now, fetch: .ok(.sample), degraded: true) == now.addingTimeInterval(WidgetContent.retryInterval))
        // il reset del giorno arriva comunque prima se è più vicino
        let nearReset = reset.addingTimeInterval(-30)
        #expect(WidgetContent.nextUpdate(after: nearReset, fetch: .ok(.sample), degraded: true) == reset.addingTimeInterval(1))
    }

    /// Dopo un fallimento il widget ritenta tra due minuti: né "Lens non raggiungibile" né un
    /// riepilogo a metà restano 15 minuti sullo schermo.
    @Test func dopoUnFallimentoSiRitentaPresto() async {
        let lens = FakeLens()
        let now = BudgetReport.sample.now
        lens.budgetResult = .unavailable
        let down = await WidgetContent.load(.summary, now: now, settings: InMemorySettings()) { _ in lens }
        #expect(down.nextUpdate == now.addingTimeInterval(WidgetContent.retryInterval))
        lens.budgetResult = .ok(.sample)
        lens.modelsResult = nil
        for kind in [WidgetContent.Kind.summary, .ring, .trend] {
            let partial = await WidgetContent.load(kind, model: "openai/senza-budget", now: now, settings: InMemorySettings()) { _ in lens }
            #expect(partial.nextUpdate == now.addingTimeInterval(WidgetContent.retryInterval), "\(kind)")
        }
        lens.hourlyResult = nil
        lens.modelsResult = []
        let noTrend = await WidgetContent.load(.trend, now: now, settings: InMemorySettings()) { _ in lens }
        #expect(noTrend.nextUpdate == now.addingTimeInterval(WidgetContent.retryInterval))
    }

    /// Con /api/breakdown giù il riepilogo mostra i modelli con budget e la percentuale, non "0 / 0".
    @Test func riepilogoSenzaBreakdownNonInventaIToken() async {
        let lens = FakeLens()
        lens.modelsResult = nil
        let loaded = await WidgetContent.load(.summary, now: BudgetReport.sample.now, settings: InMemorySettings()) { _ in lens }
        guard case .summary(let summary) = loaded.content else {
            Issue.record("atteso .summary")
            return
        }
        #expect(summary.rows.map(\.name) == ["qwen3.5-9b-mlx"])
        #expect(summary.rows.first?.percent == "40%")
        #expect(summary.rows.first?.tokensIn == "—")
        #expect(summary.rows.first?.tokensOut == "—")
        // senza budget e senza breakdown non c'è nulla di vero da mostrare
        lens.budgetResult = .ok(report(day: dayWith(models: nil)))
        #expect(await WidgetContent.load(.summary, now: BudgetReport.sample.now, settings: InMemorySettings()) { _ in lens }.content == .message(WidgetContent.unreachable))
    }
}
