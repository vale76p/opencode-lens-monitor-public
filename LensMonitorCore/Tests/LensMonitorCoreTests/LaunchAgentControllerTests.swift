import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct LaunchAgentControllerTests {
    let runner = FakeRunner()
    let plist = URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/local.opencode-lens.plist")
    let target = "gui/501/local.opencode-lens"

    func controller(installed: Bool = true) -> LaunchAgentController {
        LaunchAgentController(runner: runner, uid: 501, plistURL: plist, fileExists: { _ in installed })
    }

    func notLoaded() { runner.on(["print", target], CommandResult(status: 113, stderr: "Bad request.\n")) }
    func loaded() { runner.on(["print", target], CommandResult(status: 0, stdout: Fixtures.printRunning)) }
    func enabled() { runner.on(["print-disabled", "gui/501"], CommandResult(status: 0, stdout: Fixtures.enabledWithLens)) }
    func disabled() { runner.on(["print-disabled", "gui/501"], CommandResult(status: 0, stdout: Fixtures.disabledWithLens)) }

    @Test func installatoSeIlPlistEsiste() {
        #expect(controller(installed: true).isInstalled)
        #expect(!controller(installed: false).isInstalled)
    }

    @Test func statusNonCaricato() async {
        notLoaded()
        #expect(await controller().status() == .notLoaded)
        #expect(runner.usedExecutables == ["/bin/launchctl"])
    }

    /// Un print fallito per altro (timeout del runner, errore di launchd) non vuol dire "fermo".
    @Test func statusSconosciutoSePrintFallisceAltrimenti() async {
        runner.on(["print", target], CommandResult(status: -1, stderr: "timeout dopo 15 s"))
        #expect(await controller().status() == .unknown(LaunchctlError(command: "print", status: -1, stderr: "timeout dopo 15 s")))
    }

    @Test func startEStopConStatoSconosciutoFalliscono() async {
        runner.on(["print", target], CommandResult(status: 5, stderr: "Input/output error\n"))
        let error = LaunchctlError(command: "print", status: 5, stderr: "Input/output error\n")
        await #expect(throws: error) { try await controller().start() }
        await #expect(throws: error) { try await controller().stop() }
        #expect(!runner.calls.contains(["bootout", target]))
        #expect(!runner.calls.contains(["bootstrap", "gui/501", plist.path]))
    }

    @Test func bootoutInTimeoutMaServizioScaricatoNonEUnErrore() async throws {
        runner.on(["print", target], CommandResult(status: 0, stdout: Fixtures.printRunning), CommandResult(status: 113))
        runner.on(["bootout", target], CommandResult(status: -1, stderr: "timeout dopo 15 s"))
        try await controller().stop()
        #expect(runner.calls == [["print", target], ["bootout", target], ["print", target]])
    }

    @Test func bootoutFallitoConServizioAncoraCaricatoLanciaLErrore() async {
        loaded()
        runner.on(["bootout", target], CommandResult(status: 5, stderr: "Boot-out failed\n"))
        await #expect(throws: LaunchctlError(command: "bootout", status: 5, stderr: "Boot-out failed\n")) {
            try await controller().stop()
        }
    }

    /// Senza riga in print-disabled il servizio risulta abilitato, ma launchd può rifiutarne il
    /// bootstrap (Disabled nel plist): si riprova dopo un enable.
    @Test func bootstrapRifiutatoDaAbilitatoRiprovaConEnable() async throws {
        notLoaded()
        enabled()
        runner.on(["bootstrap", "gui/501", plist.path],
                  CommandResult(status: 5, stderr: "Bootstrap failed: 5: Input/output error\n"), CommandResult(status: 0))
        try await controller().start()
        #expect(runner.calls.suffix(3) == [
            ["bootstrap", "gui/501", plist.path],
            ["enable", target],
            ["bootstrap", "gui/501", plist.path],
        ])
    }

    @Test func statusInEsecuzione() async {
        loaded()
        #expect(await controller().status() == .loaded(running: true, pid: 85289))
    }

    @Test func avvioAlLogin() async {
        disabled()
        #expect(await controller().isEnabledAtLogin() == false)
    }

    @Test func avvioAlLoginSenzaRigaOConComandoFallito() async {
        runner.on(["print-disabled", "gui/501"], CommandResult(status: 0, stdout: Fixtures.disabledWithoutLens))
        #expect(await controller().isEnabledAtLogin() == true)
        let failing = FakeRunner()
        failing.on(["print-disabled", "gui/501"], CommandResult(status: 1))
        let c = LaunchAgentController(runner: failing, uid: 501, plistURL: plist, fileExists: { _ in true })
        #expect(await c.isEnabledAtLogin() == true)
    }

    @Test func startDaFermoEAbilitato() async throws {
        notLoaded()
        enabled()
        try await controller().start()
        #expect(runner.calls == [
            ["print", target],
            ["print-disabled", "gui/501"],
            ["bootstrap", "gui/501", plist.path],
        ])
    }

    @Test func startDaFermoEDisabilitatoRiabilitaSoloPerLAvvio() async throws {
        notLoaded()
        disabled()
        try await controller().start()
        #expect(runner.calls == [
            ["print", target],
            ["print-disabled", "gui/501"],
            ["enable", target],
            ["bootstrap", "gui/501", plist.path],
            ["disable", target],
        ])
    }

    @Test func bootstrapFallitoDaDisabilitatoRipristinaDisable() async {
        notLoaded()
        disabled()
        runner.on(["bootstrap", "gui/501", plist.path],
                  CommandResult(status: 5, stderr: "Bootstrap failed: 5: Input/output error\n"))
        await #expect(throws: LaunchctlError(command: "bootstrap", status: 5,
                                             stderr: "Bootstrap failed: 5: Input/output error\n")) {
            try await controller().start()
        }
        #expect(runner.calls.last == ["disable", target])
        // Il bootstrap fallito fa rileggere print (ancora 113): non è la corsa con l'helper della lens.
        #expect(runner.calls.filter { $0 == ["print", target] }.count == 2)
    }

    /// Corsa con l'helper di `reloadService` della lens: il suo bootstrap ha vinto, il nostro fallisce.
    @Test func avviaDaDisabilitatoBootstrapFallitoMaCaricatoERiuscito() async throws {
        runner.on(["print", target], CommandResult(status: 113), CommandResult(status: 0, stdout: Fixtures.printRunning))
        disabled()
        runner.on(["bootstrap", "gui/501", plist.path], CommandResult(status: 5, stderr: "Bootstrap failed: 5: Input/output error\n"))
        try await controller().start()
        #expect(runner.calls.last == ["disable", target])   // la scelta "non al login" resta
    }

    @Test func avviaDaAbilitatoSecondoBootstrapFallitoMaCaricatoERiuscito() async throws {
        runner.on(["print", target], CommandResult(status: 113), CommandResult(status: 0, stdout: Fixtures.printRunning))
        enabled()
        runner.on(["bootstrap", "gui/501", plist.path], CommandResult(status: 5, stderr: "x\n"), CommandResult(status: 5, stderr: "x\n"))
        try await controller().start()
        #expect(runner.calls.filter { $0.first == "bootstrap" }.count == 2)
    }

    @Test func avviaDaAbilitatoDueBootstrapFallitiENonCaricatoLanciaIlPrimoErrore() async {
        notLoaded(); enabled()
        runner.on(["bootstrap", "gui/501", plist.path], CommandResult(status: 5, stderr: "primo\n"), CommandResult(status: 5, stderr: "secondo\n"))
        await #expect(throws: LaunchctlError(command: "bootstrap", status: 5, stderr: "primo\n")) { try await controller().start() }
    }

    @Test func startGiaCaricatoFaKickstart() async throws {
        loaded()
        try await controller().start()
        #expect(runner.calls == [["print", target], ["kickstart", target]])
    }

    @Test func stopCaricatoFaBootout() async throws {
        loaded()
        try await controller().stop()
        #expect(runner.calls == [["print", target], ["bootout", target]])
    }

    @Test func stopNonCaricatoNonFaNulla() async throws {
        notLoaded()
        try await controller().stop()
        #expect(runner.calls == [["print", target]])
    }

    @Test func setEnabledAtLogin() async throws {
        try await controller().setEnabledAtLogin(false)
        try await controller().setEnabledAtLogin(true)
        #expect(runner.calls == [["disable", target], ["enable", target]])
    }

    @Test func messaggioDErroreUsaSoloLaPrimaRigaDiStderr() {
        let error = LaunchctlError(command: "bootout", status: 3, stderr: "\nBoot-out failed: 3: No such process\naltro\n")
        #expect(error.errorDescription == "launchctl bootout non riuscito (3): Boot-out failed: 3: No such process")
    }
}
