import Foundation
import Testing
@testable import Dreamder

struct EditorLoggingTests {
    @Test
    func subsystemUsesTheBundleIdentifierWhenPresent() throws {
        let identifier = try #require(Bundle.main.bundleIdentifier)

        #expect(EditorLogging.subsystem(of: .main) == identifier)
    }

    @Test
    func subsystemFallsBackWhenTheBundleHasNoIdentifier() throws {
        try withTempDir { directory in
            let bundle = try #require(Bundle(url: directory))

            #expect(bundle.bundleIdentifier == nil)
            #expect(EditorLogging.subsystem(of: bundle) == EditorLogging.fallbackSubsystem)
            _ = EditorLogging.logger(category: "EditorLoggingTests", bundle: bundle)
        }
    }
}
