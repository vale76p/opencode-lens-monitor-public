import Foundation
import Testing
@testable import LensMonitorCore

@MainActor
@Suite struct RecordedLoginItemTests {
    /// Dominio di prova con un nome fisso per test, vuotato all'inizio e alla fine (come in
    /// SharedSettingsTests).
    final class Domain {
        let name: String
        let defaults: UserDefaults
        init(_ test: String = #function) {
            name = "test.opencode-lens-monitor.login.\(test.prefix { $0 != "(" })"
            defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
        }
        deinit { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }

    static let home = "/Users/tu"
    static let installed = "/Users/tu/Applications/OpenCode Lens Monitor.app"

    func item(_ base: FakeLoginItem, _ domain: Domain, at path: String = installed) -> RecordedLoginItem {
        RecordedLoginItem(base: base, defaults: domain.defaults, bundlePath: path, home: Self.home)
    }

    @Test func spostataDaApplicationsRegistraDiNuovo() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        base.status = .enabled
        domain.defaults.set("/Applications/OpenCode Lens Monitor.app", forKey: RecordedLoginItem.pathKey)
        try item(base, domain).relocateIfMoved()
        #expect(base.calls == [false, true])
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == Self.installed)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.statusKey) == "enabled")
    }

    /// Fino alla 0.4.0 il percorso non veniva annotato: si registra una volta da qui.
    @Test func senzaPercorsoAnnotatoRegistraUnaVolta() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        base.status = .enabled
        try item(base, domain).relocateIfMoved()
        try item(base, domain).relocateIfMoved()
        #expect(base.calls == [false, true])
    }

    @Test func stessoPercorsoNonTocca() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        base.status = .enabled
        domain.defaults.set(Self.installed, forKey: RecordedLoginItem.pathKey)
        try item(base, domain).relocateIfMoved()
        #expect(base.calls.isEmpty)
    }

    @Test func spentoNonRegistraEAnnotaLoStato() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        domain.defaults.set("/Applications/OpenCode Lens Monitor.app", forKey: RecordedLoginItem.pathKey)
        try item(base, domain).relocateIfMoved()
        #expect(base.calls.isEmpty)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == nil)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.statusKey) == "disabled")
    }

    @Test func inAttesaDiApprovazioneRegistraDiNuovo() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        base.status = .requiresApproval
        try item(base, domain).relocateIfMoved()
        #expect(base.calls == [false, true])
    }

    /// Una build di sviluppo (DerivedData) ha lo stesso bundle id e le stesse UserDefaults:
    /// non deve spostare il login item su di sé né cambiare il percorso annotato.
    @Test func fuoriDaApplicationsNonToccaNiente() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        base.status = .enabled
        domain.defaults.set(Self.installed, forKey: RecordedLoginItem.pathKey)
        let dev = item(base, domain, at: "/Users/tu/Library/Caches/opencode-lens-monitor/DerivedData-dev/Build/Products/Debug/OpenCode Lens Monitor.app")
        try dev.relocateIfMoved()
        try dev.setEnabled(false)
        #expect(base.calls == [false])
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == Self.installed)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.statusKey) == nil)
    }

    @Test func inApplicationsDiSistemaAnnota() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        try item(base, domain, at: "/Applications/OpenCode Lens Monitor.app").setEnabled(true)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == "/Applications/OpenCode Lens Monitor.app")
    }

    @Test func interruttoreAnnotaPercorsoEStato() throws {
        let domain = Domain()
        let base = FakeLoginItem()
        let recorded = item(base, domain)
        try recorded.setEnabled(true)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == Self.installed)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.statusKey) == "enabled")
        try recorded.setEnabled(false)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == nil)
        #expect(domain.defaults.string(forKey: RecordedLoginItem.statusKey) == "disabled")
    }

    /// Se la nuova registrazione fallisce resta annotato il percorso vecchio: install.sh lo
    /// segnala e al prossimo avvio l'app riprova.
    @Test func erroreLasciaIlPercorsoVecchio() {
        let domain = Domain()
        let base = FakeLoginItem()
        base.status = .enabled
        base.error = CocoaError(.fileNoSuchFile)
        domain.defaults.set("/Applications/OpenCode Lens Monitor.app", forKey: RecordedLoginItem.pathKey)
        #expect(throws: CocoaError.self) { try item(base, domain).relocateIfMoved() }
        #expect(domain.defaults.string(forKey: RecordedLoginItem.statusKey) == "enabled")
        #expect(domain.defaults.string(forKey: RecordedLoginItem.pathKey) == "/Applications/OpenCode Lens Monitor.app")
    }
}
