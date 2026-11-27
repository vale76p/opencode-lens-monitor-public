import Testing
@testable import LensMonitorCore

@Suite struct LensCompatTests {
    @Test func confrontaConIlMinimo() {
        #expect(LensCompat.isSupported("0.38.0") == true)
        #expect(LensCompat.isSupported("0.44.0") == true)
        #expect(LensCompat.isSupported("1.0.0") == true)
        #expect(LensCompat.isSupported("0.37.9") == false)
        #expect(LensCompat.isSupported("0.9.0") == false)
    }

    @Test func versioneConSuffissoOIlleggibile() {
        #expect(LensCompat.isSupported("0.44.0-dev") == true)
        #expect(LensCompat.isSupported("0.37.0+abc") == false)
        #expect(LensCompat.isSupported("0.38") == true)   // patch mancante = 0
        #expect(LensCompat.isSupported("v0.38.0") == nil)
        #expect(LensCompat.isSupported("abc") == nil)
        #expect(LensCompat.isSupported("") == nil)
    }
}
