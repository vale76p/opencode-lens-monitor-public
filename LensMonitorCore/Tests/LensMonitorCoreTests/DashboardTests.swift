import Foundation
import Testing
@testable import LensMonitorCore

/// «Apri la dashboard» con e senza l'app OpenCode Lens della lens (extras/macos, lens ≥ 0.37.0).
@Suite struct DashboardTests {
    let app = URL(fileURLWithPath: "/Users/v/Applications/OpenCode Lens.app")
    let production = URL(string: "http://127.0.0.1:4777")!
    let dev = URL(string: "http://127.0.0.1:4790")!

    @Test func conLAppELaProduzioneApreLApp() {
        #expect(DashboardDestination.resolve(target: .service, dashboardURL: production, companionApp: app) == .app(app))
    }

    @Test func senzaLAppApreIlBrowser() {
        #expect(DashboardDestination.resolve(target: .service, dashboardURL: production, companionApp: nil) == .browser(production))
    }

    /// L'app segue solo porta e token del plist: con una lens di sviluppo mostrerebbe la produzione.
    @Test func conUnaLensDiSviluppoSempreIlBrowser() {
        let target = LensTarget.local(host: "127.0.0.1", port: 4790)
        #expect(DashboardDestination.resolve(target: target, dashboardURL: dev, companionApp: app) == .browser(dev))
        #expect(DashboardDestination.resolve(target: target, dashboardURL: dev, companionApp: nil) == .browser(dev))
    }

    @Test func bundleIdDellApp() {
        #expect(CompanionApp.bundleIdentifier == "local.opencode-lens.app")
    }
}

@MainActor
@Suite struct MonitorModelDashboardTests {
    static let dev = LensTarget.local(host: "127.0.0.1", port: 4790)
    let app = URL(fileURLWithPath: "/Users/v/Applications/OpenCode Lens.app")

    /// L'app si cerca a ogni clic: può essere installata o tolta mentre il Monitor è aperto.
    @Test func destinazioneRilettaAOgniClic() async {
        let h = Harness()
        #expect(h.model.dashboardDestination == .browser(URL(string: "http://127.0.0.1:4777")!))
        h.companionApp.value = app
        #expect(h.model.dashboardDestination == .app(app))
        await h.model.selectTarget(Self.dev)
        #expect(h.model.dashboardDestination == .browser(URL(string: "http://127.0.0.1:4777")!))
    }

    /// Senza l'app il browser riceve il token della lens seguita; l'indirizzo mostrato no.
    @Test func browserConIlTokenDellaLens() {
        let h = Harness()
        h.lens.endpoint = LensEndpoint(port: 4777, token: "segreto")
        #expect(h.model.dashboardDestination == .browser(URL(string: "http://127.0.0.1:4777/?token=segreto")!))
        #expect(h.model.lensAddress == "127.0.0.1:4777")
    }

    @Test func clicSulWidgetConLAppInstallata() async {
        let h = Harness()
        h.companionApp.value = app
        h.controller.load = .loaded(running: true, pid: 1)
        await h.model.refresh()
        #expect(h.model.widgetClicked() == .app(app))
        h.controller.load = .notLoaded
        await h.model.refresh()
        #expect(h.model.widgetClicked() == nil)
        #expect(h.model.settingsRequests == 1)
    }
}
