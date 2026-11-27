import Testing
@testable import LensMonitorCore

@Suite struct LaunchctlParserTests {
    @Test func printInEsecuzioneConPid() {
        #expect(LaunchctlParser.parsePrint(Fixtures.printRunning) == .init(running: true, pid: 85289))
    }

    @Test func printNonInEsecuzioneSenzaPid() {
        #expect(LaunchctlParser.parsePrint(Fixtures.printNotRunning) == .init(running: false, pid: nil))
    }

    @Test func ignoraStateEPidNeiBlocchiAnnidati() {
        #expect(LaunchctlParser.parsePrint(Fixtures.printNestedRunning) == .init(running: false, pid: nil))
    }

    @Test func printVuoto() {
        #expect(LaunchctlParser.parsePrint("") == .init(running: false, pid: nil))
    }

    @Test func disabilitato() {
        #expect(LaunchctlParser.parseDisabled(Fixtures.disabledWithLens, label: "local.opencode-lens") == true)
    }

    @Test func abilitato() {
        #expect(LaunchctlParser.parseDisabled(Fixtures.enabledWithLens, label: "local.opencode-lens") == false)
    }

    @Test func etichettaConStessoPrefissoNonCorrisponde() {
        #expect(LaunchctlParser.parseDisabled(Fixtures.disabledWithoutLens, label: "local.opencode-lens") == nil)
    }
}
