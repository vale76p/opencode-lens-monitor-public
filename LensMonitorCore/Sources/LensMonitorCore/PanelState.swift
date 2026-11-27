import Foundation

/// Colore del pallino nella barra, delle barre e degli anelli.
public enum StatusColor: Equatable, Sendable {
    case green, orange, red, gray, warning
}

extension Pace {
    public var color: StatusColor {
        switch self {
        case .under: .green
        case .over: .orange
        case .exceeded: .red
        case .noLimit: .gray
        }
    }

    /// Testo del badge; `nil` senza limite.
    public var badge: String? {
        switch self {
        case .under: "In linea"
        case .over: "Sopra il ritmo"
        case .exceeded: "Superato"
        case .noLimit: nil
        }
    }
}

/// Tutto ciò che pannello ed etichetta mostrano, ricavato da stato del servizio e dati della lens.
public struct PanelState: Equatable, Sendable {
    /// Il giorno di budget della lens: token di tutti i modelli e media dei loro budget.
    public struct Today: Equatable, Sendable {
        /// Inizio del giorno di budget, "17/10/2026".
        public let date: String
        /// Media delle percentuali dei modelli con un budget giornaliero, pesata sull'uso degli ultimi
        /// 7 giorni quando c'è (`today`); `nil` se nessuno ne ha.
        public let percent: String?
        /// Riempimento della barra, 0…1; `nil` senza budget.
        public let progress: Double?
        /// Ritmo della media: colore della barra.
        public let pace: Pace
        /// Ritmo del modello messo peggio: colore del pallino e badge. Con la media un modello oltre
        /// il budget e uno fermo darebbero "In linea" e nasconderebbero lo sforamento.
        public let alert: Pace
        /// Token di oggi di tutti i modelli, cache compresa, es. "7,1M".
        public let total: String
        /// "Media pesata sull'uso di 7 giorni (2 modelli)", "Media di 2 modelli con budget", o la
        /// variabile da impostare.
        public let detail: String
    }

    /// Un modello usato oggi, o con un budget giornaliero.
    public struct ModelRow: Equatable, Sendable, Identifiable {
        public let name: String
        /// Token di oggi contro il budget giornaliero del modello, es. "40%"; `nil` senza budget.
        public let percent: String?
        /// Riempimento della barra, 0…1; `nil` senza budget.
        public let progress: Double?
        /// Token di oggi su budget giornaliero, es. "7,1M / 100M"; `nil` senza budget.
        public let budget: String?
        public let pace: Pace
        public let tokensIn: String
        public let tokensOut: String
        /// Al posto della barra: il budget c'è ma la lens non ha mai visto il modello (`ModelBudget.seen`).
        public let note: String?
        public var id: String { name }

        public init(name: String, percent: String? = nil, progress: Double? = nil, budget: String? = nil, pace: Pace = .noLimit, tokensIn: String, tokensOut: String, note: String? = nil) {
            self.name = name
            self.percent = percent
            self.progress = progress
            self.budget = budget
            self.pace = pace
            self.tokensIn = tokensIn
            self.tokensOut = tokensOut
            self.note = note
        }
    }

    public static let outdatedNotice = "Aggiorna opencode-lens: serve la 0.38 o successiva"
    public static let unavailableNotice = "Dati della lens non disponibili: nuovo tentativo tra poco"
    public static let maxModels = 5

    /// Colore del ritmo di oggi (media dei budget dei modelli), come la card Oggi.
    public let dot: StatusColor
    /// Percentuale di oggi nella barra; vuota senza budget per modello o con il servizio non attivo.
    public let menuBarText: String
    public let today: Today?
    public let models: [ModelRow]
    /// Sotto i modelli: tra quanto e a che ora si azzera il giorno di budget, es.
    /// "Reset in 04h 12m alle 06:00"; `nil` senza /api/budget.
    public let modelsReset: String?
    public let notice: String?

