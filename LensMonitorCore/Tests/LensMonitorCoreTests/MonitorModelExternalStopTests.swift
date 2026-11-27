import Foundation
import Testing
@testable import LensMonitorCore

/// La lens fermata fuori dal Monitor (Impostazioni della lens: bootout + bootstrap senza enable):
/// per `externalRestartGrace` secondi è un riavvio, poi resta ferma con una nota che dice perché.
@MainActor
@Suite struct MonitorModelExternalStopTests {
    /// Lens attiva e poi scaricata da qualcun altro: il modello è in `.restarting`.
    private func stoppedOutside(atLogin: Bool) async -> Harness {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.controller.enabledAtLogin = atLogin
        await h.model.refresh()
        h.controller.load = .notLoaded
        await h.model.refresh()
        return h
    }

    @Test func stopEsternoMostraRiavvioPoiNotaDisabilitata() async {
        let h = await stoppedOutside(atLogin: false)
        #expect(h.model.state == .restarting)
        #expect(h.model.primaryAction == .start)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 19
        await h.model.refresh()
        #expect(h.model.state == .restarting)
        h.clock.now += 2
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == ExternalStop.disabledNote)
    }

    @Test func stopEsternoConLoginAttivoNotaGenerica() async {
        let h = await stoppedOutside(atLogin: true)
        #expect(h.model.state == .restarting)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 21
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == ExternalStop.otherNote)
    }

    /// La nota si ricalcola a ogni refresh: segue il toggle "Avvia la lens all'accesso".
    @Test func notaSegueLAvvioAlLogin() async {
        let h = await stoppedOutside(atLogin: false)
        h.clock.now += 21
        await h.model.refresh()
        #expect(h.model.externalStopNote == ExternalStop.disabledNote)
        h.controller.enabledAtLogin = true
        h.clock.now += 5
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == ExternalStop.otherNote)
    }

    /// Un `launchctl print` che non risponde tiene lo stato di prima, ma non fa ripartire la
    /// finestra: conta dal primo `notLoaded`.
    @Test func printSconosciutoNonFaRipartireLaFinestra() async {
        let h = await stoppedOutside(atLogin: false)
        #expect(h.model.state == .restarting)
        h.clock.now += 10
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        await h.model.refresh()
        #expect(h.model.state == .restarting)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 11
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == ExternalStop.disabledNote)
    }

    /// Un print che resta muto non tiene `.restarting` per sempre: scaduta la finestra la lens è
    /// ferma, con la nota.
    @Test func printSconosciutoOltreLaFinestraFerma() async {
        let h = await stoppedOutside(atLogin: false)
        #expect(h.model.state == .restarting)
        h.clock.now += 25
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == ExternalStop.disabledNote)
    }

    /// Primo refresh con il print muto (`.failed` da resolve), poi "non caricata": il job non era
    /// caricato, quindi nessuno l'ha fermato (es. riavvio del Mac con la lens fermata dal Monitor).
    @Test func printSconosciutoAlPrimoRefreshPoiFermoNonEStopEsterno() async {
        let h = Harness()
        h.controller.enabledAtLogin = false
        h.controller.load = .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s"))
        await h.model.refresh()
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 25
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
    }

    @Test func fermaInTimeoutNonEStopEsterno() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.controller.enabledAtLogin = false
        await h.model.refresh()
        h.controller.stopError = FakeError(message: "timeout dopo 15 s")
        h.controller.afterStop = nil            // il job resta caricato: bootout in timeout
        await h.model.stop()
        #expect(h.model.state == .running(opencodeConnected: true))
        h.controller.load = .notLoaded          // launchd finisce di scaricarlo dopo
        h.clock.now += 5
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 25
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
    }

    /// Oltre `ownStopGrace` un Ferma del Monitor non conta più: lo stop che arriva dopo è esterno.
    @Test func fermaDelMonitorScadutoNonCopreStopEsterno() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.controller.enabledAtLogin = false
        await h.model.refresh()
        h.controller.stopError = FakeError(message: "timeout dopo 15 s")
        h.controller.afterStop = nil
        await h.model.stop()
        h.clock.now += MonitorModel.ownStopGrace + 1
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.state == .restarting)
    }

    @Test func riavvioRiuscitoNellaFinestraNessunaNota() async {
        let h = await stoppedOutside(atLogin: false)
        #expect(h.model.state == .restarting)
        h.clock.now += 5
        h.controller.load = .loaded(running: true, pid: 2)
        await h.model.refresh()
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.externalStopNote == nil)
        // La finestra è chiusa: uno stop successivo ne apre una nuova da capo.
        h.clock.now += 30
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.state == .restarting)
    }

    @Test func stopEsternoAncheDaAvvioOErrore() async {
        // Da .starting: caricato ma non ancora in esecuzione.
        let starting = Harness()
        starting.controller.load = .loaded(running: false, pid: nil)
        await starting.model.refresh()
        #expect(starting.model.state == .starting)
        starting.controller.load = .notLoaded
        await starting.model.refresh()
        #expect(starting.model.state == .restarting)

        // Da .failed: la lens diagnostica.
        let failed = Harness()
        failed.controller.load = .loaded(running: true, pid: 1)
        failed.lens.healthResult = .diagnostic(reason: "schema troppo nuovo")
        await failed.model.refresh()
        #expect(failed.model.state == .failed("database non utilizzabile: schema troppo nuovo"))
        failed.controller.load = .notLoaded
        await failed.model.refresh()
        #expect(failed.model.state == .restarting)
    }

    @Test func fermaDelMonitorNonEStopEsterno() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        h.controller.enabledAtLogin = false
        await h.model.refresh()
        await h.model.stop()
        #expect(h.model.state == .stopped)
        h.clock.now += 25
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
    }

    @Test func primoRefreshFermoNonEStopEsterno() async {
        let h = Harness()
        h.controller.load = .notLoaded
        h.controller.enabledAtLogin = false
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 25
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
    }

    @Test func avviaDalMonitorAzzeraLaNota() async {
        let h = await stoppedOutside(atLogin: false)
        h.clock.now += 21
        await h.model.refresh()
        #expect(h.model.externalStopNote == ExternalStop.disabledNote)
        await h.model.start()
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.externalStopNote == nil)
    }

    /// Avvia mentre la finestra del riavvio è ancora aperta.
    @Test func avviaDuranteIlRiavvio() async {
        let h = await stoppedOutside(atLogin: false)
        #expect(h.model.state == .restarting)
        h.clock.now += 5
        await h.model.start()
        #expect(h.model.state == .running(opencodeConnected: true))
        #expect(h.model.externalStopNote == nil)
    }

    /// Avvia fallito subito dopo la nota: la nota sparisce (l'errore dice già cosa è successo) e
    /// lo stato fermo che segue non è uno stop esterno.
    @Test func avviaFallitoAzzeraLaNota() async {
        let h = await stoppedOutside(atLogin: false)
        h.clock.now += 21
        await h.model.refresh()
        h.controller.startError = FakeError(message: "bootstrap fallito")
        await h.model.start()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
        #expect(h.model.lastError == "bootstrap fallito")
    }

    @Test func cambioDiLensAzzeraLoStopEsterno() async {
        let h = Harness()
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.state == .restarting)
        await h.model.selectTarget(.local(host: "127.0.0.1", port: 4790))
        #expect(h.model.state != .restarting)
        #expect(h.model.externalStopNote == nil)
        await h.model.selectTarget(.service)
        h.clock.now += 30
        await h.model.refresh()
        #expect(h.model.state == .stopped)
        #expect(h.model.externalStopNote == nil)
    }

    @Test func lensDiSviluppoMaiRiavvioEsterno() async {
        let h = Harness()
        await h.model.selectTarget(.local(host: "127.0.0.1", port: 4790))
        #expect(h.model.state == .running(opencodeConnected: true))
        h.lens.current = nil
        await h.model.refresh()
        #expect(h.model.state == .unreachable)
        #expect(h.model.externalStopNote == nil)
        h.clock.now += 30
        await h.model.refresh()
        #expect(h.model.state == .unreachable)
        #expect(h.model.externalStopNote == nil)
    }
}
