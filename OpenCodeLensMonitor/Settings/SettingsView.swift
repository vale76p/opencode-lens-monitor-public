import AppKit
import LensMonitorCore
import ServiceManagement
import SwiftUI

/// Tre schede piccole invece di un unico modulo: ognuna sta nella finestra senza scorrere.
struct SettingsView: View {
    @Bindable var model: MonitorModel

    var body: some View {
        TabView {
            Tab("Generale", systemImage: "gearshape") { GeneralSettings(model: model) }
            Tab("Server", systemImage: "server.rack") { ServerSettings(model: model) }
        }
        .frame(width: 480)
    }
}

/// Modulo raggruppato alto quanto il contenuto: senza `scrollDisabled` e `fixedSize` il modulo
/// è uno scroll view e la finestra delle impostazioni mostrerebbe la barra laterale.
private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: MonitorModel

    var body: some View {
        SettingsForm {
            Section("Servizio") {
                HStack(spacing: 8) {
                    Circle().fill(model.state.statusDot.color).frame(width: 9, height: 9)
                    Text(model.state.statusText).lineLimit(2)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                if let note = model.externalStopNote {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    switch model.primaryAction {
                    case .start:
                        Button("Avvia lens", systemImage: "play.fill") { Task { await model.start() } }
                            .disabled(model.busy)
                    case .stop:
                        Button("Ferma lens", systemImage: "stop.fill") { Task { await model.stop() } }
                            .disabled(model.busy)
                    case nil:
                        EmptyView()
                    }
                    Spacer()
                    Button("Dashboard", systemImage: "chart.bar.xaxis") { DashboardOpener.open(model.dashboardDestination) }
                        .disabled(!model.state.isRunning)
                    Button("Log", systemImage: "doc.text") { NSWorkspace.shared.open(Paths.logToOpen()) }
                }
                if let error = model.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Section {
                Picker("Aggiorna i dati", selection: Binding(
                    get: { model.usageInterval },
                    set: { model.setUsageInterval($0) }
                )) {
                    ForEach(RefreshInterval.choices, id: \.self) { seconds in
                        Text(Format.interval(seconds)).tag(seconds)
                    }
                }
            } header: {
                Text("Dati")
            } footer: {
                Text("Budget e modelli, cioè la percentuale nella barra; si rileggono anche a ogni apertura del pannello. Lo stato del servizio si controlla ogni 5 s quando serve, fino a ogni minuto con la lens ferma o in errore da un pezzo.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("All'accesso") {
                Toggle("Avvia la lens", isOn: Binding(
                    get: { model.serviceAtLogin },
                    set: { enabled in Task { await model.setServiceAtLogin(enabled) } }
                ))
                .disabled(!model.canToggleServiceAtLogin)
                Toggle("Apri OpenCode Monitor", isOn: Binding(
                    get: { model.appLogin.isOn },
                    set: { model.setAppAtLogin($0) }
                ))
                if model.appLogin == .requiresApproval {
                    Button("Approva in Impostazioni di Sistema…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
        }
    }
}

private struct ServerSettings: View {
    @Bindable var model: MonitorModel

    var body: some View {
        SettingsForm {
            Section {
                Picker("Lens", selection: Binding(
                    get: { model.lensTarget },
                    set: { target in Task { await model.selectTarget(target) } }
                )) {
                    ForEach(model.serverOptions) { option in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title)
                            Text(option.address).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .foregroundStyle(option.available ? .primary : .secondary)
                        .tag(option.target)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(model.busy)
            } header: {
                HStack {
                    Text("Lens da seguire")
                    Spacer()
                    if model.discovering { ProgressView().controlSize(.small) }
                    Button("Cerca di nuovo", systemImage: "arrow.clockwise") { Task { await model.discoverServers() } }
                        .buttonStyle(.borderless)
                        .disabled(model.discovering)
                }
            } footer: {
                Text("Pannello e widget seguono la lens scelta. Avvia e Ferma agiscono solo sul LaunchAgent di produzione; una lens di sviluppo con LENS_TOKEN non compare.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { await model.discoverServers() }
    }
}
