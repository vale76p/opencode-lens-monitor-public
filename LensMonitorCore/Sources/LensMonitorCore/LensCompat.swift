import Foundation

/// Versione minima della lens che il Monitor supporta.
public enum LensCompat {
    /// 0.38 è una scelta di supporto, non un limite tecnico: da lì in poi gli zip sono firmati e la
    /// lens si aggiorna dalla dashboard, quindi chi è più indietro ha un modo semplice per mettersi
    /// in pari. Tecnicamente il Monitor funzionerebbe già dalla ~0.30 (/healthz diagnostico).
    public static let minimum = "0.38.0"

    /// `true` se `version` è almeno `minimum`; `nil` se non si legge (es. prefisso `v`, testo
    /// qualsiasi): in dubbio il pannello non mostra avvisi. Suffissi `-…` e `+…` sono ignorati e una
    /// patch mancante vale 0.
    public static func isSupported(_ version: String) -> Bool? {
        guard let current = components(version), let floor = components(minimum) else { return nil }
        return current.lexicographicallyPrecedes(floor) == false
    }

    private static func components(_ version: String) -> [Int]? {
        let core = version.prefix { $0 != "-" && $0 != "+" }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (2...3).contains(parts.count), !parts.contains(nil) else { return nil }
        let numbers = parts.compactMap { $0 }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }
}
