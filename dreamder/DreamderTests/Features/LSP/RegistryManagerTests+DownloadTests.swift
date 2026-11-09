import Foundation
import Testing
@testable import Dreamder

extension RegistryManagerTests {
    @Test
    func downloadReplacesTheStaleRegistryAndStoresTheChecksums() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await serve(network, zip: Self.registryZip)
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            manager.handleUpdateError(RegistryManagerError.failedToSaveRegistryCache)

            await manager.downloadRegistryItems()

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            #expect(manager.downloadError == nil)
            let registryFile = path.appending(path: "registry.json")
            let attributes = try FileManager.default.attributesOfItem(
                atPath: registryFile.path(percentEncoded: false)
            )
            let modified = try #require(attributes[.modificationDate] as? Date)
            #expect(abs(modified.timeIntervalSinceNow) < 3600)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.registryJSON)
            let storedChecksums = try Data(contentsOf: path.appending(path: "checksums.txt"))
            #expect(storedChecksums == Self.checksumBody(for: Self.registryZip))
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "temp.zip").path) == false)
            #expect(stagingExists(path) == false)
            #expect(await network.requestCount(for: Self.registryURL) == 1)
            #expect(await network.requestCount(for: Self.checksumURL) == 1)
        }
    }

    @Test
    func aLeftoverStagingDirectoryIsWipedBeforeInstalling() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let staging = path.appending(path: RegistryManager.stagingDirectoryName, directoryHint: .isDirectory)
            let extracted = staging.appending(path: "extracted", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            try Data("junk".utf8).write(to: staging.appending(path: "registry.zip"))
            try Data("junk".utf8).write(to: staging.appending(path: "junk.txt"))
            try Data("[]".utf8).write(to: extracted.appending(path: "registry.json"))
            let network = FakeNetwork()
            await serve(network, zip: Self.registryZip)
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            #expect(manager.downloadError == nil)
            #expect(stagingExists(path) == false)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.registryJSON)
        }
    }

    @Test
    func aChecksumMismatchRejectsTheDownloadBeforeTouchingTheDisk() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await serve(network, zip: Self.registryZip, checksums: Self.checksumBody(for: Data("another archive".utf8)))
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            let before = try snapshot(of: directory)

            await manager.downloadRegistryItems()

            #expect(checksumFailure(manager.downloadError) == "mismatch:registry.json.zip")
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
            #expect(stagingExists(path) == false)
            #expect(try snapshot(of: directory) == before)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.isDownloadingRegistry == false)
        }
    }

    @Test(arguments: [
        "",
        "{hash}  registry.json\n",
        "garbage\nnot a checksum line\n",
        "abc123  registry.json.zip\n",
        "{hash}\n"
    ])
    func aChecksumFileWithoutAnEntryForTheArchiveIsRejected(template: String) async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            let body = template.replacingOccurrences(of: "{hash}", with: Self.sha256Hex(Self.registryZip))
            await serve(network, zip: Self.registryZip, checksums: Data(body.utf8))
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(checksumFailure(manager.downloadError) == "missing:registry.json.zip")
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
            #expect(stagingExists(path) == false)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.isDownloadingRegistry == false)
        }
    }

    @Test(arguments: [
        "{hash}  registry.json.zip\n",
        "{HASH}  registry.json.zip\n",
        "{hash} *registry.json.zip\n",
        "{HASH} *registry.json.zip",
        "junk line\n{hash}  registry.json\n{hash}  registry.json.zip\r\n"
    ])
    func publishedChecksumsInEveryAcceptedNotationVerifyTheArchive(template: String) async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            let hash = Self.sha256Hex(Self.registryZip)
            let body = Data(
                template
                    .replacingOccurrences(of: "{hash}", with: hash)
                    .replacingOccurrences(of: "{HASH}", with: hash.uppercased())
                    .utf8
            )
            await serve(network, zip: Self.registryZip, checksums: body)
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(manager.downloadError == nil)
            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            #expect(try Data(contentsOf: path.appending(path: "checksums.txt")) == body)
            #expect(stagingExists(path) == false)
        }
    }

    @Test
    func onlyTheRegistryFileIsTakenFromTheArchive() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let installed = path.appending(path: "other-ls", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
            try Data("original".utf8).write(to: installed.appending(path: "server"))
            let zip = StoredZip.make(entries: [
                ("registry.json", Self.registryJSON),
                ("other-ls/server", "evil"),
                ("checksums.txt", "evil"),
                ("evil.txt", "evil")
            ])
            let network = FakeNetwork()
            await serve(network, zip: zip)
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(manager.downloadError == nil)
            #expect(manager.registryItems.map(\.name) == ["alpha-ls", "gamma-ls"])
            let entries = try FileManager.default.contentsOfDirectory(atPath: path.path(percentEncoded: false))
            #expect(Set(entries) == ["checksums.txt", "other-ls", "registry.json"])
            #expect(try String(contentsOf: installed.appending(path: "server"), encoding: .utf8) == "original")
            #expect(try Data(contentsOf: path.appending(path: "checksums.txt")) == Self.checksumBody(for: zip))
            #expect(stagingExists(path) == false)
        }
    }

    @Test(arguments: ["../escape.txt", "../../escape.txt", "../../../escape.txt"])
    func anArchiveEntryEscapingTheExtractionFolderIsRejected(entryName: String) async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let zip = StoredZip.make(entries: [("registry.json", Self.registryJSON), (entryName, "evil")])
            let network = FakeNetwork()
            await serve(network, zip: zip)
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())
            let before = try snapshot(of: directory)

            await manager.downloadRegistryItems()

            #expect(isWriteFailure(manager.downloadError))
            #expect(try snapshot(of: directory) == before)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
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
            let registryBody = StoredZip.make(entries: [("registry.json", Self.registryJSON)])
            await network.script(Self.registryURL, [.body(registryBody, status: 200)])
            await network.script(Self.checksumURL, [.body(Self.checksumBody(for: Self.registryZip), status: 200)])
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
            await network.script(Self.checksumURL, [.body(Self.checksumBody(for: Self.registryZip), status: 200)])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(invalidResponseStatus(lastRetryError(of: manager.downloadError, url: Self.registryURL)) == 500)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.isDownloadingRegistry == false)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
            #expect(stagingExists(path) == false)
        }
    }

    @Test
    func failedChecksumDownloadDiscardsTheDownloadedRegistry() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            let registryBody = StoredZip.make(entries: [("registry.json", Self.registryJSON)])
            await network.script(Self.registryURL, [.body(registryBody, status: 200)])
            await network.script(Self.checksumURL, [.failure("no route to host")])
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(lastRetryError(of: manager.downloadError, url: Self.checksumURL) != nil)
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(stagingExists(path) == false)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
        }
    }

    @Test
    func corruptArchiveIsReportedAsAWriteFailure() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            let corrupt = Data("this is not a zip archive".utf8)
            await serve(network, zip: corrupt)
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(isWriteFailure(manager.downloadError))
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(manager.isDownloadingRegistry == false)
            #expect(stagingExists(path) == false)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
        }
    }

    @Test
    func archiveWithoutARegistryFileFailsToPopulateTheCache() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await serve(network, zip: StoredZip.make(entries: [("other.json", "[]")]))
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(isMissingRegistryCache(manager.downloadError))
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(try String(contentsOf: path.appending(path: "registry.json"), encoding: .utf8) == Self.staleJSON)
            #expect(FileManager.default.fileExists(atPath: path.appending(path: "checksums.txt").path) == false)
            #expect(stagingExists(path) == false)
        }
    }

    @Test
    func archiveWithUnreadableRegistryFailsToPopulateTheCache() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let network = FakeNetwork()
            await serve(network, zip: StoredZip.make(entries: [("registry.json", "{ broken")]))
            let manager = makeManager(installPath: path, network: network, delays: DelayRecorder())

            await manager.downloadRegistryItems()

            #expect(isMissingRegistryCache(manager.downloadError))
            #expect(manager.registryItems.map(\.name) == ["stale-ls"])
            #expect(stagingExists(path) == false)
        }
    }

    @Test
    func firstStartWithAnUnwritableInstallLocationReportsAWriteFailure() async throws {
        try await withTempDir { directory in
            let blocker = directory.appending(path: "blocker")
            try Data("a file, not a folder".utf8).write(to: blocker)
            let network = FakeNetwork()
            await serve(network, zip: Self.registryZip)

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
}
