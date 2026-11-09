import Foundation
import Testing
@testable import Dreamder

nonisolated enum StoredZip {
    static func make(entries: [(name: String, contents: String)]) -> Data {
        var archive = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let body = Data(entry.contents.utf8)
            let checksum = crc32(body)
            let offset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0x21))
            archive.appendLittleEndian(checksum)
            archive.appendLittleEndian(UInt32(body.count))
            archive.appendLittleEndian(UInt32(body.count))
            archive.appendLittleEndian(UInt16(name.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(name)
            archive.append(body)

            directory.appendLittleEndian(UInt32(0x0201_4B50))
            directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0x21))
            directory.appendLittleEndian(checksum)
            directory.appendLittleEndian(UInt32(body.count))
            directory.appendLittleEndian(UInt32(body.count))
            directory.appendLittleEndian(UInt16(name.count))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt32(0))
            directory.appendLittleEndian(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(directory.count))
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

extension Data {
    nonisolated mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

private actor FakeNetwork {
    enum Outcome: Sendable {
        case body(Data, status: Int)
        case failure(String)
        case notHTTP
    }

    struct Failure: Error, Sendable {
        let message: String
    }

    private var scripts: [URL: [Outcome]] = [:]
    private var holding = false
    private var heldRequests: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [URL] = []

    func script(_ url: URL, _ outcomes: [Outcome]) {
        scripts[url] = outcomes
    }

    func hold() {
        holding = true
    }

    func release() {
        holding = false
        let waiting = heldRequests
        heldRequests = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    func requestCount(for url: URL) -> Int {
        requests.filter { $0 == url }.count
    }

    func respond(to url: URL) async throws -> (Data, URLResponse) {
        requests.append(url)
        if holding {
            await withCheckedContinuation { heldRequests.append($0) }
        }
        var queue = scripts[url] ?? []
        guard let outcome = queue.first else {
            throw Failure(message: "unscripted \(url.absoluteString)")
        }
        if queue.count > 1 {
            queue.removeFirst()
            scripts[url] = queue
        }
        switch outcome {
        case .body(let data, let status):
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
                throw Failure(message: "unusable status \(status)")
            }
            return (data, response)
        case .failure(let message):
            throw Failure(message: message)
        case .notHTTP:
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
    }
}

private actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        values.append(seconds)
    }
}

