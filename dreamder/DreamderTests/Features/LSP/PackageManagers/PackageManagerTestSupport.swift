import Foundation
import Testing
@testable import Dreamder

nonisolated final class ScriptedShell: Sendable {
    typealias Responder = @Sendable (String) throws -> ProcessOutput

    private static let commandPrefix = "exec 2>&1\n"

    let runner: FakeProcessRunner
    let client: ShellClient

    init(_ responder: @escaping Responder = { _ in FakeProcessRunner.output("") }) {
        let prefix = ScriptedShell.commandPrefix
        let runner = FakeProcessRunner { invocation in
            let script = invocation.arguments.last ?? ""
            let command = script.hasPrefix(prefix) ? String(script.dropFirst(prefix.count)) : script
            return try responder(command)
        }
        let loginShell = FakeProcessRunner { _ in FakeProcessRunner.output("PATH=/usr/bin:/bin\0") }
        let environment = ShellEnvironment(runner: loginShell, baseEnvironment: { [:] })
        self.runner = runner
        self.client = ShellClient(runner: runner, shellEnvironment: environment)
    }

    var commands: [String] {
        let prefix = ScriptedShell.commandPrefix
        return runner.invocations.map { invocation in
            let script = invocation.arguments.last ?? ""
            return script.hasPrefix(prefix) ? String(script.dropFirst(prefix.count)) : script
        }
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
func runStep(_ step: PackageManagerInstallStep, shell: ScriptedShell = ScriptedShell()) async -> StepOutcome {
    let model = PackageManagerProgressModel(shellClient: shell.client)
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
