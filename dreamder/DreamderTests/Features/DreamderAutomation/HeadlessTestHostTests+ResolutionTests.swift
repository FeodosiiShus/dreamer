import AppKit
import Testing
@testable import Dreamder

@MainActor
extension HeadlessTestHostTests {
    @Test(arguments: [
        ([String: String](), [String](), false, false),
        ([String: String](), [String](), true, false),
        (["DREAMDER_HEADLESS": "1"], [String](), false, true),
        (["DREAMDER_HEADLESS": "1"], [String](), true, true),
        (["DREAMDER_HEADLESS": "0"], [String](), false, false),
        (["DREAMDER_HEADLESS": "0"], [String](), true, false),
        (["DREAMDER_HEADLESS": "yes"], [String](), false, false),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "YES"], false, true),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "yes"], false, true),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "true"], false, true),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "1"], false, true),
        ([String: String](), ["Dreamder", "/tmp/project", "--args", "-DreamderHeadless", "YES"], false, true),
        (["DREAMDER_HEADLESS": "0"], ["Dreamder", "-DreamderHeadless", "YES"], false, true),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "NO"], true, false),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "0"], true, false),
        ([String: String](), ["Dreamder", "-DreamderHeadless"], true, false),
        ([String: String](), ["Dreamder", "-DreamderHeadless", "-ApplePersistenceIgnoreState"], true, false),
        ([String: String](), ["Dreamder", "-DreamderHeadless=YES"], true, false),
        ([String: String](), ["Dreamder", "DreamderHeadless", "YES"], true, false),
        ([String: String](), ["Dreamder", "-OtherFlag", "YES"], true, false)
    ])
    func headlessIsEnabledOnlyByTheEnvironmentOrTheLaunchArgumentOfThisProcess(
        environment: [String: String],
        arguments: [String],
        persistedDefault: Bool,
        expected: Bool
    ) throws {
        try withIsolatedDefaults { defaults in
            defaults.set(persistedDefault, forKey: DreamderHeadless.argumentKey)

            let resolved = DreamderHeadless.resolveIsEnabled(environment: environment, arguments: arguments)

            #expect(resolved == expected)
        }
    }

    @Test
    func theLiveGateReadsTheEnvironmentAndArgumentsOfThisProcess() {
        let process = ProcessInfo.processInfo

        let resolved = DreamderHeadless.resolveIsEnabled(
            environment: process.environment,
            arguments: process.arguments
        )

        #expect(DreamderHeadless.isEnabled == resolved)
    }
}
