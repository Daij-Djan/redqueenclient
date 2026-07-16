import Testing
@testable import RedQueen

struct AppConfigTests {
    @Test func homeserverIsConfigured() {
        #expect(AppConfig.homeserverURL.hasPrefix("https://"))
        #expect(AppConfig.defaultAgentUserID.hasPrefix("@"))
    }
}
