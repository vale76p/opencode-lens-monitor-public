import LensMonitorCore
import SwiftUI

/// Pannello della barra: card dei dati con la lens attiva, card di stato altrimenti.
struct PanelView: View {
    let model: MonitorModel

    var body: some View {
        // Ogni secondo: tempo al reset e countdown del refresh.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let panel = model.panel
            GlassEffectContainer(spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    PanelHeader(state: model.state, development: model.lensTarget != .service)
                    if let error = model.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if model.state.isRunning {
                        if let notice = panel.notice { NoticeCard(text: notice) }
                        if let today = panel.today { TodayCard(today: today) }
                        if !panel.models.isEmpty { ModelsCard(models: panel.models, reset: panel.modelsReset) }
                        RefreshRow(next: model.nextUsageRefresh, usage: model.usage, address: model.lensAddress, lensVersion: model.lensVersion, interval: model.usageInterval, now: context.date)
                    } else {
                        StatusCard(model: model)
                    }
                    PanelFooter(model: model)
                }
                .padding(14)
            }
        }
        .frame(width: 340)
        .onAppear { Task { await model.panelOpened() } }
    }
}

struct PanelHeader: View {
    let state: ServiceState
    /// Si segue una lens di sviluppo invece di quella del LaunchAgent.
    var development = false

    var body: some View {
        HStack(spacing: 8) {
            OpenCodeMark().frame(width: 18, height: 18)
            Text("OpenCode Monitor").font(.title3.weight(.semibold))
            if development {
                Text("DEV").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    .help("Lens di sviluppo, scelta nelle impostazioni")
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(state.statusDot.color).frame(width: 7, height: 7)
                Text(state.shortText).font(.caption).foregroundStyle(.secondary)
            }
            .help(state.statusText)
        }
    }
}