    public static func make(service: ServiceState, usage: UsageSnapshot?, lensVersion: String? = nil, now: Date, timeZone: TimeZone = .current) -> PanelState {
        // Dopo un refresh fallito il report resta, ma un giorno di budget già finito non è "oggi".
        let report = usage?.budget.flatMap { $0.day.to > now ? $0 : nil }
        // Self.today e il tipo esplicito: la costante si chiama come la funzione, e lo Swift 6.3 di
        // Xcode 26 va in crash ("failed to produce diagnostic") se deve risolvere il nome da solo.
        let today: Today? = report.map { Self.today($0, models: usage?.models ?? [], history: usage?.history, timeZone: timeZone) }
        let dot: StatusColor = switch service {
        case .notInstalled, .failed: .warning
        case .running: today?.alert.color ?? .gray
        case .stopped, .starting, .unreachable, .checking, .restarting: .gray
        }
        return PanelState(
            dot: dot,
            menuBarText: service.isRunning ? (today?.percent ?? "") : "",
            today: today,
            models: modelRows(usage?.models, budgets: report?.day.models ?? []),
            modelsReset: report.map { modelsReset($0, now: now, timeZone: timeZone) },
            notice: notice(usage, lensVersion: lensVersion)
        )
    }

    /// Lens più vecchia della versione minima (vale anche senza dati: è la causa, non un sintomo),
    /// altrimenti prima lettura fallita senza dati da mostrare. Una versione illeggibile non avvisa.
    static func notice(_ usage: UsageSnapshot?, lensVersion: String?) -> String? {
        if let lensVersion, LensCompat.isSupported(lensVersion) == false { return outdatedNotice }
        guard let usage else { return nil }
        if usage.stale && usage.budget == nil { return unavailableNotice }
        return nil
    }

    static func modelsReset(_ report: BudgetReport, now: Date, timeZone: TimeZone) -> String {
        Format.resetLine(from: now, to: report.day.to, timeZone: timeZone)
    }

    /// La percentuale è la media dei modelli con budget pesata su `history`: ogni modello conta per i
    /// suoi token della finestra diviso il suo budget, così un modello leggero usato apposta poco non
    /// abbassa il totale e uno mai usato non c'entra. Senza storia (o senza uso) è la media semplice,
    /// dove anche i modelli non ancora usati oggi contano 0%. In entrambi i casi restano fuori quelli
    /// che la lens non ha mai visto (`seen == false`). La proiezione della barra usa gli stessi pesi;
    /// il ritmo del pallino è il peggiore tra i modelli.
    static func today(_ report: BudgetReport, models: [ModelUsage], history: [ModelUsage]? = nil, timeZone: TimeZone) -> Today {
        let budgets = report.day.countedModels
        var used: [String: Double] = [:]
        for m in history ?? [] { used[Format.modelKey(m.key), default: 0] += m.tokensTotal }
        let usage = budgets.map { (used[$0.model] ?? 0) / $0.limit }
        let weighted = usage.reduce(0, +) > 0
        let weights = weighted ? usage : budgets.map { _ in 1.0 }
        let mean = { (value: (ModelBudget) -> Double) in
            zip(budgets, weights).reduce(0) { $0 + value($1.0) * $1.1 } / weights.reduce(0, +)
        }
        let ratio = budgets.isEmpty ? nil : mean { $0.ratio ?? 0 }
        let projected = budgets.allSatisfy { $0.projectedRatio != nil } && !budgets.isEmpty
            ? mean { $0.projectedRatio ?? 0 }
            : nil
        let count = budgets.count
        let singleUsed = weighted && usage.filter { $0 > 0 }.count == 1
        return Today(
            date: Format.date(report.day.from, timeZone: timeZone),
            percent: ratio.map(Format.percent),
            progress: ratio.map { min(max($0, 0), 1) },
            pace: Pace(ratio: ratio, projectedRatio: projected),
            alert: budgets.map(\.pace).max { $0.severity < $1.severity } ?? .noLimit,
            total: Format.tokens(models.reduce(0) { $0 + $1.tokensTotal }),
            // senza budget anche quando LENS_MODEL_LIMITS c'è ma nessun suo modello è nella
            // configurazione di OpenCode: la lens conta solo quelli attivi
            detail: count == 0 ? "Nessun budget per modello attivo (LENS_MODEL_LIMITS)"
                : count == 1 ? "Budget di 1 modello"
                // con un solo modello usato la percentuale è la sua, non una media
                : singleUsed ? "Budget di 1 modello (gli altri non usati in 7 giorni)"
                : weighted ? "Media pesata sull'uso di 7 giorni (\(usage.filter { $0 > 0 }.count) modelli)"
                : "Media di \(count) modelli con budget"
        )
    }

