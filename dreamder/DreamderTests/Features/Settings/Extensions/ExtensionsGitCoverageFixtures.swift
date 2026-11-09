import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Dreamder

struct CovExtGitNoNetwork: Error {}

struct CovExtGitFailure: Error {}

struct CovExtGitLocalizedFailure: LocalizedError {
    var errorDescription: String? { "Cov extension failure description" }
    var failureReason: String? { "Cov extension failure reason" }
    var recoverySuggestion: String? { "Cov extension recovery suggestion" }
}

@MainActor
final class CovExtGitStepLog {
    var ran = 0
}

@MainActor
final class CovExtGitStepGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private(set) var isWaiting = false

    func wait() async {
        if opened { return }
        isWaiting = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in self.open() }
        }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class CovExtGitRowRecorder {
    private(set) var cancels = 0
    private(set) var installs: [String] = []

    func cancel() {
        cancels += 1
    }

    func install(_ item: RegistryItem) {
        installs.append(item.name)
    }
}

@MainActor
enum CovExtGitRegistryFixtures {
    static func item(
        name: String,
        sourceID: String? = nil,
        homepage: String = "https://example.com/tool",
        description: String = "A language server"
    ) throws -> RegistryItem {
        let object: [String: Any] = [
            "name": name,
            "description": description,
            "homepage": homepage,
            "licenses": [String](),
            "languages": [String](),
            "categories": ["LSP"],
            "source": ["id": sourceID ?? "pkg:npm/\(name)@1.2.3"]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RegistryItem.self, from: data)
    }

    static func uniqueName(_ prefix: String = "covext-ls") -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }

    static func manager(in directory: URL) -> RegistryManager {
        RegistryManager(
            installPath: directory.appending(path: "Language Servers", directoryHint: .isDirectory),
            registryURL: nil,
            checksumURL: nil,
            fetch: noFetch,
            backoff: noBackoff
        )
    }

    nonisolated static func noFetch(_ url: URL) async throws -> (Data, URLResponse) {
        throw CovExtGitNoNetwork()
    }

    nonisolated static func noBackoff(_ seconds: TimeInterval) async throws {}

    static func step(
        _ name: String,
        confirmation: InstallStepConfirmation = .none,
        handler: @escaping @MainActor (PackageManagerProgressModel) async throws -> Void
    ) -> PackageManagerInstallStep {
        PackageManagerInstallStep(name: name, confirmation: confirmation, handler: handler)
    }

    static func register(_ name: String, in manager: RegistryManager, enabled: Bool = true) {
        manager.installedLanguageServers[name] = SettingsData.InstalledLanguageServer(
            packageName: name,
            isEnabled: enabled,
            version: "1.2.3"
        )
    }
}
