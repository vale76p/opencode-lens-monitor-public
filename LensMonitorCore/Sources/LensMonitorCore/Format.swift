import Foundation

/// Testi del pannello e dei widget, in italiano (virgola decimale), indipendenti dalla lingua del sistema.
public enum Format {
    /// Tetto delle conversioni a intero: ben oltre ogni valore reale (token, minuti, percentuali) e
    /// abbastanza lontano da `Int.max` perché le somme e le divisioni dopo la conversione restino sicure.
    public static let maxInt = 1_000_000_000_000_000

    /// `Int(value)` che non va in trap: `Int(Double)` si ferma con NaN, infiniti e valori oltre
    /// `Int.max`, e un numero fuori scala dalla lens farebbe chiudere l'app a ogni refresh anche dopo
    /// il riavvio. NaN vale 0, il resto si limita a ±`maxInt`.
    public static func int(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        return Int(min(max(value, -Double(maxInt)), Double(maxInt)))
    }

    /// Riga del reset di pannello e widget, "Reset in 04h 12m alle 06:00": minuti per difetto, mai
    /// negativi, ora in formato 24 ore.
    public static func resetLine(from now: Date, to reset: Date, timeZone: TimeZone = .current) -> String {
        let minutes = max(int(reset.timeIntervalSince(now) / 60), 0)
        return String(format: "Reset in %02dh %02dm alle ", minutes / 60, minutes % 60) + clock(reset, timeZone: timeZone)
    }

    /// Data, "17/10/2026".
    public static func date(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.day, .month, .year], from: date)
        return String(format: "%02d/%02d/%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }

    /// Ora del giorno, "06:00".
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Token compatti: 950, 12,3k, 50M.
    public static func tokens(_ value: Double) -> String {
        compact(value)
    }

    /// 0,523 → "52%", anche oltre il 100%. Sotto il budget al massimo "99%": "100%" arrotondato
    /// accanto a "In linea" sembrerebbe un budget già superato.
    public static func percent(_ ratio: Double) -> String {
        let value = int((ratio * 100).rounded())
        return "\(ratio < 1 ? min(value, 99) : value)%"
    }

    /// "46 s", "1 min 5 s", "2 min".
    public static func nextRefresh(in seconds: TimeInterval) -> String {
        let total = max(0, int(seconds.rounded(.up)))
        if total < 60 { return "\(total) s" }
        let rest = total % 60
        return rest == 0 ? "\(total / 60) min" : "\(total / 60) min \(rest) s"
    }

    /// Voce dell'intervallo dei dati nelle impostazioni (15 s, 1 min, 5 min).
    public static func interval(_ seconds: TimeInterval) -> String {
        nextRefresh(in: seconds)
    }

    /// L'intervallo nella frase del popover ⓘ: "ogni minuto", "ogni 30 s".
    public static func every(_ seconds: TimeInterval) -> String {
        seconds == 60 ? "ogni minuto" : "ogni \(interval(seconds))"
    }

    /// Riga sotto le card: in pausa senza refresh previsto, in corso quando il tempo è scaduto
    /// (il refresh parte al giro successivo del poll, che con la lens attiva non aspetta più del refresh), altrimenti il conto alla rovescia.
    public static func refreshStatus(next: Date?, now: Date) -> String {
        guard let next else { return "Aggiornamento in pausa" }
        let seconds = next.timeIntervalSince(now)
        return seconds <= 0 ? "Aggiornamento in corso…" : "Prossimo aggiornamento tra \(nextRefresh(in: seconds))"
    }

    /// Dalla chiave `provider/modello#variante` della lens tiene `provider/modello`: la stessa
    /// chiave dei budget per modello, con le varianti insieme.
    public static func modelKey(_ key: String) -> String {
        key.split(separator: "#", maxSplits: 1).first.map(String.init) ?? key
    }

    /// Dalla chiave `provider/modello#variante` della lens tiene `modello`.
    public static func modelName(_ key: String) -> String {
        let withoutVariant = key.split(separator: "#", maxSplits: 1).first.map(String.init) ?? key
        guard let slash = withoutVariant.firstIndex(of: "/") else { return withoutVariant }
        return String(withoutVariant[withoutVariant.index(after: slash)...])
    }

    /// Il suffisso si sceglie sul valore già arrotondato a un decimale: 999.950 diventa "1M", non "1000k".
    static func compact(_ raw: Double) -> String {
        let value = raw.isNaN ? 0 : min(max(raw, -Double(maxInt)), Double(maxInt))
        if value.rounded() < 1000 { return String(int(value.rounded())) }
        let sizes: [(Double, String)] = [(1e3, "k"), (1e6, "M"), (1e9, "G")]
        // Il primo suffisso con cui il valore, arrotondato a un decimale, sta sotto 1000. Oltre i
        // 999,95G resta "G" (5e12 → "5000G"): non c'è un caso "G non basta".
        let (size, suffix) = sizes.first { (value / $0.0 * 10).rounded() / 10 < 1000 } ?? sizes[sizes.count - 1]
        return oneDecimal((value / size * 10).rounded() / 10) + suffix
    }

    /// "15 s", "0,5 s": secondi con al più un decimale, per il messaggio di timeout del runner.
    public static func seconds(_ value: TimeInterval) -> String {
        oneDecimal(value) + " s"
    }

    /// Un decimale, senza lo zero finale: "1,5", "12".
    private static func oneDecimal(_ value: Double) -> String {
        let text = decimal(value, digits: 1)
        return text.hasSuffix(",0") ? String(text.dropLast(2)) : text
    }

    static func decimal(_ value: Double, digits: Int) -> String {
        String(format: "%.\(digits)f", value).replacingOccurrences(of: ".", with: ",")
    }
}
