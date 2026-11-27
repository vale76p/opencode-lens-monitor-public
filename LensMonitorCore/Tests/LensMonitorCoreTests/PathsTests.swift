import Foundation
import Testing
@testable import LensMonitorCore

@Suite struct PathsTests {
    @Test func percorsiNellaHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(Paths.plist.path == home + "/Library/LaunchAgents/local.opencode-lens.plist")
        #expect(Paths.log.path == home + "/Library/Logs/opencode-lens/lens.log")
    }

    /// Nella sandbox del widget homeDirectoryForCurrentUser è il container: la home viene dall'utente.
    @Test func homeDellUtente() {
        #expect(Paths.home.path == String(cString: getpwuid(getuid())!.pointee.pw_dir))
    }

    @Test func apreIlLogSeEsiste() {
        #expect(Paths.logToOpen(fileExists: { _ in true }) == Paths.log)
    }

    @Test func senzaLogApreLaCartellaLogs() {
        #expect(Paths.logToOpen(fileExists: { _ in false }) == Paths.logsFolder)
    }
}
