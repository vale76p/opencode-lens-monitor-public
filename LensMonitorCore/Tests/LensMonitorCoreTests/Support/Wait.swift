import Testing

/// Aspetta che `condition` diventi vera cedendo il turno agli altri task, con un limite: una
/// regressione deve far fallire il test, non bloccare tutta la suite in un ciclo infinito.
@MainActor
func waitUntil(_ condition: () -> Bool, maxYields: Int = 10_000, sourceLocation: SourceLocation = #_sourceLocation) async {
    for _ in 0..<maxYields {
        if condition() { return }
        await Task.yield()
    }
    if !condition() { Issue.record("condizione mai verificata", sourceLocation: sourceLocation) }
}
