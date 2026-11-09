import CryptoKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct RegistryManagerTests {
    static let registryURL = URL(filePath: "/fake/registry.json.zip")
    static let checksumURL = URL(filePath: "/fake/checksums.txt")

    static let registryJSON = #"""
    [
      {
        "name": "alpha-ls",
        "description": "Alpha language server",
        "homepage": "https://example.com/alpha",
        "licenses": ["MIT"],
        "languages": ["Alpha"],
        "categories": ["LSP"],
        "source": {
          "id": "pkg:npm/alpha-ls@1.0.0",
          "version_overrides": [
            { "constraint": "semver:<=0.9.0", "id": "pkg:npm/alpha-ls@0.9.0" }
          ]
        },
        "bin": { "alpha-ls": "npm:alpha-ls" }
      },
      {
        "name": "beta-formatter",
        "description": "Beta formatter",
        "homepage": "https://example.com/beta",
        "licenses": ["MIT"],
        "languages": ["Beta"],
        "categories": ["Formatter"],
        "source": { "id": "pkg:npm/beta-formatter@2.0.0" }
      },
      {
        "name": "gamma-ls",
        "description": "Gamma language server",
        "homepage": "https://example.com/gamma",
        "licenses": ["Apache-2.0"],
        "languages": ["Gamma"],
        "categories": ["Linter", "LSP"],
        "source": { "id": "pkg:pypi/gamma-ls@3.1.0" }
      }
    ]
    """#

    static let staleJSON = #"""
    [
      {
        "name": "stale-ls",
        "description": "Stale language server",
        "homepage": "https://example.com/stale",
        "licenses": [],
        "languages": [],
        "categories": ["LSP"],
        "source": { "id": "pkg:npm/stale-ls@0.0.1" }
      }
    ]
    """#

    static let registryZip = StoredZip.make(entries: [("registry.json", registryJSON)])

    func installPath(in directory: URL) -> URL {
        directory.appending(path: "Language Servers", directoryHint: .isDirectory)
    }

    func seedRegistry(_ json: String, at installPath: URL, ageInHours: Double = 0) throws {
        try FileManager.default.createDirectory(at: installPath, withIntermediateDirectories: true)
        let file = installPath.appending(path: "registry.json")
        try Data(json.utf8).write(to: file)
        if ageInHours > 0 {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: -ageInHours * 3600)],
                ofItemAtPath: file.path(percentEncoded: false)
            )
        }
    }

    func makeManager(
        installPath: URL,
        network: FakeNetwork,
        delays: DelayRecorder,
        registryURL: URL? = RegistryManagerTests.registryURL
    ) -> RegistryManager {
        RegistryManager(
            installPath: installPath,
            registryURL: registryURL,
            checksumURL: Self.checksumURL,
            fetch: { url in try await network.respond(to: url) },
            backoff: { seconds in await delays.record(seconds) }
        )
    }

    func makeOfflineManager(installPath: URL) -> RegistryManager {
        makeManager(installPath: installPath, network: FakeNetwork(), delays: DelayRecorder(), registryURL: nil)
    }

    func makeItem(
        name: String,
        sourceID: String,
        categories: [String] = ["LSP"],
        sourceExtras: String = ""
    ) throws -> RegistryItem {
        let list = categories.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {
          "name": "\(name)",
          "description": "d",
          "homepage": "https://example.com",
          "licenses": [],
          "languages": [],
          "categories": [\(list)],
          "source": { "id": "\(sourceID)"\(sourceExtras) }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RegistryItem.self, from: Data(json.utf8))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func checksumBody(for archive: Data, file: String = "registry.json.zip") -> Data {
        Data("\(sha256Hex(archive))  \(file)\n".utf8)
    }

    func serve(_ network: FakeNetwork, zip: Data, checksums: Data? = nil) async {
        await network.script(Self.registryURL, [.body(zip, status: 200)])
        await network.script(Self.checksumURL, [.body(checksums ?? Self.checksumBody(for: zip), status: 200)])
    }

    func stagingExists(_ installPath: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: installPath.appending(path: RegistryManager.stagingDirectoryName).path(percentEncoded: false)
        )
    }

    func snapshot(of directory: URL) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
    }

    func checksumFailure(_ error: Error?) -> String? {
        guard let error = error as? RegistryManagerError else { return nil }
        switch error {
        case .checksumMissing(let file): return "missing:\(file)"
        case .checksumMismatch(let file): return "mismatch:\(file)"
        default: return nil
        }
    }

    func uniqueName() -> String {
        "registry-manager-test-\(UUID().uuidString.prefix(8).lowercased())"
    }

    func caught<Result>(_ body: () throws -> Result) -> Error? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }

    func isInstallationRunning(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .installationRunning = error else { return false }
        return true
    }

    func isInvalidConfiguration(_ error: Error?) -> Bool {
        guard let error = error as? PackageManagerError, case .invalidConfiguration = error else { return false }
        return true
    }

    func invalidResponseStatus(_ error: Error?) -> Int? {
        guard let error = error as? RegistryManagerError, case .invalidResponse(let status) = error else { return nil }
        return status
    }

    func isDownloadFailure(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .downloadFailed = error else { return false }
        return true
    }

    func isWriteFailure(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .writeFailed = error else { return false }
        return true
    }

    func isMissingRegistryCache(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .failedToSaveRegistryCache = error else { return false }
        return true
    }

    func lastRetryError(of error: Error?, url: URL) -> Error? {
        guard let error = error as? RegistryManagerError,
              case .maxRetriesExceeded(let failedURL, let lastError) = error,
              failedURL == url else { return nil }
        return lastError
    }
}
