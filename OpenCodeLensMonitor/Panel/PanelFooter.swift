import AppKit
import LensMonitorCore
import SwiftUI

struct PanelFooter: View {
    let model: MonitorModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 4) {
            // versione del Monitor; la dashboard della lens è il pulsante qui accanto
            Text("OpenCode Monitor v\(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { DashboardOpener.open(model.dashboardDestination) } label: { Image(systemName: "chart.bar.xaxis") }
                .help("Apri la dashboard")
            Button {
                NSApp.activate()
                openSettings()
            } label: { Image(systemName: "gearshape") }
                .help("Impostazioni")
            Button { showPowerMenu() } label: { Image(systemName: "power") }
                .help("Servizio e uscita")
        }
        .buttonStyle(FooterButtonStyle())
    }

    /// Menu di AppKit invece di un `Menu` di SwiftUI: quello disegna un suo pulsante AppKit, che
    /// ignora lo stile degli altri due e all'hover si spostava e si colorava d'accento.
    /// Le voci le decide PowerMenu (core, testato); qui solo il popUp. `model.primaryAction` e non
    /// `state.primaryAction`: con una lens di sviluppo Ferma colpirebbe il LaunchAgent.
    private func showPowerMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in PowerMenu.items(primaryAction: model.primaryAction, busy: model.busy) {
            if item.separatorBefore, menu.items.isEmpty == false { menu.addItem(.separator()) }
            menu.addItem(ActionMenuItem(item.title, enabled: item.enabled) { [model] in
                switch item.action {
                case .start: Task { await model.start() }
                case .stop: Task { await model.stop() }
                case .quit: NSApplication.shared.terminate(nil)
                }
            })
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// Icone del piede del pannello: grigie, scure sotto il puntatore con un fondo leggero.
/// Interamente SwiftUI: con `.borderless` AppKit disegna il pulsante e l'hover non si vede.
struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FooterIcon(label: configuration.label, pressed: configuration.isPressed)
    }
}

private struct FooterIcon<Label: View>: View {
    let label: Label
    let pressed: Bool
    // State senza la macro @State (il plugin è solo in Xcode): vedi OpenCodeLensMonitorApp
    private let hovering = State(initialValue: false)

    init(label: Label, pressed: Bool) {
        self.label = label
        self.pressed = pressed
    }

    var body: some View {
        let on = hovering.wrappedValue
        label
            .foregroundStyle(on || pressed ? Color.primary : Color.secondary)
            .frame(width: 28, height: 24)
            .background(Color.primary.opacity(pressed ? 0.14 : on ? 0.07 : 0), in: .rect(cornerRadius: 7))
            .contentShape(.rect(cornerRadius: 7))
            .onHover { hovering.wrappedValue = $0 }
            .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// Voce di `NSMenu` con una closure al posto di target e selettore.
private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("non da nib") }

    @objc private func run() { handler() }
}
