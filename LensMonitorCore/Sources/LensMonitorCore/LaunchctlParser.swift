import Foundation

/// Parsing dell'output testuale di `launchctl`.
public enum LaunchctlParser {
    public struct PrintInfo: Equatable, Sendable {
        public let running: Bool
        public let pid: Int?
    }

    /// Legge solo le righe di primo livello (un tab di rientro): i blocchi annidati,
    /// come "resource coalition", hanno a loro volta righe "state = …".
    public static func parsePrint(_ output: String) -> PrintInfo {
        var state: String?
        var pid: Int?
        for line in output.split(separator: "\n") {
            guard line.hasPrefix("\t"), !line.hasPrefix("\t\t") else { continue }
            let text = line.dropFirst()
            if text.hasPrefix("state = ") {
                state = String(text.dropFirst("state = ".count))
            } else if text.hasPrefix("pid = ") {
                pid = Int(text.dropFirst("pid = ".count))
            }
        }
        return PrintInfo(running: state == "running", pid: pid)
    }

    /// `true` se il servizio è disabilitato, `false` se abilitato, `nil` se non compare.
    public static func parseDisabled(_ output: String, label: String) -> Bool? {
        let key = "\"\(label)\" => "
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix(key) else { continue }
            switch text.dropFirst(key.count) {
            case "disabled": return true
            case "enabled": return false
            default: return nil
            }
        }
        return nil
    }
}
