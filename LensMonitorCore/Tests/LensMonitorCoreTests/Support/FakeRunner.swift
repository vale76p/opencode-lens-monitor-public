import Foundation
@testable import LensMonitorCore

/// Registra le chiamate e restituisce risposte programmate per argomenti.
/// Più risposte per gli stessi argomenti si consumano in ordine; l'ultima resta.
/// Senza risposta programmata: status 0, output vuoto.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: [CommandResult]] = [:]
    private var recorded: [[String]] = []
    private var executables: Set<String> = []

    var calls: [[String]] { lock.withLock { recorded } }
    var usedExecutables: Set<String> { lock.withLock { executables } }

    func on(_ arguments: [String], _ results: CommandResult...) {
        lock.withLock { responses[arguments.joined(separator: " "), default: []] += results }
    }

    func run(_ executable: String, _ arguments: [String]) async -> CommandResult {
        lock.withLock {
            recorded.append(arguments)
            executables.insert(executable)
            let key = arguments.joined(separator: " ")
            guard var list = responses[key], let first = list.first else { return CommandResult(status: 0) }
            if list.count > 1 {
                list.removeFirst()
                responses[key] = list
            }
            return first
        }
    }
}