@MainActor
private final class StepGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private(set) var isWaiting = false

    func wait() async {
        if opened { return }
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func markWaiting() {
        isWaiting = true
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private struct StepFailure: Error {}

@MainActor
@Suite(.serialized, .uiGate)
struct RegistryManagerTests {
    private static let registryURL = URL(filePath: "/fake/registry.json.zip")
    private static let checksumURL = URL(filePath: "/fake/checksums.txt")

    private static let registryJSON = #"""
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

    private static let staleJSON = #"""
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

    private func installPath(in directory: URL) -> URL {
        directory.appending(path: "Language Servers", directoryHint: .isDirectory)
    }

    private func seedRegistry(_ json: String, at installPath: URL, ageInHours: Double = 0) throws {
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

    private func makeManager(
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

    private func makeOfflineManager(installPath: URL) -> RegistryManager {
        makeManager(installPath: installPath, network: FakeNetwork(), delays: DelayRecorder(), registryURL: nil)
    }

    private func makeItem(name: String, sourceID: String, categories: [String] = ["LSP"]) throws -> RegistryItem {
        let list = categories.map { "\"\($0)\"" }.joined(separator: ",")
        let json = """
        {
          "name": "\(name)",
          "description": "d",
          "homepage": "https://example.com",
          "licenses": [],
          "languages": [],
          "categories": [\(list)],
          "source": { "id": "\(sourceID)" }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RegistryItem.self, from: Data(json.utf8))
    }

    private func uniqueName() -> String {
        "registry-manager-test-\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func caught<Result>(_ body: () throws -> Result) -> Error? {
        do {
            _ = try body()
            return nil
        } catch {
            return error
        }
    }

    private func isInstallationRunning(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .installationRunning = error else { return false }
        return true
    }

    private func isInvalidConfiguration(_ error: Error?) -> Bool {
        guard let error = error as? PackageManagerError, case .invalidConfiguration = error else { return false }
        return true
    }

    private func invalidResponseStatus(_ error: Error?) -> Int? {
        guard let error = error as? RegistryManagerError, case .invalidResponse(let status) = error else { return nil }
        return status
    }

    private func isDownloadFailure(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .downloadFailed = error else { return false }
        return true
    }

    private func isWriteFailure(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .writeFailed = error else { return false }
        return true
    }

    private func isMissingRegistryCache(_ error: Error?) -> Bool {
        guard let error = error as? RegistryManagerError, case .failedToSaveRegistryCache = error else { return false }
        return true
    }

    private func lastRetryError(of error: Error?, url: URL) -> Error? {
        guard let error = error as? RegistryManagerError,
              case .maxRetriesExceeded(let failedURL, let lastError) = error,
              failedURL == url else { return nil }
        return lastError
    }

    @Test
    func missingRegistryFileLoadsNothing() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))

            #expect(manager.loadItemsFromDisk() == nil)
            #expect(manager.registryItems.isEmpty)
        }
    }

    @Test
    func freshRegistryKeepsOnlyLanguageServersInFileOrder() throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.registryJSON, at: path)
            let manager = makeOfflineManager(installPath: path)

            #expect(manager.loadItemsFromDisk()?.map(\.name) == ["alpha-ls", "gamma-ls"])
        }
    }

    @Test
    func startingWithAFreshRegistryPublishesItWithoutTouchingTheNetwork() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.registryJSON, at: path)
            let network = FakeNetwork()
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            try await Task.sleep(for: .milliseconds(200))

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            #expect(await network.requests.isEmpty)
            #expect(manager.isDownloadingRegistry == false)
        }
    }

    @Test
    func versionOverridesInTheDownloadedRegistryAreKept() throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.registryJSON, at: path)
            let manager = makeOfflineManager(installPath: path)

            let alpha = try #require(manager.loadItemsFromDisk()?.first { $0.name == "alpha-ls" })
            let overrides = try #require(alpha.source.versionOverrides)

            #expect(overrides.map(\.constraint) == ["semver:<=0.9.0"])
            #expect(overrides.map(\.id) == ["pkg:npm/alpha-ls@0.9.0"])
        }
    }

    @Test(arguments: [0.0, 1.0, 23.0])
    func registryYoungerThanADayIsUsed(ageInHours: Double) throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.registryJSON, at: path, ageInHours: ageInHours)
            let manager = makeOfflineManager(installPath: path)

            #expect(manager.loadItemsFromDisk()?.map(\.name) == ["alpha-ls", "gamma-ls"])
        }
    }

    @Test(arguments: [24.0, 25.0, 24.0 * 30])
    func registryAtLeastADayOldIsIgnored(ageInHours: Double) throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.registryJSON, at: path, ageInHours: ageInHours)
            let manager = makeOfflineManager(installPath: path)

            #expect(manager.loadItemsFromDisk() == nil)
        }
    }

    @Test(arguments: [
        "{ not json",
        "{\"name\": \"alpha-ls\"}",
        "[{\"name\": \"only-a-name\"}]",
        ""
    ])
    func unreadableRegistryLoadsNothing(contents: String) throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(contents, at: path)
            let manager = makeOfflineManager(installPath: path)

            #expect(manager.loadItemsFromDisk() == nil)
        }
    }

    @Test
    func oneMalformedEntryDiscardsTheWholeRegistry() throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            let broken = Self.registryJSON.replacingOccurrences(of: "\"licenses\": [\"MIT\"],", with: "")
            try seedRegistry(broken, at: path)
            let manager = makeOfflineManager(installPath: path)

            #expect(manager.loadItemsFromDisk() == nil)
        }
    }

    @Test
    func registryWithoutLanguageServersLoadsAsEmptyList() throws {
        try withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry("[]", at: path)
            let manager = makeOfflineManager(installPath: path)

            #expect(manager.loadItemsFromDisk()?.isEmpty == true)
        }
    }

    @Test(arguments: [200, 204, 299])
    func downloadReturnsTheBodyOfASuccessfulResponse(status: Int) async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(installPath: installPath(in: directory), network: network, delays: delays, registryURL: nil)
            await network.script(Self.registryURL, [.body(Data("payload".utf8), status: status)])

            let data = try await manager.download(from: Self.registryURL)

            #expect(String(decoding: data, as: UTF8.self) == "payload")
            #expect(await network.requestCount(for: Self.registryURL) == 1)
            #expect(await delays.values.isEmpty)
        }
    }

    @Test(arguments: [199, 300, 301, 404, 500, 503])
    func downloadRetriesWithDoublingDelaysThenReportsTheLastResponse(status: Int) async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(installPath: installPath(in: directory), network: network, delays: delays, registryURL: nil)
            await network.script(Self.registryURL, [.body(Data(), status: status)])

            var failure: Error?
            do {
                _ = try await manager.download(from: Self.registryURL)
            } catch {
                failure = error
            }

            #expect(invalidResponseStatus(lastRetryError(of: failure, url: Self.registryURL)) == status)
            #expect(await network.requestCount(for: Self.registryURL) == 4)
            #expect(await delays.values == [2, 4, 8])
        }
    }

    @Test
    func downloadRecoversWhenALaterAttemptSucceeds() async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(installPath: installPath(in: directory), network: network, delays: delays, registryURL: nil)
            await network.script(Self.registryURL, [
                .body(Data(), status: 503),
                .failure("connection reset"),
                .body(Data("finally".utf8), status: 200)
            ])

            let data = try await manager.download(from: Self.registryURL)

            #expect(String(decoding: data, as: UTF8.self) == "finally")
            #expect(await network.requestCount(for: Self.registryURL) == 3)
            #expect(await delays.values == [2, 4])
        }
    }

    @Test
    func downloadTreatsAResponseThatIsNotHTTPAsAFailure() async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(installPath: installPath(in: directory), network: network, delays: delays, registryURL: nil)
            await network.script(Self.registryURL, [.notHTTP])

            var failure: Error?
            do {
                _ = try await manager.download(from: Self.registryURL)
            } catch {
                failure = error
            }

            #expect(isDownloadFailure(lastRetryError(of: failure, url: Self.registryURL)))
            #expect(await network.requestCount(for: Self.registryURL) == 4)
        }
    }

    @Test
    func downloadStartingOnTheLastAllowedAttemptDoesNotRetry() async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(installPath: installPath(in: directory), network: network, delays: delays, registryURL: nil)
            await network.script(Self.registryURL, [.failure("offline")])

            var failure: Error?
            do {
                _ = try await manager.download(from: Self.registryURL, attempt: 4)
            } catch {
                failure = error
            }

            #expect(lastRetryError(of: failure, url: Self.registryURL) != nil)
            #expect(await network.requestCount(for: Self.registryURL) == 1)
            #expect(await delays.values.isEmpty)
        }
    }

    @Test
    func missingRegistryIsDownloadedWhenTheManagerStarts() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", Self.registryJSON)]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("checksum registry.json.zip\n".utf8), status: 200)])

            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            try await eventually(timeout: .seconds(20)) { manager.registryItems.count == 2 || manager.downloadError != nil }

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            let requestedPaths = await network.requests.map(\.path)
            #expect(Set(requestedPaths) == [Self.registryURL.path, Self.checksumURL.path])
            #expect(manager.isDownloadingRegistry == false)
            #expect(manager.downloadError == nil)
        }
    }

    @Test
    func downloadReplacesTheStaleRegistryAndStoresTheChecksums() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", Self.registryJSON)]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("abc123  registry.json.zip\n".utf8), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            manager.handleUpdateError(RegistryManagerError.failedToSaveRegistryCache)

            await manager.downloadRegistryItems()

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            #expect(manager.downloadError == nil)
            let attributes = try FileManager.default.attributesOfItem(atPath: path.appending(path: "registry.json").path(percentEncoded: false))
            let modified = try #require(attributes[.modificationDate] as? Date)
            #expect(abs(modified.timeIntervalSinceNow) < 3600)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.registryJSON)
            #expect(try String(contentsOf: path.appending(path: "checksums.txt"), encoding: .utf8) == "abc123  registry.json.zip\n")
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "temp.zip").path) == false)
            #expect(await network.requestCount(for: Self.registryURL) == 1)
            #expect(await network.requestCount(for: Self.checksumURL) == 1)
        }
    }

    @Test
    func downloadReplacesAPreviousTemporaryArchive() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            try Data("leftover".utf8).write(to: path.appending(path: "temp.zip"))
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", Self.registryJSON)]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "temp.zip").path) == false)
        }
    }

    @Test
    func downloadWithoutARegistryURLDoesNothing() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder(), registryURL: nil)

            await manager.downloadRegistryItems()

            #expect(await network.requests.isEmpty)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.downloadError == nil)
            #expect(manager.isDownloadingRegistry == false)
        }
    }

    @Test
    func downloadFlagIsRaisedWhileRequestsAreInFlight() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", Self.registryJSON)]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])
            await network.hold()
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            let download = Task { @MainActor in
                await manager.downloadRegistryItems()
            }
            try await eventually { manager.isDownloadingRegistry }
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            await network.release()
            await download.value

            #expect(manager.isDownloadingRegistry == false)
            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
        }
    }

    @Test
    func failedRegistryDownloadKeepsTheLoadedItemsAndRecordsTheError() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(Data(), status: 500)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(invalidResponseStatus(lastRetryError(of: manager.downloadError, url: Self.registryURL)) == 500)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.isDownloadingRegistry == false)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
        }
    }

    @Test
    func failedChecksumDownloadDiscardsTheDownloadedRegistry() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", Self.registryJSON)]), status: 200)])
            await network.script(Self.checksumURL, [.failure("no route to host")])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(lastRetryError(of: manager.downloadError, url: Self.checksumURL) != nil)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
        }
    }

    @Test
    func corruptArchiveIsReportedAsAWriteFailure() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(Data("this is not a zip archive".utf8), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(isWriteFailure(manager.downloadError))
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.isDownloadingRegistry == false)
        }
    }

    @Test
    func archiveWithoutARegistryFileFailsToPopulateTheCache() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("other.json", "[]")]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(isMissingRegistryCache(manager.downloadError))
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
        }
    }

    @Test
    func archiveWithUnreadableRegistryFailsToPopulateTheCache() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", "{ broken")]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(isMissingRegistryCache(manager.downloadError))
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
        }
    }

    @Test
    func firstStartWithAnUnwritableInstallLocationReportsAWriteFailure() async throws {
        try await withTempDir { directory in
            let blocker = directory.appending(path: "blocker")
            try Data("a file, not a folder".utf8).write(to: blocker)
            let network = FakeNetwork()
            await network.script(Self.registryURL, [.body(StoredZip.make(entries: [("registry.json", Self.registryJSON)]), status: 200)])
            await network.script(Self.checksumURL, [.body(Data("sum".utf8), status: 200)])

            let manager = makeManager(
                installPath: blocker.appending(path: "Language Servers", directoryHint: .isDirectory),
                network: network,
                delays: DelayRecorder()
            )
            try await eventually { manager.downloadError != nil }

            #expect(isWriteFailure(manager.downloadError))
            #expect(manager.registryItems.isEmpty)
        }
    }

    @Test
    func updateErrorsAreAlwaysRecordedForThePresentation() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let url = Self.registryURL
            let cause = NSError(domain: "RegistryManagerTests", code: 7)
            let errors: [Error] = [
                RegistryManagerError.installationRunning,
                RegistryManagerError.invalidResponse(statusCode: 418),
                RegistryManagerError.downloadFailed(url: url, error: cause),
                RegistryManagerError.maxRetriesExceeded(url: url, lastError: cause),
                RegistryManagerError.writeFailed(error: cause),
                RegistryManagerError.failedToSaveRegistryCache,
                cause
            ]

            for error in errors {
                manager.downloadError = nil
                manager.handleUpdateError(error)
                #expect(manager.downloadError?.localizedDescription == error.localizedDescription)
            }
        }
    }

    @Test
    func togglingAnInstalledServerKeepsItsVersion() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1.2.3")
            defer { manager.installedLanguageServers.removeValue(forKey: name) }

            manager.setPackageEnabled(packageName: name, enabled: false)
            #expect(manager.installedLanguageServers[name] == SettingsData.InstalledLanguageServer(packageName: name, isEnabled: false, version: "1.2.3"))

            manager.setPackageEnabled(packageName: name, enabled: true)
            #expect(manager.installedLanguageServers[name] == SettingsData.InstalledLanguageServer(packageName: name, isEnabled: true, version: "1.2.3"))
        }
    }

    @Test
    func togglingAnUnknownServerDoesNotRegisterIt() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()

            manager.setPackageEnabled(packageName: name, enabled: true)

            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func removingAServerWithoutFilesOnlyForgetsIt() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1")
            defer { manager.installedLanguageServers.removeValue(forKey: name) }

            try await manager.removeLanguageServer(packageName: name)

            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func removingAServerDeletesItsDirectoryAndRegistration() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let name = uniqueName()
            let packageDirectory = path.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            try Data("binary".utf8).write(to: packageDirectory.appending(path: "server"))
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1")
            defer { manager.installedLanguageServers.removeValue(forKey: name) }

            try await manager.removeLanguageServer(packageName: name)

            #expect(FileManager.default.fileExists(atPath: packageDirectory.path) == false)
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func removingAScopedServerDecodesPercentEscapesInTheName() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let scope = "@scope-\(UUID().uuidString.prefix(8).lowercased())"
            let decodedName = "\(scope)/server"
            let packageDirectory = path.appending(path: decodedName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            manager.installedLanguageServers[decodedName] = .init(packageName: decodedName, isEnabled: true, version: "1")
            defer { manager.installedLanguageServers.removeValue(forKey: decodedName) }

            try await manager.removeLanguageServer(packageName: "\(scope)%2Fserver")

            #expect(FileManager.default.fileExists(atPath: packageDirectory.path) == false)
            #expect(manager.installedLanguageServers[decodedName] == nil)
        }
    }

    @Test
    func failedRemovalKeepsTheServerRegistered() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            let manager = makeOfflineManager(installPath: path)
            let name = uniqueName()
            let packageDirectory = path.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)
            manager.installedLanguageServers[name] = .init(packageName: name, isEnabled: true, version: "1")
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path.path(percentEncoded: false))
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path(percentEncoded: false))
                manager.installedLanguageServers.removeValue(forKey: name)
            }

            var failure: Error?
            do {
                try await manager.removeLanguageServer(packageName: name)
            } catch {
                failure = error
            }

            #expect(failure != nil)
            #expect(FileManager.default.fileExists(atPath: packageDirectory.path))
            #expect(manager.installedLanguageServers[name] != nil)
        }
    }

    @Test
    func installOperationForANpmServerListsTheNpmSteps() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: "alpha-ls", sourceID: "pkg:npm/alpha-ls@1.0.0")

            let operation = try manager.installOperation(package: item)

            #expect(operation.package.name == "alpha-ls")
            #expect(operation.steps.map(\.name) == [
                "Initialize Directory Structure",
                "Install Package Using npm",
                "Verify Installation"
            ])
        }
    }

    @Test(arguments: ["pkg:nuget/Tool@1.0.0", "pkg:gem/tool@1.0.0", "pkg:unknown/tool"])
    func installOperationRejectsServersWithoutAUsableInstaller(sourceID: String) throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: "tool", sourceID: sourceID)

            #expect(isInvalidConfiguration(caught { try manager.installOperation(package: item) }))
        }
    }

    @Test
    func startingAnOperationWithoutAnInstallMethodIsRejected() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: "tool", sourceID: "pkg:nuget/Tool@1.0.0")
            let operation = PackageManagerInstallOperation(package: item, steps: [])

            #expect(isInvalidConfiguration(caught { try manager.startInstallation(operation: operation) }))
            #expect(manager.isInstalling == false)
            #expect(manager.runningInstall == nil)
        }
    }

    @Test
    func successfulInstallRegistersTheServerEnabledAtTheInstalledVersion() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/\(name)@4.3.4")
            let gate = StepGate()
            let step = PackageManagerInstallStep(name: "Wait", confirmation: .none) { _ in
                await gate.wait()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)

            #expect(manager.isInstalling)
            try await eventually { manager.runningInstall === operation && gate.isWaiting }
            #expect(manager.installedLanguageServers[name] == nil)
            #expect(isInstallationRunning(caught { try manager.startInstallation(operation: operation) }))
            #expect(isInstallationRunning(caught { try manager.installOperation(package: item) }))

            gate.open()
            try await eventually { !manager.isInstalling && manager.runningInstall == nil }

            #expect(manager.installedLanguageServers[name] == SettingsData.InstalledLanguageServer(packageName: name, isEnabled: true, version: "4.3.4"))
            #expect(operation.error == nil)
        }
    }

    @Test
    func failedInstallLeavesTheServerUnregisteredAndNotifiesTheUser() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/\(name)@2.0.0")
            let step = PackageManagerInstallStep(name: "Fail", confirmation: .none) { _ in
                throw StepFailure()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)
            try await eventually { !manager.isInstalling && manager.runningInstall == nil }

            #expect(manager.installedLanguageServers[name] == nil)
            #expect(operation.error is StepFailure)
            try await eventually {
                NotificationManager.shared.notifications.contains { $0.title == "Could not install \(name)@2.0.0" }
            }
        }
    }

    @Test
    func cancellingAnInstallStopsItWithoutRegisteringTheServer() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/\(name)@1.0.0")
            let gate = StepGate()
            let step = PackageManagerInstallStep(name: "Sleep", confirmation: .none) { _ in
                gate.markWaiting()
                try await Task.sleep(for: .seconds(600))
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)
            try await eventually { gate.isWaiting }
            manager.cancelInstallation()

            #expect(manager.isInstalling == false)
            try await eventually { manager.runningInstall == nil }
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }
}
