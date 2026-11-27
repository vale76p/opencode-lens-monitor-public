import Foundation

/// Il modello seguito da un widget piccolo o medio, con le cifre del giorno di budget.
public struct ModelDay: Equatable, Sendable {
    /// `provider/modello`, la chiave dei budget.
    public let key: String
    public let name: String
    /// Token di oggi su budget giornaliero, "42%", senza tener conto di quanto manca al reset;
    /// `nil` senza budget.
    public let percent: String?
    /// Riempimento dell'anello, 0…1; `nil` senza budget.
    public let progress: Double?
    /// Token di oggi, cache compresa, "7,1M".
    public let used: String
    /// "7,1M / 15M"; `nil` senza budget.
    public let budget: String?
    public let pace: Pace
    /// Fine del giorno di budget.
    public let reset: Date

    public init(key: String, name: String, percent: String?, progress: Double?, used: String, budget: String?, pace: Pace, reset: Date) {
        self.key = key
        self.name = name
        self.percent = percent
        self.progress = progress
        self.used = used
        self.budget = budget
        self.pace = pace
        self.reset = reset
    }

    /// "Reset in 04h 12m alle 06:00" all'ora di una voce della timeline: il tempo resta giusto
    /// tra un aggiornamento dei dati e l'altro.
    public func resetLine(at now: Date, timeZone: TimeZone = .current) -> String {
        Format.resetLine(from: now, to: reset, timeZone: timeZone)
    }

    /// Senza budget (tolto da LENS_MODEL_LIMITS dopo averlo scelto) i token vengono da
    /// /api/breakdown, varianti insieme.
    public static func make(key: String, report: BudgetReport, models: [ModelUsage]?) -> ModelDay {
        let budget = report.day.models?.first { $0.model == key }
        let used = budget?.used ?? (models ?? []).filter { Format.modelKey($0.key) == key }.reduce(0) { $0 + $1.tokensTotal }
        return ModelDay(
            key: key,
            name: Format.modelName(key),
            percent: budget?.displayPercent,
            progress: budget?.displayProgress,
            used: Format.tokens(used),
            budget: budget?.displayBudget,
            pace: budget?.pace ?? .noLimit,
            reset: report.day.to
        )
    }
}

/// Andamento del giorno di budget di un modello: token di ogni ora dal reset.
public struct DayTrend: Equatable, Sendable {
    public struct Point: Equatable, Sendable, Identifiable {
        /// Ore dal reset, a metà dell'ora: 0,5 è la prima.
        public let hour: Double
        public let value: Double
        public var id: Double { hour }
    }

    public struct Tick: Equatable, Sendable, Identifiable {
        public let hour: Double
        /// Ora locale, "06".
        public let label: String
        public var id: Double { hour }
    }

    /// Fino all'ora in corso compresa: le ore che devono ancora venire non sono zero, non ci sono.
    public let points: [Point]
    /// Riferimento tratteggiato: budget giornaliero diviso le ore del giorno; `nil` senza budget.
    public let average: Double?
    /// Ore del giorno di budget, fine dell'asse: 24, o 23 e 25 nei giorni del cambio d'ora.
    public let hours: Int
    /// Etichette dell'asse ogni 6 ore dal reset.
    public let ticks: [Tick]

    public init(points: [Point], average: Double?, hours: Int, ticks: [Tick]) {
        self.points = points
        self.average = average
        self.hours = hours
        self.ticks = ticks
    }

    /// `values`: un valore per ora da `report.day.from`, come lo dà /api/timeseries.
    public static func make(values: [Double], key: String, report: BudgetReport, timeZone: TimeZone = .current) -> DayTrend {
        let day = report.day
        // Ore reali del giorno di budget (23/24/25 col cambio d'ora): le etichette della lens
        // possono essere una in meno (l'ora ripetuta deduplicata), il dominio e i tick no.
        // Al massimo 48: un giorno fuori scala non deve generare milioni di tick.
        let hours = min(max(1, Format.int((day.to.timeIntervalSince(day.from) / 3600).rounded())), 48)
        let current = min(max(Format.int(report.now.timeIntervalSince(day.from) / 3600), 0), hours - 1)
        let points = values.prefix(current + 1).enumerated().map { Point(hour: Double($0.offset) + 0.5, value: $0.element) }
        let limit = day.models?.first { $0.model == key }?.limit
        let ticks = stride(from: 0, through: hours, by: 6).map { hour in
            let clock = Format.clock(day.from.addingTimeInterval(Double(hour) * 3600), timeZone: timeZone)
            return Tick(hour: Double(hour), label: String(clock.prefix(2)))
        }
        return DayTrend(points: points, average: limit.map { $0 / Double(hours) }, hours: hours, ticks: ticks)
    }
}

