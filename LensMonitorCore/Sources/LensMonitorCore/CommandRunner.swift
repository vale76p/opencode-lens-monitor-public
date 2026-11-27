import Foundation

/// Esito di un comando esterno.
public struct CommandResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String = "", stderr: String = "") {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Esegue un comando esterno. Nei test si sostituisce con un runner finto.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) async -> CommandResult
}

/// Runner reale: `Process` su una coda globale, fuori dal main actor.
public struct ProcessCommandRunner: CommandRunner {
    /// Secondi dopo cui un comando ancora in corso viene terminato: un launchctl bloccato
    /// terrebbe il Monitor occupato e il polling fermo.
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        let timeout = timeout
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runBlocking(executable, arguments, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stderr: error.localizedDescription)
        }
        let deadline = DispatchTime.now() + timeout
        // Watchdog: SIGTERM allo scadere, SIGKILL un secondo dopo se il processo lo ignora.
        let watched = ProcessBox(process)
        let timedOut = FlagBox()
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            guard watched.process.isRunning else { return }
            timedOut.set()
            watched.process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if watched.process.isRunning { kill(watched.process.processIdentifier, SIGKILL) }
            }
        }
        // I due pipe si leggono man mano, in parallelo (se uno si riempie l'altro non si blocca), e
        // non con readDataToEndOfFile, che torna solo all'EOF: un figlio che eredita il pipe e
        // sopravvive al comando (il watchdog termina solo quello) terrebbe bloccata per sempre la
        // continuation, e con lei il refresh che la aspetta.
        let outData = PipeReader(out.fileHandleForReading)
        let errData = PipeReader(err.fileHandleForReading)
        // Prima l'EOF dei pipe, poi waitUntilExit. Quando il comando esce il kernel chiude i pipe
        // subito, mentre Foundation si accorge dell'uscita da una coda di GCD che sotto carico (la
        // suite dei test, un Mac occupato) arriva con secondi di ritardo: con waitUntilExit per
        // primo il runner aspettava quel ritardo a ogni comando. Un figlio che tiene il pipe non
        // fa aspettare oltre la scadenza del watchdog.
        let outEnded = outData.waitForEnd(until: deadline)
        let errEnded = errData.waitForEnd(until: deadline)
        process.waitUntilExit()
        if !outEnded || !errEnded {
            // Il comando è uscito (da solo o per il watchdog) con i pipe ancora aperti: un attimo
            // per ciò che ha scritto uscendo, poi si tiene quello che c'è.
            let grace = DispatchTime.now() + 0.2
            _ = outData.waitForEnd(until: grace)
            _ = errData.waitForEnd(until: grace)
        }
        outData.stop()
        errData.stop()
        if timedOut.isSet {
            return CommandResult(status: -1, stderr: "timeout dopo \(Format.seconds(timeout))")
        }
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData.data, as: UTF8.self),
            stderr: String(decoding: errData.data, as: UTF8.self)
        )
    }
}

/// Accumula i byte di un pipe man mano che arrivano, dalla coda di Foundation del
/// `readabilityHandler`; `data` si legge dopo `stop()`.
private final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var buffer = Data()
    private let ended = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                // EOF: tutti gli scrittori hanno chiuso il pipe
                handle.readabilityHandler = nil
                ended.signal()
                return
            }
            lock.withLock { buffer.append(chunk) }
        }
    }

    /// `true` all'EOF; il semaforo resta segnalato, così una seconda attesa torna subito.
    @discardableResult
    func waitForEnd(until deadline: DispatchTime) -> Bool {
        guard ended.wait(timeout: deadline) == .success else { return false }
        ended.signal()
        return true
    }

    /// Toglie l'handler (che tiene vivo questo oggetto) senza chiudere il descrittore: si chiude
    /// da solo alla deallocazione del FileHandle, quando nessuna lettura può più essere in corso.
    func stop() {
        handle.readabilityHandler = nil
    }

    var data: Data { lock.withLock { buffer } }
}

/// Il `Process` sorvegliato dal watchdog, usato solo per `isRunning` e `terminate()`.
private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
