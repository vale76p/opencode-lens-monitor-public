import Foundation
@testable import LensMonitorCore

/// Il report d'esempio con il giorno o `now` sostituiti.
func report(day: BudgetPeriod? = nil, now: Date? = nil) -> BudgetReport {
    let sample = BudgetReport.sample
    return BudgetReport(now: now ?? sample.now, periods: .init(day: day ?? sample.day))
}

/// Il giorno d'esempio con altri budget per modello.
func dayWith(models: [ModelBudget]?) -> BudgetPeriod {
    let day = BudgetReport.sample.day
    return BudgetPeriod(from: day.from, to: day.to, models: models)
}