    /// Modelli di oggi (`nil`: /api/breakdown non ha risposto) raggruppati per `provider/modello` (varianti insieme), dal più recente, poi
    /// quelli con un budget giornaliero non ancora usati oggi; al massimo `limit`. Il nome è quello breve,
    /// con il provider solo se due righe avrebbero lo stesso nome (lo stesso modello da due provider).
    static func modelRows(_ models: [ModelUsage]?, budgets: [ModelBudget], limit: Int = maxModels) -> [ModelRow] {
        var byKey: [String: (tokensIn: Double, tokensOut: Double, last: Date)] = [:]
        for model in models ?? [] {
            let key = Format.modelKey(model.key)
            let entry = byKey[key] ?? (0, 0, .distantPast)
            byKey[key] = (entry.tokensIn + model.tokensIn, entry.tokensOut + model.tokensOut, max(entry.last, model.last ?? .distantPast))
        }
        let budgetByKey = Dictionary(budgets.map { ($0.model, $0) }, uniquingKeysWith: { first, _ in first })
        let used = byKey
            .sorted { $0.value.last != $1.value.last ? $0.value.last > $1.value.last : $0.key < $1.key }
            .map { (key: $0.key, tokensIn: $0.value.tokensIn, tokensOut: $0.value.tokensOut) }
        let unused = budgetByKey.keys.filter { byKey[$0] == nil }.sorted().map { (key: $0, tokensIn: 0.0, tokensOut: 0.0) }
        // Un modello oltre il budget o sopra il ritmo resta sempre visibile: il pallino lo segnala,
        // la riga deve dire quale. Gli altri riempiono i posti rimasti, nell'ordine di prima.
        let all = used + unused
        let alerting = Set(all.map(\.key).filter { (budgetByKey[$0].flatMap { $0.seen ? $0.pace.severity : nil } ?? 0) >= Pace.over.severity })
        let others = all.filter { !alerting.contains($0.key) }.prefix(max(0, limit - alerting.count)).map(\.key)
        let kept = alerting.union(others)
        let rows = all.filter { kept.contains($0.key) }
        // Senza /api/breakdown i token non si sanno: "—", non uno "0" che sembra vero.
        let tokens = { (value: Double) in models == nil ? "—" : Format.tokens(value) }
        let shortNames = Dictionary(grouping: rows, by: { Format.modelName($0.key) })
        return rows.map { row in
            let budget = budgetByKey[row.key]
            let short = Format.modelName(row.key)
            return ModelRow(
                name: (shortNames[short]?.count ?? 0) > 1 ? row.key : short,
                percent: budget?.displayPercent,
                progress: budget?.displayProgress,
                budget: budget?.displayBudget,
                pace: budget.flatMap { $0.seen ? $0.pace : nil } ?? .noLimit,
                tokensIn: tokens(row.tokensIn),
                tokensOut: tokens(row.tokensOut),
                note: budget.flatMap { $0.seen ? nil : ModelBudget.unseenNote }
            )
        }
    }
}