/// Il riepilogo del giorno: le righe e il reset della card Modelli del pannello, in meno spazio.
public struct DaySummary: Equatable, Sendable {
    /// Righe che entrano nel widget medio; quelli oltre il budget o sopra il ritmo restano comunque.
    public static let maxModels = 4

    public let rows: [PanelState.ModelRow]
    /// Fine del giorno di budget.
    public let reset: Date

    public init(rows: [PanelState.ModelRow], reset: Date) {
        self.rows = rows
        self.reset = reset
    }

    public static func make(report: BudgetReport, models: [ModelUsage]?) -> DaySummary {
        DaySummary(rows: PanelState.modelRows(models, budgets: report.day.models ?? [], limit: maxModels), reset: report.day.to)
    }

    /// "Reset in 04h 12m alle 06:00" all'ora di una voce della timeline.
    public func resetLine(at now: Date, timeZone: TimeZone = .current) -> String {
        Format.resetLine(from: now, to: reset, timeZone: timeZone)
    }

    /// Anteprima nella galleria dei widget.
    public static let sample = DaySummary(rows: [
        PanelState.ModelRow(name: "qwen3-coder", percent: "66%", progress: 0.66, budget: "9,9M / 15M", pace: .over, tokensIn: "937,7k", tokensOut: "399,7k"),
        PanelState.ModelRow(name: "gpt-oss-120b", percent: "3%", progress: 0.03, budget: "277,9k / 10M", pace: .under, tokensIn: "26,3k", tokensOut: "11,1k"),
        PanelState.ModelRow(name: "llama-4-maverick", percent: "21%", progress: 0.21, budget: "1,3M / 6M", pace: .under, tokensIn: "132,4k", tokensOut: "62,5k"),
        PanelState.ModelRow(name: "mistral-small", percent: "1%", progress: 0.01, budget: "49,6k / 6M", pace: .under, tokensIn: "4,7k", tokensOut: "2,5k"),
    ], reset: BudgetReport.sample.day.to)
}

/// I modelli che i widget piccolo e medio possono seguire.
public enum WidgetModels {
    public struct Choice: Equatable, Sendable {
        /// `provider/modello`.
        public let key: String
        public let name: String
    }

    /// Quelli con un budget giornaliero, per nome breve; con il provider se due hanno lo stesso nome.
    public static func choices(_ report: BudgetReport) -> [Choice] {
        let keys = Set((report.day.models ?? []).map(\.model))
        let short = Dictionary(grouping: keys, by: Format.modelName)
        return keys
            .map { Choice(key: $0, name: (short[Format.modelName($0)]?.count ?? 0) > 1 ? $0 : Format.modelName($0)) }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.key < $1.key }
    }

    /// Per il menu "Modifica widget": i modelli della lens scelta nelle impostazioni; vuoto se non risponde.
    public static func load(
        settings: any SharedSettingsStore,
        lens: (SharedConfig) -> any LensReading = WidgetContent.defaultLens
    ) async -> [Choice] {
        guard case .ok(let report) = await lens(settings.load()).budget() else { return [] }
        return choices(report)
    }

    /// Il modello scelto; senza scelta quello messo peggio (ritmo, poi percentuale), così un widget
    /// appena aggiunto mostra subito il modello da tenere d'occhio. `nil` se nessuno ha un budget.
    public static func resolve(_ selected: String?, report: BudgetReport) -> String? {
        if let selected { return selected }
        return (report.day.models ?? []).filter(\.seen).max { a, b in
            if a.pace.severity != b.pace.severity { return a.pace.severity < b.pace.severity }
            if (a.ratio ?? 0) != (b.ratio ?? 0) { return (a.ratio ?? 0) < (b.ratio ?? 0) }
            return a.model > b.model
        }?.model
    }
}

/// Cosa mostra un widget.
public enum WidgetContent: Equatable, Sendable {
    /// Widget piccolo (solo il modello) e medio (con l'andamento; `nil` se la lens non lo dà).
    case model(ModelDay, DayTrend?)
    case summary(DaySummary)
    case message(String)

    public enum Kind: Sendable {
        case ring, trend, summary
    }

