import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct ListenerVerifierTests {
    let lsof = ["-nP", "-iTCP:4777", "-sTCP:LISTEN", "-Fp"]

    func check(_ result: CommandResult, pid: Int = 85289, environment: [String: String] = [:]) async -> ListenerCheck {
        let runner = FakeRunner()
        runner.on(lsof, result)
        return await LsofListenerVerifier(runner: runner, environment: environment).check(pid: pid, port: 4777)
    }

    @Test func stessoProcessoDelJob() async {
        #expect(await check(CommandResult(status: 0, stdout: "p85289\n")) == .verified)
        // IPv4 e IPv6 dello stesso processo: due righe con lo stesso pid, o una sola
        #expect(await check(CommandResult(status: 0, stdout: "p85289\np85289\n")) == .verified)
    }

    @Test func altroProcessoSullaPorta() async {
        #expect(await check(CommandResult(status: 0, stdout: "p4242\n")) == .foreign)
        // anche uno solo estraneo basta: il token non va a nessuno dei due
        #expect(await check(CommandResult(status: 0, stdout: "p85289\np4242\n")) == .foreign)
    }

    /// Fallimenti chiusi: niente pid, niente token.
    @Test func lsofCheNonRispondeNonVerifica() async {
        #expect(await check(CommandResult(status: 1)) == .unverified, "nessuno ascolta ancora")
        #expect(await check(CommandResult(status: -1, stderr: "timeout dopo 5 s")) == .unverified)
        #expect(await check(CommandResult(status: 0, stdout: "rumore\n")) == .unverified)
    }

    @Test func chiedeLsofSullaPortaGiusta() async {
        let runner = FakeRunner()
        runner.on(lsof, CommandResult(status: 0, stdout: "p1\n"))
        _ = await LsofListenerVerifier(runner: runner, environment: [:]).check(pid: 1, port: 4777)
        #expect(runner.calls == [lsof])
        #expect(runner.usedExecutables == ["/usr/sbin/lsof"])
    }

    /// Con LENS_MONITOR_PORT la porta è scelta a mano per provare un'altra lens: non si controlla.
    @Test func portaScelteAManoNonSiControlla() async {
        let runner = FakeRunner()
        let verifier = LsofListenerVerifier(runner: runner, environment: ["LENS_MONITOR_PORT": "4778"])
        #expect(await verifier.check(pid: 1, port: 4778) == .verified)
        #expect(runner.calls.isEmpty)
        // un valore non valido non conta come scelta
        #expect(await check(CommandResult(status: 0, stdout: "p4242\n"), environment: ["LENS_MONITOR_PORT": "x"]) == .foreign)
    }
}
