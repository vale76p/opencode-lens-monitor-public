import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct BudgetTests {
    /// Settimana, mese e i totali per periodo del JSON d'esempio si ignorano.
    @Test func decodificaIlGiorno() {
        let r = BudgetReport.sample
        #expect(r.now == Date(timeIntervalSince1970: 1_792_058_400))
        #expect(r.day.from == Date(timeIntervalSince1970: 1_792_015_200))
        #expect(r.day.to == Date(timeIntervalSince1970: 1_792_101_600))
        #expect(r.day.models == [ModelBudget(model: "lmstudio/qwen3.5-9b-mlx", used: 400, limit: 1000, ratio: 0.4, projectedRatio: 0.8, pace: .under)])
    }

    @Test func soloIlGiornoBasta() throws {
        let json = #"{"now":1792058400000,"periods":{"day":{"from":1792015200000,"to":1792101600000}}}"#
        let r = try LensJSON.decoder.decode(BudgetReport.self, from: Data(json.utf8))
        #expect(r.day.models == nil)
    }

    /// La lens manda `seen: false` per un modello con budget mai comparso in uno step; una lens
    /// vecchia non manda il campo e il modello vale visto.
    @Test func campoSeenOpzionale() throws {
        let never = #"{"model":"lmstudio/never-used","used":0,"limit":500000,"ratio":0,"projected":0,"projectedRatio":0,"pace":"under","seen":false}"#
        let old = #"{"model":"a/m","used":1,"limit":10,"ratio":0.1,"projectedRatio":null,"pace":"under"}"#
        let unseen = try LensJSON.decoder.decode(ModelBudget.self, from: Data(never.utf8))
        #expect(!unseen.seen)
        #expect(unseen.displayPercent == nil)
        #expect(unseen.displayProgress == nil)
        #expect(try LensJSON.decoder.decode(ModelBudget.self, from: Data(old.utf8)).seen)
    }

    @Test func ritmoSconosciutoValeNessunLimite() throws {
        let json = #"{"model":"a/m","used":1,"limit":10,"ratio":0.1,"projectedRatio":null,"pace":"turbo"}"#
        let budget = try LensJSON.decoder.decode(ModelBudget.self, from: Data(json.utf8))
        #expect(budget.pace == .noLimit)
    }

    /// Pannello e widget mostrano un budget con le stesse regole: percentuale (con il tetto di
    /// Format.percent), riempimento fermato tra 0 e 1 anche oltre il budget, "usati / budget".
    @Test func regoleDiVisualizzazioneCondivise() {
        let over = ModelBudget(model: "a/m", used: 18_000_000, limit: 15_000_000, ratio: 1.2, pace: .exceeded)
        #expect(over.displayPercent == "120%")
        #expect(over.displayProgress == 1)
        #expect(over.displayBudget == "18M / 15M")
        let under = ModelBudget(model: "a/m", used: 7_100_000, limit: 15_000_000, ratio: 0.473, pace: .under)
        #expect(under.displayPercent == "47%")
        #expect(under.displayProgress == 0.473)
        #expect(under.displayBudget == "7,1M / 15M")
        let unknown = ModelBudget(model: "a/m", used: 0, limit: 0, ratio: nil, pace: .noLimit)
        #expect(unknown.displayPercent == nil)
        #expect(unknown.displayProgress == nil)
        #expect(ModelBudget(model: "a/m", used: 0, limit: 10, ratio: -0.5, pace: .under).displayProgress == 0)
    }

    @Test func jsonNonValido() {
        #expect(throws: (any Error).self) {
            try LensJSON.decoder.decode(BudgetReport.self, from: Data("{}".utf8))
        }
    }
}
