import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct FormatTests {
    static let base = Date(timeIntervalSince1970: 1_000_000)

    @Test(arguments: [
        (0.0, "0"), (950, "950"), (5000, "5k"), (12_300, "12,3k"),
        (12_345_678, "12,3M"), (50_000_000, "50M"), (2_500_000_000, "2,5G"),
    ] as [(Double, String)])
    func token(value: Double, expected: String) {
        #expect(Format.tokens(value) == expected)
    }

    /// Dopo l'arrotondamento a un decimale si passa al suffisso successivo: niente "1000k".
    @Test(arguments: [
        (999.0, "999"), (999.5, "1k"), (999.6, "1k"), (999_949, "999,9k"), (999_950, "1M"),
        (999_500_000, "999,5M"), (999_950_000, "1G"), (1_000_000, "1M"), (5e12, "5000G"),
    ] as [(Double, String)])
    func tokenAlConfine(value: Double, expected: String) {
        #expect(Format.tokens(value) == expected)
    }

    @Test(arguments: [(15.0, "15 s"), (0.5, "0,5 s"), (2.5, "2,5 s"), (0, "0 s")] as [(Double, String)])
    func secondi(value: Double, expected: String) {
        #expect(Format.seconds(value) == expected)
    }

    @Test func percentuale() {
        #expect(Format.percent(0.523) == "52%")
        #expect(Format.percent(0.996) == "99%")
        #expect(Format.percent(1) == "100%")
        #expect(Format.percent(1.004) == "100%")
        let base = Date(timeIntervalSince1970: 1_792_058_400)
        let utc = TimeZone(identifier: "UTC")!
        #expect(Format.resetLine(from: base, to: base.addingTimeInterval(4 * 3600 + 12 * 60 + 59), timeZone: utc) == "Reset in 04h 12m alle 14:12")
        #expect(Format.resetLine(from: base, to: base.addingTimeInterval(25 * 3600), timeZone: utc) == "Reset in 25h 00m alle 11:00")
        #expect(Format.resetLine(from: base, to: base.addingTimeInterval(-60), timeZone: utc) == "Reset in 00h 00m alle 09:59")
        #expect(Format.clock(base, timeZone: TimeZone(identifier: "UTC")!) == "10:00")
        #expect(Format.date(base, timeZone: TimeZone(identifier: "UTC")!) == "15/10/2026")
        #expect(Format.date(Date(timeIntervalSince1970: 1_767_225_600), timeZone: TimeZone(identifier: "UTC")!) == "01/01/2026")
        #expect(Format.percent(1.75) == "175%")
        #expect(Format.percent(0) == "0%")
    }

    @Test(arguments: [(46.0, "46 s"), (45.2, "46 s"), (65, "1 min 5 s"), (120, "2 min"), (-3, "0 s")] as [(Double, String)])
    func prossimoAggiornamento(seconds: Double, expected: String) {
        #expect(Format.nextRefresh(in: seconds) == expected)
    }

    /// Il refresh da 60 s parte al giro successivo del poll da 5 s: scaduto il tempo, la riga
    /// dice che l'aggiornamento è in corso invece di restare su "tra 0 s".
    @Test func rigaDelRefresh() {
        let now = Self.base
        #expect(Format.refreshStatus(next: nil, now: now) == "Aggiornamento in pausa")
        #expect(Format.refreshStatus(next: now.addingTimeInterval(46), now: now) == "Prossimo aggiornamento tra 46 s")
        #expect(Format.refreshStatus(next: now.addingTimeInterval(0.4), now: now) == "Prossimo aggiornamento tra 1 s")
        #expect(Format.refreshStatus(next: now, now: now) == "Aggiornamento in corso…")
        #expect(Format.refreshStatus(next: now.addingTimeInterval(-3), now: now) == "Aggiornamento in corso…")
    }

    @Test(arguments: [(15.0, "15 s", "ogni 15 s"), (60, "1 min", "ogni minuto"), (300, "5 min", "ogni 5 min")] as [(Double, String, String)])
    func intervalloDeiDati(seconds: Double, label: String, every: String) {
        #expect(Format.interval(seconds) == label)
        #expect(Format.every(seconds) == every)
    }

    @Test func nomeDelModello() {
        #expect(Format.modelName("opencode/claude-opus-4-8#max") == "claude-opus-4-8")
        #expect(Format.modelName("openai/gpt-5.5") == "gpt-5.5")
        #expect(Format.modelName("lmstudio/qwen/qwen3.5-9b") == "qwen/qwen3.5-9b")
        #expect(Format.modelName("solo") == "solo")
    }

    /// `Int(Double)` va in trap con NaN, infiniti e valori oltre Int.max: un numero fuori scala dalla
    /// lens non deve far chiudere l'app (che al riavvio rilegge lo stesso valore e si richiude).
    @Test(arguments: [1e300, -1e300, Double.nan, .infinity, -.infinity] as [Double])
    func valoriFuoriScalaNonVannoInTrap(value: Double) {
        #expect(!Format.percent(value).isEmpty)
        #expect(!Format.tokens(value).isEmpty)
        #expect(!Format.nextRefresh(in: value).isEmpty)
        #expect(!Format.resetLine(from: Self.base, to: Date(timeIntervalSince1970: value), timeZone: TimeZone(identifier: "UTC")!).isEmpty)
        #expect(Format.int(value) >= -Format.maxInt && Format.int(value) <= Format.maxInt)
    }

    @Test func conversioneSicura() {
        #expect(Format.int(52.4) == 52)
        #expect(Format.int(-3.9) == -3)
        #expect(Format.int(.nan) == 0)
        #expect(Format.int(1e300) == Format.maxInt)
        #expect(Format.int(-1e300) == -Format.maxInt)
        #expect(Format.percent(.nan) == "0%")
        #expect(Format.tokens(.nan) == "0")
        #expect(Format.tokens(-1e300).hasPrefix("-"))
    }
}
