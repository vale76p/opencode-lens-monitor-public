import Testing
@testable import LensMonitorCore

@Suite struct PowerMenuTests {
    @Test func avviaConLaLensFerma() {
        #expect(PowerMenu.items(primaryAction: .start, busy: false) == [
            PowerMenu.Item(title: "Avvia lens", enabled: true, action: .start),
            PowerMenu.Item(title: "Esci dal Monitor", enabled: true, action: .quit),
        ])
    }

    @Test func fermaConLaLensAttiva() {
        #expect(PowerMenu.items(primaryAction: .stop, busy: false).map(\.title) == ["Ferma lens", "Esci dal Monitor"])
    }

    /// Durante Avvia/Ferma l'azione sul servizio è spenta, Esci no.
    @Test func azioneSpentaMentreBusy() {
        let items = PowerMenu.items(primaryAction: .stop, busy: true)
        #expect(items.map(\.enabled) == [false, true])
        #expect(PowerMenu.items(primaryAction: .start, busy: true).first?.enabled == false)
    }

    /// Lens di sviluppo o servizio non installato: il Monitor non controlla nulla, resta solo Esci.
    @Test func soloEsciSenzaAzione() {
        #expect(PowerMenu.items(primaryAction: nil, busy: false) == [PowerMenu.Item(title: "Esci dal Monitor", enabled: true, action: .quit)])
    }

    @Test func separatorePrimaDiEsci() {
        let items = PowerMenu.items(primaryAction: .stop, busy: false)
        #expect(items.map(\.separatorBefore) == [false, true])
    }
}
