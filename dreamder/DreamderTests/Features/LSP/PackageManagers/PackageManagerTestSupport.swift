import Foundation
import Testing
@testable import Dreamder

nonisolated final class ScriptedProcesses: Sendable {
    typealias Responder = @Sendable (String) throws -> ProcessOutput

    let runner: FakeProcessRunner
    let shellEnvironment: ShellEnvironment

    init(_ responder: @escaping Responder = { _ in FakeProcessRunner.output("") }) {
        let runner = FakeProcessRunner { invocation in
            try responder(invocation.arguments.joined(separator: " "))
        }
        let loginShell = FakeProcessRunner { _ in FakeProcessRunner.output("PATH=/usr/bin:/bin\0HOME=/Users/tester\0") }
        self.runner = runner
        self.shellEnvironment = ShellEnvironment(runner: loginShell, baseEnvironment: { [:] })
    }

    var invocations: [ProcessInvocation] {
        runner.invocations
    }

    var commands: [String] {
        invocations.map { $0.arguments.joined(separator: " ") }
    }

    var arguments: [[String]] {
        invocations.map(\.arguments)
    }

    var workingDirectories: [String?] {
        invocations.map { $0.workingDirectory?.path(percentEncoded: false) }
    }

    @MainActor
    func makeModel() -> PackageManagerProgressModel {
        PackageManagerProgressModel(runner: runner, shellEnvironment: shellEnvironment)
    }

    static func failing(_ exitCode: Int32 = 1) -> ProcessOutput {
        FakeProcessRunner.output("", exitCode: exitCode)
    }
}

struct StepOutcome {
    var statuses: [String]
    var outputs: [String]
    var error: (any Error)?
}

@MainActor
func runStep(_ step: PackageManagerInstallStep, shell: ScriptedProcesses = ScriptedProcesses()) async -> StepOutcome {
    let model = shell.makeModel()
    var failure: (any Error)?
    do {
        try await step.handler(model)
    } catch {
        failure = error
    }
    model.finish()
    var statuses: [String] = []
    var outputs: [String] = []
    for await item in model.outputStream {
        switch item {
        case .status(let text):
            statuses.append(text)
        case .output(let text):
            outputs.append(text)
        }
    }
    return StepOutcome(statuses: statuses, outputs: outputs, error: failure)
}

@MainActor
func stepNamed(_ name: String, in steps: [PackageManagerInstallStep]) throws -> PackageManagerInstallStep {
    try #require(steps.first(where: { $0.name == name }), "missing step \(name)")
}

@MainActor
extension InstallStepConfirmation {
    var message: String? {
        if case .required(let message) = self { message } else { nil }
    }
}

@MainActor
extension PackageManagerError {
    var caseName: String {
        switch self {
        case .unknown: "unknown"
        case .packageManagerNotInstalled: "packageManagerNotInstalled"
        case .initializationFailed: "initializationFailed"
        case .installationFailed: "installationFailed"
        case .invalidConfiguration: "invalidConfiguration"
        case .unsafeValue: "unsafeValue"
        }
    }
}

@MainActor
extension RegistryManagerError {
    var caseName: String {
        switch self {
        case .installationRunning: "installationRunning"
        case .invalidResponse: "invalidResponse"
        case .downloadFailed: "downloadFailed"
        case .maxRetriesExceeded: "maxRetriesExceeded"
        case .writeFailed: "writeFailed"
        case .failedToSaveRegistryCache: "failedToSaveRegistryCache"
        case .checksumMissing: "checksumMissing"
        case .checksumMismatch: "checksumMismatch"
        }
    }
}

@MainActor
func thrownError<Result>(_ body: () throws -> Result) -> (any Error)? {
    do {
        _ = try body()
        return nil
    } catch {
        return error
    }
}

@MainActor
func installationFailureMessage(_ error: (any Error)?) -> String? {
    if case .installationFailed(let message) = error as? PackageManagerError { message } else { nil }
}

@MainActor
func initializationFailureMessage(_ error: (any Error)?) -> String? {
    if case .initializationFailed(let message) = error as? PackageManagerError { message } else { nil }
}

@MainActor
func errorKind(_ error: (any Error)?) -> String {
    switch error {
    case nil: "none"
    case let error as PackageManagerError: "PackageManagerError.\(error.caseName)"
    case let error as RegistryManagerError: "RegistryManagerError.\(error.caseName)"
    case let error as ShellClientError: "ShellClientError.\(error)"
    default: "other"
    }
}

nonisolated enum PackageManagerFixtures {
    static func source(
        type: PackageManagerType,
        pkgName: String = "tool",
        entryName: String = "tool-entry",
        version: String = "1.0.0",
        repositoryUrl: String? = nil,
        gitReference: PackageSource.GitReference? = nil,
        options: [String: String] = [:]
    ) -> PackageSource {
        PackageSource(
            sourceId: "pkg:\(type.rawValue)/\(pkgName)@\(version)",
            type: type,
            pkgName: pkgName,
            entryName: entryName,
            version: version,
            repositoryUrl: repositoryUrl,
            gitReference: gitReference,
            options: options
        )
    }

    static func registryItem(name: String = "tool-entry", sourceID: String = "pkg:npm/tool@1.0.0") throws -> RegistryItem {
        let json = """
        {
          "name": "\(name)",
          "description": "d",
          "homepage": "https://example.com",
          "licenses": [],
          "languages": [],
          "categories": ["LSP"],
          "source": { "id": "\(sourceID)" }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RegistryItem.self, from: Data(json.utf8))
    }

    static func installRoot(in directory: URL) throws -> URL {
        let root = directory.appending(path: "Language Servers", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

nonisolated func isExecutable(_ url: URL) -> Bool {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
    guard let permissions = attributes?[.posixPermissions] as? Int else { return false }
    return permissions & 0o100 != 0
}
