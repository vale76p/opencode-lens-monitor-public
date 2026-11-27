import Foundation

extension BudgetReport {
    /// Risposta d'esempio di /api/budget: anteprima dei widget nella galleria e test.
    public static let sampleJSON = """
    {"now":1792058400000,"periods":{
    "day":{"from":1792015200000,"to":1792101600000,"elapsed":0.5,
    "tokens":{"used":1100,"limit":null,"ratio":null,"projected":2200,"projectedRatio":null,"pace":"none"},
    "cost":{"used":2.5,"limit":null,"ratio":null,"projected":5,"projectedRatio":null,"pace":"none"},
    "steps":{"used":1,"limit":null,"ratio":null,"projected":2,"projectedRatio":null,"pace":"none"},
    "models":[{"model":"lmstudio/qwen3.5-9b-mlx","used":400,"limit":1000,"ratio":0.4,"projected":800,"projectedRatio":0.8,"pace":"under","seen":true}]},
    "week":{"from":1791756000000,"to":1792360800000,"elapsed":0.5,
    "tokens":{"used":2100,"limit":5000,"ratio":0.42,"projected":4200,"projectedRatio":0.84,"pace":"under"},
    "cost":{"used":3.5,"limit":2,"ratio":1.75,"projected":7,"projectedRatio":3.5,"pace":"exceeded"},
    "steps":{"used":2,"limit":3,"ratio":0.6666666666666666,"projected":4,"projectedRatio":1.3333333333333333,"pace":"over"},
    "days":[{"date":"2026-10-12","tokens":1000,"cost":1,"steps":1},{"date":"2026-10-13","tokens":0,"cost":0,"steps":0},
    {"date":"2026-10-14","tokens":0,"cost":0,"steps":0},{"date":"2026-10-15","tokens":1100,"cost":2.5,"steps":1},
    {"date":"2026-10-16","tokens":0,"cost":0,"steps":0},{"date":"2026-10-17","tokens":0,"cost":0,"steps":0},
    {"date":"2026-10-18","tokens":0,"cost":0,"steps":0}]},
    "month":{"from":1790805600000,"to":1793487600000,"elapsed":0.4677419354838709,
    "tokens":{"used":6100,"limit":100000,"ratio":0.061,"projected":13041.379310344828,"projectedRatio":0.13041379310344827,"pace":"under"},
    "cost":{"used":7.5,"limit":null,"ratio":null,"projected":16.03448275862069,"projectedRatio":null,"pace":"none"},
    "steps":{"used":3,"limit":null,"ratio":null,"projected":6.414,"projectedRatio":null,"pace":"none"}}}}
    """

    // swiftlint:disable:next force_try
    public static let sample = try! LensJSON.decoder.decode(BudgetReport.self, from: Data(sampleJSON.utf8))
}
