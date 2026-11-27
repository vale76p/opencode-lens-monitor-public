import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct SharedSettingsTests {
    /// Dominio di prova con un nome fisso per test (i test girano in parallelo), vuotato
    /// all'inizio e alla fine: con un nome casuale ogni esecuzione lascerebbe un file in
    /// ~/Library/Preferences.
    final class Domain {
        let name: String
        init(_ test: String = #function) {
            name = "test.opencode-lens-monitor.\(test.prefix { $0 != "(" })"
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        deinit { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    @Test func defaultSenzaValori() {
        let domain = Domain()
        #expect(UserDefaultsSettings(suiteName: domain.name).load() == .default)
        #expect(SharedConfig.default == SharedConfig(port: 4777, token: nil))
        #expect(SharedConfig.default.host == "127.0.0.1")
    }

    @Test func appGroupSoloConLaFirmaDelTeam() {
        #expect(UserDefaultsSettings.suite(forTeam: "HS87DR6TBX") == UserDefaultsSettings.appGroup)
        #expect(UserDefaultsSettings.suite(forTeam: nil) == nil, "firma ad-hoc: UserDefaults del processo")
        #expect(UserDefaultsSettings.suite(forTeam: "ALTRO12345") == nil)
    }

    /// The test runner is ad-hoc signed: no team, and reading the signature must not fail.
    @Test func teamDellaFirmaDiQuestoProcesso() {
        let team = CodeSignature.teamIdentifier()
        #expect(team == nil || team?.count == 10)
    }

    @Test func salvaERilegge() {
        let domain = Domain()
        let settings = UserDefaultsSettings(suiteName: domain.name)
        settings.save(SharedConfig(port: 4800, token: "segreto"))
        #expect(settings.load() == SharedConfig(port: 4800, token: "segreto"))
        settings.save(SharedConfig(host: "::1", port: 4800, token: nil))
        #expect(settings.load().host == "::1")
        settings.save(SharedConfig(port: 4800, token: nil))
        #expect(settings.load().token == nil)
        #expect(settings.load().target == .service)
        settings.save(SharedConfig(port: 4790, token: nil, target: .local(host: "127.0.0.1", port: 4790)))
        #expect(settings.load().target == .local(host: "127.0.0.1", port: 4790))
    }

    @Test func senzaAppGroupSoloLaLensScelta() {
        let domain = Domain()
        let defaults = UserDefaults(suiteName: domain.name)!
        // lasciati da una versione che li copiava anche senza App Group
        defaults.set("segreto", forKey: "token")
        defaults.set("127.0.0.1", forKey: "host")
        defaults.set(4777, forKey: "port")
        let settings = UserDefaultsSettings(suiteName: domain.name, reachesWidget: false)
        settings.save(SharedConfig(port: 4800, token: "segreto", target: .local(host: "127.0.0.1", port: 4790)))
        #expect(defaults.object(forKey: "token") == nil)
        #expect(defaults.object(forKey: "host") == nil)
        #expect(defaults.object(forKey: "port") == nil)
        #expect(settings.load() == SharedConfig(port: 4777, token: nil, target: .local(host: "127.0.0.1", port: 4790)))
    }

    @Test func soloLAppGroupArrivaAlWidget() {
        #expect(UserDefaultsSettings(suiteName: UserDefaultsSettings.appGroup).reachesWidget)
        #expect(UserDefaultsSettings(suiteName: nil).reachesWidget == false)
    }

    @Test func valoriNonValidiTornanoAlDefault() {
        let domain = Domain()
        let defaults = UserDefaults(suiteName: domain.name)!
        defaults.set(0, forKey: "port")
        defaults.set("", forKey: "token")
        defaults.set("", forKey: "host")
        #expect(UserDefaultsSettings(suiteName: domain.name).load() == .default)
    }

    @Test func intervalloDeiDati() {
        let domain = Domain()
        let settings = UserDefaultsSettings(suiteName: domain.name)
        #expect(settings.load().refreshInterval == 60)
        settings.save(SharedConfig(port: 4777, token: nil, refreshInterval: 30))
        #expect(settings.load().refreshInterval == 30)
        // un valore fuori dalla lista (scritto a mano con defaults) torna al minuto
        UserDefaults(suiteName: domain.name)!.set(7, forKey: "refreshInterval")
        #expect(settings.load().refreshInterval == 60)
    }

    func plist(_ env: [String: String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "lens-\(UUID().uuidString).plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["EnvironmentVariables": env], format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    /// Firma ad-hoc: il widget non vede l'App Group, e dalla 0.38 la lens ha sempre un token.
    @Test func senzaAppGroupIlWidgetLeggeIlPlist() throws {
        let base = InMemorySettings()
        base.reachesWidget = false
        base.config = SharedConfig(port: 4777, token: nil, refreshInterval: 30)
        let url = try plist(["LENS_HOST": "::1", "LENS_PORT": "4800", "LENS_TOKEN": "segreto-di-prova-1234"])
        let settings = WidgetSettings(base: base, plist: url)
        #expect(!settings.reachesWidget)
        #expect(settings.load() == SharedConfig(host: "::1", port: 4800, token: "segreto-di-prova-1234", refreshInterval: 30))
    }

    @Test func conAppGroupValeQuelloDellApp() throws {
        let base = InMemorySettings()
        base.config = SharedConfig(port: 4790, token: nil, target: .local(host: "127.0.0.1", port: 4790))
        let url = try plist(["LENS_PORT": "4800", "LENS_TOKEN": "segreto-di-prova-1234"])
        #expect(WidgetSettings(base: base, plist: url).load() == base.config)
    }

    @Test func senzaAppGroupNePlistRestaIlDefault() {
        let base = InMemorySettings()
        base.reachesWidget = false
        let settings = WidgetSettings(base: base, plist: URL(fileURLWithPath: "/nonexistent/x.plist"))
        #expect(settings.load() == .default)
        settings.save(SharedConfig(port: 4800, token: nil))
        #expect(base.saves == 1)
    }

    @Test func gruppoDellApp() {
        #expect(UserDefaultsSettings.appGroup == "HS87DR6TBX.local.opencode-lens-monitor")
    }
}
