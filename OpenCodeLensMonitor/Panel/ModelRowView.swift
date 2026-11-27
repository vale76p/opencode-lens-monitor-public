import LensMonitorCore
import SwiftUI

/// Una riga della card Modelli del pannello (il widget del riepilogo ha la sua SummaryRow,
/// più stretta).
struct ModelRowView: View {
    let model: PanelState.ModelRow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(model.name).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("↓\(model.tokensIn) ↑\(model.tokensOut)")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .help("Token di input (senza cache) e di output (ragionamento compreso)")
                if let percent = model.percent {
                    Text(percent).monospacedDigit().fontWeight(.medium)
                        .foregroundStyle(model.pace.color.color)
                        .help("Del budget giornaliero del modello (LENS_MODEL_LIMITS)")
                }
            }
            .font(.subheadline)
            if let note = model.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .help("Il modello ha un budget in LENS_MODEL_LIMITS ma la lens non lo ha mai visto in uno step: controlla il nome")
            }
            if let progress = model.progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress).tint(model.pace.color.color).controlSize(.mini)
                    if let budget = model.budget {
                        Text(budget).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            .help("Token di oggi su budget giornaliero del modello")
                    }
                }
            }
        }
    }
}
