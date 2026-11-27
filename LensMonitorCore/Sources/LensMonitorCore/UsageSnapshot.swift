import Foundation

/// Ultimi dati letti dalla lens per pannello e widget.
public struct UsageSnapshot: Equatable, Sendable {
    public var budget: BudgetReport?
    public var models: [ModelUsage]?
    /// Token per modello dai 7 giorni di budget prima di oggi fino ad adesso: i pesi della
    /// percentuale di oggi.
    public var history: [ModelUsage]?
    /// Ora dell'ultima risposta di /api/budget.
    public var fetchedAt: Date?
    /// Ora dell'ultima risposta di /api/breakdown.
    public var modelsFetchedAt: Date?
    /// L'ultimo refresh è fallito: i dati sono quelli di prima.
    public var stale: Bool

    public init(budget: BudgetReport? = nil, models: [ModelUsage]? = nil, history: [ModelUsage]? = nil, fetchedAt: Date? = nil, modelsFetchedAt: Date? = nil, stale: Bool = false) {
        self.budget = budget
        self.models = models
        self.history = history
        self.fetchedAt = fetchedAt
        self.modelsFetchedAt = modelsFetchedAt
        self.stale = stale
    }
}
