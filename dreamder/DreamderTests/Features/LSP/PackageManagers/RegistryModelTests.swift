import Foundation
import Synchronization
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct PackageManagerTypeAndErrorTests {
    @Test
    func everyPackageManagerTypeHasAUserFacingName() {
        let expected: [(PackageManagerType, String)] = [
            (.npm, "NPM"), (.cargo, "Cargo"), (.golang, "Go"), (.pip, "Pip"), (.gem, "Gem"),
            (.nuget, "Nuget"), (.opam, "Opam"), (.composer, "Composer"),
            (.sourceBuild, "Build From Source"), (.github, "Download From GitHub")
        ]
        for (type, name) in expected {
            #expect(type.userDescription == name, "\(type.rawValue)")
        }
    }

    @Test
    func packageManagerTypesRoundTripThroughTheirRawValues() throws {
        let decoded = try JSONDecoder().decode([PackageManagerType].self, from: Data(#"["npm","golang","sourceBuild"]"#.utf8))
        #expect(decoded == [.npm, .golang, .sourceBuild])
        #expect(PackageManagerType(rawValue: "pip") == .pip)
        #expect(PackageManagerType(rawValue: "pypi") == nil)
    }

    @Test
    func packageManagerErrorsDescribeThemselvesAndExposeTheirDetail() {
        let cases: [(PackageManagerError, String, String?)] = [
            (.unknown, "Unknown error occurred", nil),
            (.packageManagerNotInstalled, "The required package manager is not installed.", nil),
            (.initializationFailed("disk full"), "Installation directory initialization failed.", "disk full"),
            (.installationFailed("exit 1"), "Package installation failed.", "exit 1"),
            (
                .invalidConfiguration,
                "The package registry contained an invalid installation configuration.",
                nil
            )
        ]
        for (error, description, reason) in cases {
            #expect(error.errorDescription == description)
            #expect(error.failureReason == reason)
        }
    }

    @Test
    func registryManagerErrorsDescribeThemselves() throws {
        let url = try #require(URL(string: "https://example.com/registry.zip"))
        let cause = NSError(domain: "test", code: 1)
        let cases: [(RegistryManagerError, String)] = [
            (.installationRunning, "A package is already being installed."),
            (.invalidResponse(statusCode: 503), "Invalid response received: 503"),
            (.downloadFailed(url: url, error: cause), "Download for \(url) error."),
            (.maxRetriesExceeded(url: url, lastError: cause), "Maximum retries exceeded for url: \(url)"),
            (.writeFailed(error: cause), "Failed to write to file."),
            (.failedToSaveRegistryCache, "Failed to write to registry cache.")
        ]
        for (error, description) in cases {
            #expect(error.errorDescription == description)
        }
    }

    @Test
    func registryManagerErrorFailureReasonComesFromTheUnderlyingError() throws {
        let url = try #require(URL(string: "https://example.com/registry.zip"))
        let plain = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "plain failure"])
        let localized = PackageManagerError.packageManagerNotInstalled

        #expect(RegistryManagerError.installationRunning.failureReason == nil)
        #expect(RegistryManagerError.invalidResponse(statusCode: 500).failureReason == nil)
        #expect(RegistryManagerError.failedToSaveRegistryCache.failureReason == nil)
        #expect(RegistryManagerError.downloadFailed(url: url, error: plain).failureReason == "plain failure")
        #expect(RegistryManagerError.maxRetriesExceeded(url: url, lastError: localized).failureReason == localized.errorDescription)
        #expect(RegistryManagerError.writeFailed(error: plain).failureReason == "plain failure")
    }
}

@MainActor
@Suite(.uiGate)
struct InstallationMethodTests {
    private func source(_ type: PackageManagerType) -> PackageSource {
        PackageManagerFixtures.source(type: type, pkgName: "pkg", version: "2.0")
    }

    private func kind(_ manager: (any PackageManagerProtocol)?) -> String {
        switch manager {
        case is NPMPackageManager: "npm"
        case is CargoPackageManager: "cargo"
        case is PipPackageManager: "pip"
        case is GolangPackageManager: "golang"
        case is GithubPackageManager: "github"
        case nil: "none"
        default: "other"
        }
    }

    private func methods() throws -> [InstallationMethod] {
        let url = try #require(URL(string: "https://example.com/pkg.zip"))
        return [
            .standardPackage(source: source(.npm)),
            .sourceBuild(source: source(.sourceBuild), command: "make"),
            .binaryDownload(source: source(.github), url: url)
        ]
    }

    @Test
    func everyMethodExposesItsSourceDetails() throws {
        for method in try methods() {
            #expect(method.packageName == "pkg")
            #expect(method.version == "2.0")
            #expect(method.packageDescription == "pkg@2.0")
        }
        #expect(try methods().compactMap(\.packageManagerType) == [.npm, .sourceBuild, .github])
    }

    @Test
    func anUnknownMethodHasNoDetails() {
        let method = InstallationMethod.unknown
        #expect(method.packageName == nil)
        #expect(method.version == nil)
        #expect(method.packageManagerType == nil)
        #expect(method.packageDescription == nil)
        #expect(method.installerDescription == "Unknown")
        #expect(kind(method.packageManager(installPath: URL(filePath: "/tmp/ls"))) == "none")
    }

