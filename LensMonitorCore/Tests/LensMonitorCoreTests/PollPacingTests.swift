import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct PollPacingTests {
    func interval(_ group: PollPacing.Group, busy: Bool = false, stable: TimeInterval = 0, action: TimeInterval? = nil, usage: TimeInterval? = nil) -> TimeInterval {
        PollPacing.interval(group: group, busy: busy, stableFor: stable, sinceUserAction: action, untilUsageRefresh: usage)
    }

    @Test func famiglieDiStati() {
        #expect(PollPacing.Group(.starting) == .waiting)
        #expect(PollPacing.Group(.restarting) == .waiting)
        #expect(PollPacing.Group(.checking) == .waiting)
        #expect(PollPacing.Group(.running(opencodeConnected: false)) == .running)
        #expect(PollPacing.Group(.failed("x")) == .failing)
        #expect(PollPacing.Group(.unreachable) == .failing)
        #expect(PollPacing.Group(.stopped) == .stopped)
        #expect(PollPacing.Group(.notInstalled) == .stopped)
    }

    @Test func occupatoEInAttesaCinqueSecondi() {
        #expect(interval(.running, busy: true, stable: 9_999) == 5)
        #expect(interval(.stopped, busy: true, stable: 9_999) == 5)
        #expect(interval(.waiting, stable: 9_999) == 5)
    }

    @Test func inEsecuzioneQuindiciSecondi() {
        #expect(interval(.running) == 15)
        #expect(interval(.running, stable: 86_400) == 15)
    }

    @Test func ilRefreshDeiDatiNonVieneRitardato() {
        #expect(interval(.running, usage: 7) == 7)
        #expect(interval(.running, usage: 40) == 15)
        #expect(interval(.running, usage: -3) == 1)
        #expect(interval(.stopped, stable: 9_999, usage: 2) == 60, "con la lens ferma non ci sono dati da rileggere")
    }

    @Test func erroreConBackoffFinoASessanta() {
        #expect(interval(.failing, stable: 0) == 5)
        #expect(interval(.failing, stable: 60) == 15)
        #expect(interval(.failing, stable: 200) == 30)
        #expect(interval(.failing, stable: 301) == 60)
        #expect(interval(.failing, stable: 86_400) == 60)
    }

    @Test func fermoProlungatoRallenta() {
        #expect(interval(.stopped, stable: 10) == 15)
        #expect(interval(.stopped, stable: 600) == 30)
        #expect(interval(.stopped, stable: 901) == 60)
    }

    /// Avvia/Ferma/Riavvia e l'apertura del pannello riportano a 5 s per `boostWindow`, anche dopo
    /// ore di backoff; poi il ritmo torna quello dello stato.
    @Test func unAzioneDellUtenteRiportaACinqueSecondi() {
        #expect(interval(.stopped, stable: 9_999, action: 0) == 5)
        #expect(interval(.failing, stable: 9_999, action: 29) == 5)
        #expect(interval(.running, action: 5) == 5)
        #expect(interval(.failing, stable: 9_999, action: 30) == 60)
        #expect(interval(.running, action: 31) == 15)
    }
}