    public static let unreachable = "Lens non raggiungibile"
    public static let noBudgets = "Nessun budget per modello (LENS_MODEL_LIMITS)"
    public static let noModels = "Nessun modello usato oggi"
    public static let refreshInterval: TimeInterval = 15 * 60
    /// Dopo una lettura fallita o a metà: il widget non ha altro modo di riprendersi (l'app lo ricarica
    /// solo quando i dati cambiano) e WidgetKit tollera qualche reload in più, non quindici minuti di
    /// «Lens non raggiungibile» dopo un riavvio della lens.
    public static let retryInterval: TimeInterval = 2 * 60

    /// Anteprima nella galleria dei widget e segnaposto, dal report d'esempio.
    public static func sample(_ kind: Kind) -> WidgetContent {
        let report = BudgetReport.sample
        let key = report.day.models?.first?.model ?? ""
        let day = ModelDay.make(key: key, report: report, models: nil)
        switch kind {
        case .ring: return .model(day, nil)
        case .trend:
            let values: [Double] = [52, 44, 38, 41, 30, 22, 18, 25, 34, 30, 41, 48, 60]
            return .model(day, DayTrend.make(values: values + Array(repeating: 0, count: 11), key: key, report: report))
        case .summary: return .summary(.sample)
        }
    }

    /// Host, porta e token dall'App Group: il sandbox non lascia leggere il plist della lens.
    public static func defaultLens(_ config: SharedConfig) -> any LensReading {
        LensClient(host: config.host, port: config.port, token: config.token)
    }

    /// Ore delle voci di una timeline: adesso, poi ogni inizio di minuto fino a `next` escluso, così
    /// "Reset in 04h 12m" cambia insieme all'orologio senza rileggere la lens.
    public static func entryDates(from now: Date, until next: Date) -> [Date] {
        var dates = [now]
        var minute = (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60
        while minute < next.timeIntervalSince1970 {
            dates.append(Date(timeIntervalSince1970: minute))
            minute += 60
        }
        return dates
    }

    /// Prossimo aggiornamento del widget: tra 15 minuti (`retryInterval` se la lettura è fallita o
    /// `degraded`: una parte dei dati manca), o un secondo dopo il reset del giorno di budget se
    /// arriva prima, così dopo il reset non resta il giorno passato.
    public static func nextUpdate(after now: Date, fetch: BudgetFetch, degraded: Bool = false) -> Date {
        let failed = degraded || fetch == .unavailable
        let regular = now.addingTimeInterval(failed ? retryInterval : refreshInterval)
        guard case .ok(let report) = fetch, report.day.to > now else { return regular }
        return min(regular, report.day.to.addingTimeInterval(1))
    }

    /// Una voce della timeline. `model`: il `provider/modello` scelto in "Modifica widget".
    public static func load(
        _ kind: Kind,
        model selected: String? = nil,
        now: Date,
        settings: any SharedSettingsStore,
        timeZone: TimeZone = .current,
        lens makeLens: (SharedConfig) -> any LensReading = defaultLens
    ) async -> (content: WidgetContent, nextUpdate: Date) {
        let lens = makeLens(settings.load())
        let fetch = await lens.budget()
        switch fetch {
        case .unavailable:
            return (.message(unreachable), nextUpdate(after: now, fetch: fetch))
        case .ok(let report):
            switch kind {
            case .summary:
                let models = await lens.models(since: report.day.from)
                let summary = DaySummary.make(report: report, models: models)
                let next = nextUpdate(after: now, fetch: fetch, degraded: models == nil)
                // Senza breakdown e senza budget non c'è niente di vero da mostrare: non "nessun modello".
                if summary.rows.isEmpty { return (.message(models == nil ? unreachable : noModels), next) }
                return (.summary(summary), next)
            case .ring, .trend:
                guard let key = WidgetModels.resolve(selected, report: report) else { return (.message(noBudgets), nextUpdate(after: now, fetch: fetch)) }
                let hasBudget = report.day.models?.contains { $0.model == key } ?? false
                let models = hasBudget ? nil : await lens.models(since: report.day.from)
                let day = ModelDay.make(key: key, report: report, models: models)
                let missingModels = !hasBudget && models == nil
                guard kind == .trend else { return (.model(day, nil), nextUpdate(after: now, fetch: fetch, degraded: missingModels)) }
                let values = await lens.hourlyTokens(model: key, from: report.day.from, to: report.day.to)
                let next = nextUpdate(after: now, fetch: fetch, degraded: missingModels || values == nil)
                return (.model(day, values.map { DayTrend.make(values: $0, key: key, report: report, timeZone: timeZone) }), next)
            }
        }
    }
}
