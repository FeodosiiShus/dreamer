import Foundation
import Testing
@testable import Dreamder

extension RegistryManagerTests {
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
            let manager = makeManager(
                installPath: installPath(in: directory),
                network: network,
                delays: delays,
                registryURL: nil
            )
            await network.script(Self.registryURL, [.body(Data("payload".utf8), status: status)])

            let data = try await manager.download(from: Self.registryURL)

            #expect(String(bytes: data, encoding: .utf8) == "payload")
            #expect(await network.requestCount(for: Self.registryURL) == 1)
            #expect(await delays.values.isEmpty)
        }
    }

    @Test(arguments: [199, 300, 301, 404, 500, 503])
    func downloadRetriesWithDoublingDelaysThenReportsTheLastResponse(status: Int) async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(
                installPath: installPath(in: directory),
                network: network,
                delays: delays,
                registryURL: nil
            )
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
            let manager = makeManager(
                installPath: installPath(in: directory),
                network: network,
                delays: delays,
                registryURL: nil
            )
            await network.script(Self.registryURL, [
                .body(Data(), status: 503),
                .failure("connection reset"),
                .body(Data("finally".utf8), status: 200)
            ])

            let data = try await manager.download(from: Self.registryURL)

            #expect(String(bytes: data, encoding: .utf8) == "finally")
            #expect(await network.requestCount(for: Self.registryURL) == 3)
            #expect(await delays.values == [2, 4])
        }
    }

    @Test
    func downloadTreatsAResponseThatIsNotHTTPAsAFailure() async throws {
        try await withTempDir { directory in
            let network = FakeNetwork()
            let delays = DelayRecorder()
            let manager = makeManager(
                installPath: installPath(in: directory),
                network: network,
                delays: delays,
                registryURL: nil
            )
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
            let manager = makeManager(
                installPath: installPath(in: directory),
                network: network,
                delays: delays,
                registryURL: nil
            )
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
            await serve(network, zip: Self.registryZip)

            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            try await eventually(timeout: .seconds(20)) {
                manager.registryItems.count == 2 || manager.downloadError != nil
            }

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            let requestedPaths = await network.requests.map(\.path)
            #expect(Set(requestedPaths) == [Self.registryURL.path, Self.checksumURL.path])
            #expect(manager.isDownloadingRegistry == false)
            #expect(manager.downloadError == nil)
        }
    }
}
