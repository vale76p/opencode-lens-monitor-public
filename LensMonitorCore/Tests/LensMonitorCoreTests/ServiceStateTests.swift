import Testing
@testable import LensMonitorCore

@Suite struct ServiceStateTests {
    @Test func riavvioInCorsoOffreAvvia() {
        #expect(ServiceState.restarting.primaryAction == .start)
        #expect(!ServiceState.restarting.isRunning)
        #expect(ServiceState.restarting.cardTitle == "Riavvio in corso…")
        #expect(ServiceState.restarting.statusDot == .gray)
        #expect(ServiceState.restarting.shortText == "riavvio in corso…")
        #expect(ServiceState.restarting.statusText == "OpenCode Lens — si sta riavviando fuori dal Monitor")
        #expect(ServiceState.restarting.symbolName == "eye")
        #expect(ServiceState.externalRestartGrace == 20)
    }

    let connected = LensHealth(opencode: "connected")
    let disconnected = LensHealth(opencode: "disconnected")

    func resolve(installed: Bool = true, _ load: LoadState, _ health: LensHealth? = nil, startingFor: Double = 0) -> ServiceState {
        ServiceState.resolve(installed: installed, load: load, health: health.map { .ok($0) } ?? .unavailable, startingFor: startingFor)
    }

    /// La lens diagnostica è su e dice perché non ha i dati: l'errore compare subito, non dopo i
    /// 15 s dell'avvio, e con il motivo invece di "/healthz non risponde".
    @Test func diagnosticaFallisceSubitoConIlMotivo() {
        let diagnostic = HealthFetch.diagnostic(reason: "database con schema 12, più nuovo di questa lens (11)")
        #expect(ServiceState.resolve(installed: true, load: .loaded(running: true, pid: 1), health: diagnostic, startingFor: 0) ==
            .failed("database non utilizzabile: database con schema 12, più nuovo di questa lens (11)"))
        #expect(ServiceState.resolve(installed: true, load: .loaded(running: true, pid: 1), health: diagnostic, startingFor: 20) ==
            .failed("database non utilizzabile: database con schema 12, più nuovo di questa lens (11)"))
        // Non installato e fermo non cambiano: launchctl ha la precedenza su /healthz.
        #expect(ServiceState.resolve(installed: false, load: .loaded(running: true, pid: 1), health: diagnostic, startingFor: 0) == .notInstalled)
        #expect(ServiceState.resolve(installed: true, load: .notLoaded, health: diagnostic, startingFor: 0) == .stopped)
    }

    /// Da un client non locale la lens dà già un motivo generico che comincia allo stesso modo.
    @Test func motivoGenericoNonRaddoppiato() {
        let generic = HealthFetch.diagnostic(reason: "database non utilizzabile (dettagli su questo computer)")
        #expect(ServiceState.resolve(installed: true, load: .loaded(running: true, pid: 1), health: generic, startingFor: 0) ==
            .failed("database non utilizzabile (dettagli su questo computer)"))
    }

    /// Lens di sviluppo: niente launchctl, solo /healthz.
    @Test func lensDiSviluppo() {
        #expect(ServiceState.resolve(local: .ok(connected)) == .running(opencodeConnected: true))
        #expect(ServiceState.resolve(local: .ok(disconnected)) == .running(opencodeConnected: false))
        #expect(ServiceState.resolve(local: .unavailable) == .unreachable)
        #expect(ServiceState.resolve(local: .diagnostic(reason: "file rovinato")) == .failed("database non utilizzabile: file rovinato"))
    }

    @Test func nonInstallato() {
        #expect(resolve(installed: false, .loaded(running: true, pid: 1), connected) == .notInstalled)
    }

    @Test func fermo() {
        #expect(resolve(.notLoaded) == .stopped)
    }

    @Test func caricatoNonInEsecuzione() {
        #expect(resolve(.loaded(running: false, pid: nil)) == .starting)
        #expect(resolve(.loaded(running: false, pid: nil), startingFor: 14.9) == .starting)
        #expect(resolve(.loaded(running: false, pid: nil), startingFor: 15) ==
            .failed("caricato ma non in esecuzione: controlla il log"))
    }

    @Test func inEsecuzioneSenzaHealthz() {
        #expect(resolve(.loaded(running: true, pid: 1)) == .starting)
        #expect(resolve(.loaded(running: true, pid: 1), startingFor: 20) ==
            .failed("in esecuzione ma /healthz non risponde"))
    }

    @Test func inEsecuzione() {
        #expect(resolve(.loaded(running: true, pid: 1), connected) == .running(opencodeConnected: true))
        #expect(resolve(.loaded(running: true, pid: 1), disconnected) == .running(opencodeConnected: false))
    }

    @Test func iconeTestiEAzioni() {
        #expect(ServiceState.running(opencodeConnected: true).symbolName == "eye.fill")
        #expect(ServiceState.running(opencodeConnected: false).symbolName == "eye")
        #expect(ServiceState.starting.symbolName == "eye")
        #expect(ServiceState.stopped.symbolName == "eye.slash")
        #expect(ServiceState.notInstalled.symbolName == "eye.trianglebadge.exclamationmark")
        #expect(ServiceState.failed("x").symbolName == "eye.trianglebadge.exclamationmark")

        #expect(ServiceState.running(opencodeConnected: true).statusText == "OpenCode Lens — attivo (OpenCode collegato)")
        #expect(ServiceState.running(opencodeConnected: false).statusText == "OpenCode Lens — attivo (OpenCode non collegato)")
        #expect(ServiceState.starting.statusText == "OpenCode Lens — avvio in corso…")
        #expect(ServiceState.stopped.statusText == "OpenCode Lens — fermo")
        #expect(ServiceState.notInstalled.statusText == "Non installato: installa opencode-lens con bash install.sh")
        #expect(ServiceState.failed("boom").statusText == "OpenCode Lens — errore: boom")

        #expect(ServiceState.notInstalled.primaryAction == nil)
        #expect(ServiceState.stopped.primaryAction == .start)
        #expect(ServiceState.starting.primaryAction == .stop)
        #expect(ServiceState.failed("x").primaryAction == .stop)
        #expect(ServiceState.running(opencodeConnected: true).primaryAction == .stop)

        #expect(ServiceState.running(opencodeConnected: false).isRunning)
        #expect(!ServiceState.starting.isRunning)
    }

    @Test func testiBreviECard() {
        #expect(ServiceState.running(opencodeConnected: true).shortText == "OpenCode")
        #expect(ServiceState.running(opencodeConnected: false).shortText == "OpenCode")
        #expect(ServiceState.running(opencodeConnected: true).statusDot == .green)
        #expect(ServiceState.running(opencodeConnected: false).statusDot == .orange)
        #expect(ServiceState.stopped.statusDot == .gray)
        #expect(ServiceState.unreachable.statusDot == .gray)
        #expect(ServiceState.failed("x").statusDot == .warning)
        #expect(ServiceState.starting.shortText == "avvio in corso…")
        #expect(ServiceState.stopped.shortText == "lens ferma")
        #expect(ServiceState.notInstalled.shortText == "lens non installata")
        #expect(ServiceState.failed("x").shortText == "errore")
        #expect(ServiceState.stopped.cardTitle == "Lens ferma")
        #expect(ServiceState.starting.cardTitle == "Avvio in corso…")
        #expect(ServiceState.failed("x").cardTitle == "Errore della lens")
        #expect(ServiceState.notInstalled.cardTitle == "Lens non installata")
        #expect(ServiceState.running(opencodeConnected: true).cardTitle == "Lens attiva")
    }
}
