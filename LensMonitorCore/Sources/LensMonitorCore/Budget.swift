import Foundation

/// Ritmo dell'uso rispetto al budget del periodo, calcolato dalla lens.
public enum Pace: String, Sendable {
    case noLimit = "none"
    case under
    case over
    case exceeded
}

extension Pace {
    /// Per scegliere il ritmo peggiore tra più modelli: superato, sopra il ritmo, in linea, senza limite.
    public var severity: Int {
        switch self {
        case .exceeded: 3
        case .over: 2
        case .under: 1
        case .noLimit: 0
        }
    }

    /// Stessa regola della lens (`pace()` in queries.js), per i valori calcolati dall'app.
    public init(ratio: Double?, projectedRatio: Double?) {
        guard let ratio else { self = .noLimit; return }
        if ratio >= 1 { self = .exceeded } else if let projectedRatio, projectedRatio > 1 { self = .over } else { self = .under }
    }
}

extension Pace: Decodable {
    /// Un valore sconosciuto (lens più nuova dell'app) vale `noLimit`.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Pace(rawValue: raw) ?? .noLimit
    }
}

/// Budget giornaliero di token di un modello (`LENS_MODEL_LIMITS`), varianti insieme.
public struct ModelBudget: Decodable, Equatable, Sendable {
    /// Nota delle righe di un modello con budget che la lens non ha mai visto: di solito un nome
    /// sbagliato in `LENS_MODEL_LIMITS`. Stessa idea della dashboard, in meno spazio.
    public static let unseenNote = "mai visto: controlla il nome"

    /// `provider/modello`, come nella tabella per modello della lens.
    public let model: String
    public let used: Double
    public let limit: Double
    public let ratio: Double?
    /// Proiezione lineare a fine giorno su budget; `nil` all'inizio del giorno.
    public let projectedRatio: Double?
    public let pace: Pace
    /// `false` se il modello non è comparso in nessuno step. Non conta nelle medie né nel colore: uno
    /// 0% inventato abbasserebbe la media e terrebbe verde il pallino. Le lens che non mandano il
    /// campo (più vecchie) valgono `true`.
    public let seen: Bool

    private enum CodingKeys: String, CodingKey { case model, used, limit, ratio, projectedRatio, pace, seen }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            model: try container.decode(String.self, forKey: .model),
            used: try container.decode(Double.self, forKey: .used),
            limit: try container.decode(Double.self, forKey: .limit),
            ratio: try container.decodeIfPresent(Double.self, forKey: .ratio),
            projectedRatio: try container.decodeIfPresent(Double.self, forKey: .projectedRatio),
            pace: try container.decode(Pace.self, forKey: .pace),
            seen: try container.decodeIfPresent(Bool.self, forKey: .seen) ?? true
        )
    }

    public init(model: String, used: Double, limit: Double, ratio: Double?, projectedRatio: Double? = nil, pace: Pace, seen: Bool = true) {
        self.model = model
        self.used = used
        self.limit = limit
        self.ratio = ratio
        self.projectedRatio = projectedRatio
        self.pace = pace
        self.seen = seen
    }
}

/// Regole di visualizzazione di un budget, le stesse nel pannello e nei widget: scritte una volta
/// sola, così non possono divergere.
extension ModelBudget {
    /// Token di oggi su budget, "42%"; `nil` senza rapporto o con un modello mai visto.
    public var displayPercent: String? { seen ? ratio.map(Format.percent) : nil }
    /// Riempimento di barra o anello, 0…1 anche oltre il budget; `nil` senza rapporto o con un
    /// modello mai visto.
    public var displayProgress: Double? { seen ? ratio.map { min(max($0, 0), 1) } : nil }
    /// "7,1M / 15M".
    public var displayBudget: String { "\(Format.tokens(used)) / \(Format.tokens(limit))" }
}

/// Il giorno di budget della lens (da `LENS_RESET_HOUR`). La lens manda anche settimana e mese,
/// con token, costo e step per periodo: nessuna vista li mostra più dalla 0.3.0, e decodificarli
/// farebbe fallire tutto `/api/budget` se una lens futura li togliesse.
public struct BudgetPeriod: Decodable, Equatable, Sendable {
    public let from: Date
    /// Fine del periodo: il momento del reset.
    public let to: Date
    /// Modelli con un budget giornaliero; assente nelle lens più vecchie.
    public let models: [ModelBudget]?

    /// I modelli della percentuale di oggi: con un budget e già visti dalla lens. Una regola sola
    /// per il calcolo e per la scelta di leggere la storia, che altrimenti divergerebbero.
    public var countedModels: [ModelBudget] { (models ?? []).filter { $0.ratio != nil && $0.seen } }
}

/// Risposta di GET /api/budget.
public struct BudgetReport: Decodable, Equatable, Sendable {
    public let now: Date
    public let periods: Periods

    public struct Periods: Decodable, Equatable, Sendable {
        public let day: BudgetPeriod
    }

    public var day: BudgetPeriod { periods.day }
}

/// Decoder delle risposte della lens: le date sono in millisecondi.
enum LensJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
