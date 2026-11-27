import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct CommandRunnerTests {
    let runner = ProcessCommandRunner()

    @Test func catturaStdoutEStatus() async {
        let result = await runner.run("/bin/echo", ["ciao"])
        #expect(result == CommandResult(status: 0, stdout: "ciao\n"))
    }

    @Test func catturaStderrEExitCode() async {
        let result = await runner.run("/bin/sh", ["-c", "echo errore >&2; exit 3"])
        #expect(result.status == 3)
        #expect(result.stdout == "")
        #expect(result.stderr == "errore\n")
    }

    @Test func eseguibileInesistenteDaStatusMenoUno() async {
        let result = await runner.run("/nonexistent/launchctl", [])
        #expect(result.status == -1)
        #expect(!result.stderr.isEmpty)
    }

    @Test func outputOltreIlBufferDellaPipeNonBlocca() async {
        let result = await runner.run("/bin/sh", ["-c", "yes a | head -c 200000; yes b | head -c 200000 >&2"])
        #expect(result.status == 0)
        #expect(result.stdout.count == 200_000)
        #expect(result.stderr.count == 200_000)
    }

    /// Un launchctl bloccato non deve tenere il Monitor occupato per sempre.
    @Test func comandoBloccatoTerminatoDopoIlTimeout() async {
        let started = Date()
        let result = await ProcessCommandRunner(timeout: 0.5).run("/bin/sleep", ["5"])
        #expect(result.status == -1)
        #expect(result.stderr == "timeout dopo 0,5 s")
        #expect(Date().timeIntervalSince(started) < 3)
    }

    /// Un figlio che eredita il pipe e sopravvive al comando (qui `sleep 3 &`) non deve tenere
    /// bloccata la lettura: il comando è finito, il suo esito torna con l'output letto fin lì
    /// entro la scadenza del watchdog, che termina solo il comando.
    @Test func figlioCheTieneIlPipeNonBloccaLaLettura() async {
        let started = Date()
        let result = await ProcessCommandRunner(timeout: 0.5).run("/bin/sh", ["-c", "sleep 3 & echo ciao; echo err >&2"])
        #expect(result.status == 0)
        #expect(result.stdout == "ciao\n")
        #expect(result.stderr == "err\n")
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func timeoutPredefinitoDi15Secondi() {
        #expect(ProcessCommandRunner().timeout == 15)
    }
}
