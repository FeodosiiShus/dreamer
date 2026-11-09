import Foundation
import Testing
@testable import Dreamder

nonisolated enum ScmFakeGit {
    static let executable = URL(fileURLWithPath: "/usr/bin/git")

    static func commandRunner(_ fake: FakeProcessRunner) -> GitCommandRunner {
        GitCommandRunner(runner: fake, gitExecutable: executable, baseEnvironment: { [:] })
    }

    static func client(
        directory: URL = URL(fileURLWithPath: "/tmp/dreamder-fake-\(UUID().uuidString)", isDirectory: true),
        scopePath: String? = nil,
        handler: @escaping FakeProcessRunner.Handler
    ) -> (client: GitClient, fake: FakeProcessRunner) {
        let fake = FakeProcessRunner(handler: handler)
        return (GitClient(directoryURL: directory, scopePath: scopePath, commandRunner: commandRunner(fake)), fake)
    }

    static func arguments(_ invocation: ProcessInvocation) -> [String] {
        Array(invocation.arguments.dropFirst(GitCommandRunner.configuration.count))
    }

    static func ok(_ stdout: String = "") -> ProcessOutput {
        FakeProcessRunner.output(stdout)
    }

    static func failure(_ stderr: String, code: Int32 = 128) -> ProcessOutput {
        FakeProcessRunner.output("", stderr: stderr, exitCode: code)
    }
}

nonisolated struct ScmCountConfig: GitConfigRepresentable {
    let count: Int

    init(count: Int) {
        self.count = count
    }

    init?(configValue: String) {
        guard let count = Int(configValue) else { return nil }
        self.count = count
    }

    var asConfigValue: String {
        String(count)
    }
}