    @Test
    func theManagerMatchesThePackageType() {
        let installPath = URL(filePath: "/tmp/ls")
        let expected: [(PackageManagerType, String)] = [
            (.npm, "npm"), (.cargo, "cargo"), (.pip, "pip"), (.golang, "golang"),
            (.github, "github"), (.sourceBuild, "github"),
            (.nuget, "none"), (.opam, "none"), (.gem, "none"), (.composer, "none")
        ]
        for (type, manager) in expected {
            let method = InstallationMethod.standardPackage(source: source(type))
            #expect(kind(method.packageManager(installPath: installPath)) == manager, "\(type.rawValue)")
        }
    }

    @Test
    func unsupportedInstallersAreLabelled() {
        let supported: [PackageManagerType] = [.npm, .cargo, .golang, .pip, .sourceBuild, .github]
        for type in supported {
            #expect(InstallationMethod.standardPackage(source: source(type)).installerDescription == type.userDescription)
        }
        let unsupported: [PackageManagerType] = [.nuget, .opam, .gem, .composer]
        for type in unsupported {
            #expect(
                InstallationMethod.standardPackage(source: source(type)).installerDescription
                    == "(Unsupported) \(type.userDescription)"
            )
        }
    }
}

nonisolated final class FetchLog: Sendable {
    private let urls = Mutex<[URL]>([])

    func record(_ url: URL) {
        urls.withLock { $0.append(url) }
    }

    var recorded: [URL] {
        urls.withLock { $0 }
    }
}

@MainActor
@Suite(.uiGate)
struct RegistryManagerTimingTests {
    private static let registryURL = URL(filePath: "/fake/registry.json.zip")
    private static let checksumURL = URL(filePath: "/fake/checksums.txt")

    private static func registryJSON(name: String) -> String {
        """
        [{
          "name": "\(name)",
          "description": "d",
          "homepage": "https://example.com",
          "licenses": [],
          "languages": [],
          "categories": ["LSP"],
          "source": { "id": "pkg:npm/\(name)@1.0.0" }
        }]
        """
    }

    private func seedRegistry(named name: String, in installPath: URL) throws {
        try FileManager.default.createDirectory(at: installPath, withIntermediateDirectories: true)
        try Data(Self.registryJSON(name: name).utf8).write(to: installPath.appending(path: "registry.json"))
    }

    @Test
    func theDefaultBackoffSleepsForTheRequestedTime() async throws {
        try await withTempDir { directory in
            let manager = RegistryManager(installPath: directory, registryURL: nil, checksumURL: nil)

            try await manager.backoff(0)

            #expect(manager.registryItems.isEmpty)
        }
    }

    @Test
    func theDefaultCacheExpiryWaitsUntilItIsCancelled() async throws {
        try await withTempDir { directory in
            let manager = RegistryManager(installPath: directory, registryURL: nil, checksumURL: nil)
            let expiry = manager.cacheExpiry

            let waiting = Task { try await expiry() }
            waiting.cancel()
            let outcome = await waiting.result

            #expect(throws: CancellationError.self) { try outcome.get() }
        }
    }

    @Test
    func anExpiredCacheDownloadsTheRegistryAgain() async throws {
        try await withTempDir { directory in
            let installPath = directory.appending(path: "Language Servers", directoryHint: .isDirectory)
            try seedRegistry(named: "stale-ls", in: installPath)
            let clock = TestClock()
            let log = FetchLog()
            let archive = StoredZip.make(entries: [(name: "registry.json", contents: Self.registryJSON(name: "fresh-ls"))])
            let registryURL = Self.registryURL

            let manager = RegistryManager(
                installPath: installPath,
                registryURL: Self.registryURL,
                checksumURL: Self.checksumURL,
                fetch: { url in
                    log.record(url)
                    guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
                        throw CancellationError()
                    }
                    let body = url == registryURL ? archive : Data("checksums".utf8)
                    return (body, response)
                },
                backoff: { _ in },
                cacheExpiry: { try await clock.sleep(for: .seconds(RegistryManager.cacheExpirationInterval)) }
            )
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            try await clock.waitForSleepers(1)
            #expect(log.recorded.isEmpty)

            clock.advance(by: .seconds(RegistryManager.cacheExpirationInterval))

            try await eventually(timeout: .seconds(30)) { manager.registryItems.map(\.name) == ["fresh-ls"] }
            #expect(Set(log.recorded) == [Self.registryURL, Self.checksumURL])
        }
    }

    @Test
    func replacingTheItemsRestartsTheExpiryCountdown() async throws {
        try await withTempDir { directory in
            let installPath = directory.appending(path: "Language Servers", directoryHint: .isDirectory)
            try seedRegistry(named: "stale-ls", in: installPath)
            let clock = TestClock()
            let manager = RegistryManager(
                installPath: installPath,
                registryURL: nil,
                checksumURL: nil,
                cacheExpiry: { try await clock.sleep(for: .seconds(RegistryManager.cacheExpirationInterval)) }
            )
            try await clock.waitForSleepers(1)

            manager.setRegistryItems([])

            try await eventually(timeout: .seconds(30)) { clock.pendingSleeperCount == 1 }
            #expect(manager.registryItems.isEmpty)
        }
    }
}
