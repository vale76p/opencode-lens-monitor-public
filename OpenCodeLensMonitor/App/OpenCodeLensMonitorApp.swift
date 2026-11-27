import LensMonitorCore
import SwiftUI
import WidgetKit

@main
struct OpenCodeLensMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Non @State: dall'SDK di macOS 27 @State è una macro di SwiftUI, il cui plugin c'è solo in
    // Xcode, e scripts/build-clt.sh compila con i Command Line Tools. L'App nasce una volta sola
    // e MonitorModel è @Observable: basta una proprietà normale.
    private let model: MonitorModel

    init() {
        let loginItem = RecordedLoginItem(
            base: AppLoginItem(),
            defaults: .standard,
            bundlePath: Bundle.main.bundlePath,
            home: NSHomeDirectory()
        )
        // install.sh sposta l'app in ~/Applications: il login item va registrato da qui
        try? loginItem.relocateIfMoved()
        let model = MonitorModel(
            controller: LaunchAgentController(),
            lens: AppLens.client(),
            discovery: LensDiscovery(),
            loginItem: loginItem,
            settings: UserDefaultsSettings(),
            listener: LsofListenerVerifier(),
            companionApp: DashboardOpener.companionApp
        )
        model.onUsageChange = { WidgetCenter.shared.reloadAllTimelines() }
        AppDelegate.model = model
        model.startPolling()
        self.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(panel: model.panel, service: model.state)
                .modifier(SettingsOpener(requests: model.settingsRequests))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Apre le impostazioni quando il modello lo chiede: `openSettings` esiste solo nelle viste.
private struct SettingsOpener: ViewModifier {
    let requests: Int
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onChange(of: requests) {
            NSApp.activate()
            openSettings()
        }
    }
}

enum AppLens {
    /// La lens scelta nelle impostazioni (salvata nell'App Group): host, porta e token dal plist
    /// del LaunchAgent, `LENS_MONITOR_PORT` per provare un'altra lens, o una lens di sviluppo.
    static func client() -> LensClient {
        LensClient(
            endpoint: { LensConfig.endpoint(for: UserDefaultsSettings().load().target, plistAt: Paths.plist) },
            service: { LensConfig.endpoint(for: .service, plistAt: Paths.plist) }
        )
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
