import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct PanelStateTests {
    let now = BudgetReport.sample.now
    let models = [ModelUsage(key: "opencode/claude-opus-4-8", last: nil, tokensIn: 12_300, tokensOut: 4_500, tokensTotal: 7_100_000)]

    func make(_ service: ServiceState = .running(opencodeConnected: true), usage: UsageSnapshot?) -> PanelState {
        PanelState.make(service: service, usage: usage, now: now, timeZone: TimeZone(identifier: "Europe/Rome")!)
    }

    @Test func inEsecuzioneConBudget() {
        let p = make(usage: UsageSnapshot(budget: .sample, models: models))
        #expect(p.dot == .green)
        #expect(p.menuBarText == "40%")
        #expect(p.models == [
            PanelState.ModelRow(name: "claude-opus-4-8", tokensIn: "12,3k", tokensOut: "4,5k"),
            PanelState.ModelRow(name: "qwen3.5-9b-mlx", percent: "40%", progress: 0.4, budget: "400 / 1k", pace: .under, tokensIn: "0", tokensOut: "0"),
        ])
        #expect(p.today == PanelState.Today(date: "15/10/2026", percent: "40%", progress: 0.4, pace: .under, alert: .under, total: "7,1M", detail: "Budget di 1 modello"))
        #expect(p.notice == nil)
    }

    @Test func oggiMediaDeiModelliConBudget() {
        let day = BudgetReport.sample.day
        let budgets = [
            ModelBudget(model: "a/m1", used: 0, limit: 10, ratio: 0.9, projectedRatio: 1.8, pace: .over),
            ModelBudget(model: "a/m2", used: 0, limit: 10, ratio: 0.3, projectedRatio: 0.6, pace: .under),
            ModelBudget(model: "a/m3", used: 0, limit: 10, ratio: 0, projectedRatio: 0, pace: .under),
        ]
        let report = BudgetReport(now: BudgetReport.sample.now, periods: .init(
            day: BudgetPeriod(from: day.from, to: day.to, models: budgets)))
        let rome = TimeZone(identifier: "Europe/Rome")!
        let today = PanelState.today(report, models: [], timeZone: rome)
        #expect(today.percent == "40%")
        #expect(today.pace == .under, "proiezione media 0,8: in linea anche se un modello è sopra il ritmo")
        #expect(today.alert == .over, "il pallino segue il modello messo peggio")
        #expect(today.total == "0")
        #expect(today.detail == "Media di 3 modelli con budget")

        let none = BudgetReport(now: report.now, periods: .init(
            day: BudgetPeriod(from: day.from, to: day.to, models: nil)))
        let empty = PanelState.today(none, models: [], timeZone: rome)
        #expect(empty.percent == nil)
        #expect(empty.progress == nil)
        #expect(empty.pace == .noLimit)
        #expect(empty.detail == "Nessun budget per modello attivo (LENS_MODEL_LIMITS)")
        #expect(empty.alert == .noLimit)
    }

    func pesati(_ ratios: [Double], projected: [Double]? = nil, extra: [ModelBudget] = []) -> BudgetReport {
        let budgets = ratios.enumerated().map { i, r in
            ModelBudget(model: "a/m\(i + 1)", used: 0, limit: 10, ratio: r, projectedRatio: projected?[i], pace: .under)
        }
        return report(day: dayWith(models: budgets + extra))
    }

    /// 8 giorni: A ~95% al giorno, B ~90%, C ~10% del budget (limite 10), pesi 7,65 / 7,3 / 0,8;
    /// A anche con una variante, che conta come lo stesso modello.
    let storia = [
        ModelUsage(key: "a/m1", last: nil, tokensTotal: 50),
        ModelUsage(key: "a/m1#high", last: nil, tokensTotal: 26.5),
        ModelUsage(key: "a/m2", last: nil, tokensTotal: 73),
        ModelUsage(key: "a/m3", last: nil, tokensTotal: 8),
    ]
    let rome = TimeZone(identifier: "Europe/Rome")!

    @Test func oggiPesatoSullUsoAbituale() {
        let today = PanelState.today(pesati([1, 1, 0.1], projected: [1.2, 1.2, 0.2]), models: [], history: storia, timeZone: rome)
        #expect(today.percent == "95%", "media semplice 70%")
        #expect(today.progress.map { ($0 * 100).rounded() } == 95)
        #expect(today.pace == .over, "proiezione pesata 1,15; la media semplice 0,87 sarebbe in linea")
        #expect(today.detail == "Media pesata sull'uso di 7 giorni (3 modelli)")
    }

    @Test func alMattinoIlModelloLeggeroNonGonfia() {
        let today = PanelState.today(pesati([0.05, 0.05, 0.3]), models: [], history: storia, timeZone: rome)
        #expect(today.percent == "6%", "media semplice 13%")
    }

    @Test func modelloMaiUsatoNonPesa() {
        let mai = ModelBudget(model: "a/m4", used: 0, limit: 10, ratio: 0, projectedRatio: nil, pace: .under)
        let today = PanelState.today(pesati([1, 1, 0.1], extra: [mai]), models: [], history: storia, timeZone: rome)
        #expect(today.percent == "95%")
        #expect(today.detail == "Media pesata sull'uso di 7 giorni (3 modelli)")
    }

    @Test func unSoloModelloUsatoNonEUnaMedia() {
        let storia = [ModelUsage(key: "a/m1", last: nil, tokensTotal: 50)]
        let today = PanelState.today(pesati([0.8, 0]), models: [], history: storia, timeZone: rome)
        #expect(today.percent == "80%")
        #expect(today.detail == "Budget di 1 modello (gli altri non usati in 7 giorni)")
    }

    @Test func leVariantiPesanoComeIlModello() {
        let storia = [
            ModelUsage(key: "a/m1#high", last: nil, tokensTotal: 76.5),
            ModelUsage(key: "a/m2", last: nil, tokensTotal: 73),
            ModelUsage(key: "a/m3", last: nil, tokensTotal: 8),
        ]
        let today = PanelState.today(pesati([1, 1, 0.1]), models: [], history: storia, timeZone: rome)
        #expect(today.percent == "95%", "senza sommare la variante a/m1 peserebbe 0: 91%")
        #expect(today.detail == "Media pesata sull'uso di 7 giorni (3 modelli)")
    }

    @Test func senzaStoriaMediaSemplice() {
        for history in [nil, [], [ModelUsage(key: "x/altro", last: nil, tokensTotal: 99)]] as [[ModelUsage]?] {
            let today = PanelState.today(pesati([1, 1, 0.1]), models: [], history: history, timeZone: rome)
            #expect(today.percent == "70%")
            #expect(today.detail == "Media di 3 modelli con budget")
        }
    }

    @Test func makePassaLaStoria() {
        let p = make(usage: UsageSnapshot(budget: pesati([1, 1, 0.1]), models: [], history: storia))
        #expect(p.menuBarText == "95%")
    }

    @Test func etichettaSenzaBudgetPerModello() {
        let day = BudgetReport.sample.day
        let report = BudgetReport(now: now, periods: .init(
            day: BudgetPeriod(from: day.from, to: day.to, models: [])))
        let p = make(usage: UsageSnapshot(budget: report))
        #expect(p.dot == .gray)
        #expect(p.menuBarText == "")
    }

    @Test func unModelloSuperatoColoraIlPallinoAncheConMediaInLinea() {
        let day = BudgetReport.sample.day
        let report = BudgetReport(now: now, periods: .init(
            day: BudgetPeriod(from: day.from, to: day.to, models: [
                ModelBudget(model: "a/m1", used: 0, limit: 1, ratio: 1.5, projectedRatio: 1.6, pace: .exceeded),
                ModelBudget(model: "a/m2", used: 0, limit: 1, ratio: 0, projectedRatio: 0, pace: .under),
            ])))
        let p = make(usage: UsageSnapshot(budget: report))
        #expect(p.menuBarText == "75%")
        #expect(p.dot == .red)
        #expect(p.today?.pace == .under, "proiezione media 0,8")
        #expect(p.today?.alert == .exceeded)
    }

    /// Un modello con budget che la lens non ha mai visto (nome sbagliato in LENS_MODEL_LIMITS) non
    /// è uno 0% vero: fuori da media, conteggio e colore, e la riga lo dice.
    @Test func modelloMaiVistoFuoriDaMediaEColore() {
        let day = BudgetReport.sample.day
        let budgets = [
            ModelBudget(model: "a/m1", used: 0, limit: 10, ratio: 0.77, projectedRatio: 0.8, pace: .under),
            ModelBudget(model: "a/m2", used: 0, limit: 10, ratio: 0.0004, projectedRatio: 0.0008, pace: .under),
            ModelBudget(model: "lmstudio/never-used", used: 0, limit: 500_000, ratio: 0, projectedRatio: 0, pace: .under, seen: false),
        ]
        let report = BudgetReport(now: now, periods: .init(day: BudgetPeriod(from: day.from, to: day.to, models: budgets)))
        let today = PanelState.today(report, models: [], timeZone: TimeZone(identifier: "Europe/Rome")!)
        #expect(today.percent == "39%")
        #expect(today.detail == "Media di 2 modelli con budget")
        let rows = PanelState.modelRows([], budgets: budgets)
        let never = rows.first { $0.name == "never-used" }
        #expect(never?.note == ModelBudget.unseenNote)
        #expect(never?.percent == nil && never?.progress == nil)
        #expect(never?.pace == .noLimit)
        #expect(rows.filter { $0.note != nil }.count == 1)
    }

    @Test func tuttiMaiVistiComeSenzaBudget() {
        let day = BudgetReport.sample.day
        let budgets = [ModelBudget(model: "x/y", used: 0, limit: 1, ratio: 0, projectedRatio: 0, pace: .exceeded, seen: false)]
        let report = BudgetReport(now: now, periods: .init(day: BudgetPeriod(from: day.from, to: day.to, models: budgets)))
        let p = make(usage: UsageSnapshot(budget: report))
        #expect(p.dot == .gray)
        #expect(p.menuBarText == "")
        #expect(p.today?.alert == .noLimit)
        #expect(p.today?.detail == "Nessun budget per modello attivo (LENS_MODEL_LIMITS)")
    }

    @Test func senzaBreakdownITokenSonoTrattini() {
        let budget = ModelBudget(model: "a/m", used: 5, limit: 10, ratio: 0.5, pace: .under)
        #expect(PanelState.modelRows(nil, budgets: [budget]).map(\.tokensIn) == ["—"])
        #expect(PanelState.modelRows([], budgets: [budget]).map(\.tokensIn) == ["0"])
    }

    @Test func modelloOltreIlBudgetSempreVisibile() {
        let t = { (s: Double) in Date(timeIntervalSince1970: s) }
        let models = (1...6).map { ModelUsage(key: "a/m\($0)", last: t(Double(100 - $0))) }
        let rows = PanelState.modelRows(models, budgets: [ModelBudget(model: "a/m6", used: 2, limit: 1, ratio: 2, pace: .exceeded)])
        #expect(rows.map(\.name) == ["m1", "m2", "m3", "m4", "m6"])
    }

    @Test func giornoDiBudgetFinitoNonEOggi() {
        let late = BudgetReport.sample.day.to.addingTimeInterval(60)
        let p = PanelState.make(service: .running(opencodeConnected: true), usage: UsageSnapshot(budget: .sample, stale: true), now: late)
        #expect(p.today == nil)
        #expect(p.menuBarText == "")
        #expect(p.modelsReset == nil)
        #expect(p.dot == .gray)
    }

    @Test func stessoModelloDaDueProvider() {
        let rows = PanelState.modelRows([
            ModelUsage(key: "anthropic/claude-sonnet-4-5#max", last: Date(timeIntervalSince1970: 20), tokensIn: 1_000, tokensOut: 100),
            ModelUsage(key: "github-copilot/claude-sonnet-4-5", last: Date(timeIntervalSince1970: 10), tokensIn: 500, tokensOut: 50),
            ModelUsage(key: "openai/gpt-5.5", last: Date(timeIntervalSince1970: 5), tokensIn: 7, tokensOut: 1),
        ], budgets: [
            ModelBudget(model: "anthropic/claude-sonnet-4-5", used: 600, limit: 1_000, ratio: 0.6, pace: .under),
            ModelBudget(model: "github-copilot/claude-sonnet-4-5", used: 2_000, limit: 1_000, ratio: 2, pace: .exceeded),
        ])
        #expect(rows.map(\.name) == ["anthropic/claude-sonnet-4-5", "github-copilot/claude-sonnet-4-5", "gpt-5.5"])
        #expect(rows.map(\.percent) == ["60%", "200%", nil])
        #expect(rows.map(\.tokensIn) == ["1k", "500", "7"])
    }

    @Test func etichettaColorataDalRitmoDiOggi() {
        let day = BudgetReport.sample.day
        let report = BudgetReport(now: now, periods: .init(
            day: BudgetPeriod(from: day.from, to: day.to, models: [ModelBudget(model: "a/m", used: 0, limit: 1, ratio: 1.2, projectedRatio: 2.4, pace: .exceeded)])))
        let p = make(usage: UsageSnapshot(budget: report))
        #expect(p.dot == .red)
        #expect(p.menuBarText == "120%")
    }

    @Test func servizioNonAttivo() {
        let usage = UsageSnapshot(budget: .sample)
        #expect(make(.stopped, usage: usage).dot == .gray)
        #expect(make(.stopped, usage: usage).menuBarText == "")
        #expect(make(.starting, usage: nil).dot == .gray)
        #expect(make(.notInstalled, usage: nil).dot == .warning)
        #expect(make(.failed("x"), usage: nil).dot == .warning)
        #expect(make(.running(opencodeConnected: true), usage: nil).dot == .gray)
    }

    @Test func lensTroppoVecchiaPrevaleSuDatiNonDisponibili() {
        let stale = UsageSnapshot(stale: true)
        let p = PanelState.make(service: .running(opencodeConnected: true), usage: stale, lensVersion: "0.37.0", now: now)
        #expect(p.notice == PanelState.outdatedNotice)
    }

    @Test func lensTroppoVecchiaAncheSenzaDati() {
        #expect(PanelState.make(service: .running(opencodeConnected: true), usage: nil, lensVersion: "0.30.0", now: now).notice == PanelState.outdatedNotice)
    }

    @Test func versioneSupportataOIgnotaNessunAvviso() {
        #expect(PanelState.make(service: .running(opencodeConnected: true), usage: UsageSnapshot(), lensVersion: "0.44.0", now: now).notice == nil)
        #expect(PanelState.make(service: .running(opencodeConnected: true), usage: UsageSnapshot(), lensVersion: nil, now: now).notice == nil)
        #expect(PanelState.make(service: .running(opencodeConnected: true), usage: UsageSnapshot(stale: true), lensVersion: nil, now: now).notice == PanelState.unavailableNotice)
    }

    /// Lens attiva ma prima lettura di /api/budget fallita: senza avviso il pannello resterebbe vuoto.
    @Test func datiNonDisponibili() {
        let p = make(usage: UsageSnapshot(stale: true))
        #expect(p.notice == "Dati della lens non disponibili: nuovo tentativo tra poco")
        #expect(p.today == nil)
        // con dati vecchi già presenti si mostrano quelli, senza avviso
        #expect(make(usage: UsageSnapshot(budget: .sample, stale: true)).notice == nil)
        // prima del primo refresh nessun avviso
        #expect(make(usage: nil).notice == nil)
    }

    @Test func modelliRaggruppatiPerNomeDalPiuRecente() {
        let t = { (s: Double) in Date(timeIntervalSince1970: s) }
        let usage = UsageSnapshot(models: [
            ModelUsage(key: "opencode/claude-opus-4-8#max", last: t(200)),
            ModelUsage(key: "opencode/claude-opus-4-8", last: t(100)),
            ModelUsage(key: "openai/gpt-5.5", last: t(300)),
            ModelUsage(key: "a/m1", last: t(50)),
            ModelUsage(key: "a/m2", last: t(40)),
            ModelUsage(key: "a/m3", last: t(30)),
            ModelUsage(key: "a/m4", last: nil),
        ])
        let rows = make(usage: usage).models
        #expect(rows.map(\.name) == ["gpt-5.5", "claude-opus-4-8", "m1", "m2", "m3"])
    }

    @Test func modelliConTokenEBudgetDelGiorno() {
        let rows = PanelState.modelRows([
            ModelUsage(key: "lmstudio/qwen3.5-9b-mlx#think", last: Date(timeIntervalSince1970: 10), tokensIn: 1_000, tokensOut: 200),
            ModelUsage(key: "lmstudio/qwen3.5-9b-mlx", last: Date(timeIntervalSince1970: 20), tokensIn: 500, tokensOut: 100),
        ], budgets: [
            ModelBudget(model: "lmstudio/qwen3.5-9b-mlx", used: 1_800, limit: 1_000, ratio: 1.8, pace: .exceeded),
            ModelBudget(model: "openai/gpt-5.5", used: 0, limit: 5_000, ratio: 0, pace: .under),
        ])
        #expect(rows == [
            PanelState.ModelRow(name: "qwen3.5-9b-mlx", percent: "180%", progress: 1, budget: "1,8k / 1k", pace: .exceeded, tokensIn: "1,5k", tokensOut: "300"),
            PanelState.ModelRow(name: "gpt-5.5", percent: "0%", progress: 0, budget: "0 / 5k", pace: .under, tokensIn: "0", tokensOut: "0"),
        ])
    }

    @Test func resetDelGiornoSottoIModelli() {
        // giorno d'esempio: 12 h al reset, che è a mezzanotte ora di Roma
        let p = make(usage: UsageSnapshot(budget: .sample))
        #expect(p.modelsReset == "Reset in 12h 00m alle 00:00")
    }

    @Test func coloriEBadgeDelRitmo() {
        #expect(Pace.under.color == .green)
        #expect(Pace.over.color == .orange)
        #expect(Pace.exceeded.color == .red)
        #expect(Pace.noLimit.color == .gray)
        #expect(Pace.under.badge == "In linea")
        #expect(Pace.exceeded.badge == "Superato")
        #expect(Pace.noLimit.badge == nil)
    }
}
