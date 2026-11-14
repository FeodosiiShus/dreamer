import Foundation
import Testing
@testable import Dreamder

struct TestHostTests {
    @Test(arguments: [
        ([String: String](), false),
        (["DREAMDER_SHARD": "1"], false),
        (["XCTestConfigurationFilePath": "/tmp/host.xctestconfiguration"], true),
        (["XCTestConfigurationFilePath": ""], true),
        (["xctestconfigurationfilepath": "/tmp/host.xctestconfiguration"], false)
    ])
    func aProcessIsATestHostOnlyWhenTheXCTestConfigurationVariableIsSet(
        environment: [String: String],
        expected: Bool
    ) {
        #expect(TestHost.isActive(in: environment) == expected)
    }

    @Test
    func theKeyIsTheOneXCTestSetsForItsHost() {
        #expect(TestHost.environmentKey == "XCTestConfigurationFilePath")
    }

    @Test
    func theDefaultEnvironmentIsTheOneOfThisProcess() {
        #expect(TestHost.isActive() == (ProcessInfo.processInfo.environment[TestHost.environmentKey] != nil))
        #expect(TestHost.isActive())
    }
}
