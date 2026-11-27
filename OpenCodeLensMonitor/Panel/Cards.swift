import LensMonitorCore
import SwiftUI

/// Il giorno di budget: media dei budget dei modelli e token totali, con lo stesso peso.
struct TodayCard: View {
    let today: PanelState.Today

    private let big = Font.system(size: 34, weight: .semibold, design: .rounded)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Oggi").font(.headline)
                Text(today.date).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if let badge = today.alert.badge {
                    PaceBadge(text: badge, color: today.alert.color.color)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                if let percent = today.percent {
                    Text(percent).font(big).monospacedDigit()
                }
                Spacer()
                Text(today.total).font(big).monospacedDigit()
                    .help("Token di oggi di tutti i modelli, cache compresa")
            }
            if let progress = today.progress {
                ProgressView(value: progress).tint(today.pace.color.color)
            }
            Text(today.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .glassCard()
    }
}

struct ModelsCard: View {
    let models: [PanelState.ModelRow]
    /// "Reset in 04h 12m alle 06:00", una sola riga per tutti i modelli.
    let reset: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Modelli").font(.headline)
                Spacer()
                Text("oggi · token in / out").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(models) { ModelRowView(model: $0) }
            if let reset {
                Text(reset).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }
}

struct NoticeCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(.orange)
            .glassCard()
    }
}

/// Al posto delle card dei dati quando la lens non è attiva.
struct StatusCard: View {
    let model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.state.cardTitle, systemImage: model.state.symbolName).font(.headline)
            Text(model.state.statusText).font(.caption).foregroundStyle(.secondary)
            if let note = model.externalStopNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            switch model.primaryAction {
            case .start:
                Button("Avvia lens") { Task { await model.start() } }
                    .buttonStyle(.glass).disabled(model.busy)
            case .stop:
                Button("Ferma lens") { Task { await model.stop() } }
                    .buttonStyle(.glass).disabled(model.busy)
            case nil:
                EmptyView()
            }
            // Una lens di sviluppo spenta resterebbe seguita anche dopo un riavvio, senza controllare
            // più la produzione: si torna indietro da qui, senza cercare nelle impostazioni.
            if model.state == .unreachable {
                Button("Torna a Produzione") { Task { await model.selectTarget(.service) } }
                    .buttonStyle(.glass).disabled(model.busy)
            }
        }
        .glassCard()
    }
}

struct RefreshRow: View {
    let next: Date?
    let usage: UsageSnapshot?
    let address: String
    let lensVersion: String?
    let interval: TimeInterval
    let now: Date
    // State senza la macro @State (il plugin è solo in Xcode): vedi OpenCodeLensMonitorApp
    private let showInfo = State(initialValue: false)

    var body: some View {
        HStack {
            Text(Format.refreshStatus(next: next, now: now))
            if usage?.stale == true {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            }
            Spacer()
            Button { showInfo.wrappedValue.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .popover(isPresented: showInfo.projectedValue, arrowEdge: .bottom) {
                    RefreshInfo(usage: usage, address: address, lensVersion: lensVersion, interval: interval).padding(12).frame(width: 260)
                }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct RefreshInfo: View {
    let usage: UsageSnapshot?
    let address: String
    let lensVersion: String?
    let interval: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lensVersion {
                Text("opencode-lens v\(lensVersion)").fontWeight(.medium)
            }
            Text("Dati da /api/budget e /api/breakdown della lens su \(address), \(Format.every(interval)).")
            // Format.clock e non .formatted(): quello segue la lingua del sistema (su un Mac inglese
            // "5:03 PM" accanto ai testi italiani e alle ore 24 h del resto dell'app).
            if let fetched = usage?.fetchedAt {
                Text("Ultimo dato: \(Format.clock(fetched))")
            }
            if let models = usage?.modelsFetchedAt, models != usage?.fetchedAt {
                Text("Modelli: \(Format.clock(models))")
            }
            if usage?.stale == true {
                Text("L'ultimo aggiornamento non è riuscito: i dati sono vecchi.").foregroundStyle(.orange)
            }
            Text("Pannello e widget: budget giornalieri per modello, LENS_MODEL_LIMITS nel plist della lens.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
}
