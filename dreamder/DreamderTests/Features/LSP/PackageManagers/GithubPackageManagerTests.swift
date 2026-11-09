import Foundation
import Synchronization
import Testing
@testable import Dreamder

nonisolated final class FakeDownloader: Sendable {
    enum Behavior: Sendable {
        case file(Data)
        case status(Int)
        case nonHTTP
        case fail
        case missingTemporaryFile
    }

    struct Failure: Error {}

    private let behavior: Behavior
    private let staging: URL
    private let log = Mutex<[URLRequest]>([])

    init(_ behavior: Behavior, staging: URL) {
        self.behavior = behavior
        self.staging = staging
    }

    var requests: [URLRequest] {
        log.withLock { $0 }
    }

    var download: PackageFileDownload {
        { [self] request in try await self.respond(to: request) }
    }

    private func respond(to request: URLRequest) async throws -> (URL, URLResponse) {
        log.withLock { $0.append(request) }
        let url = request.url ?? staging
        switch behavior {
        case .file(let data):
            return (try stage(data), try httpResponse(url: url, status: 200))
        case .status(let status):
            return (try stage(Data("error body".utf8)), try httpResponse(url: url, status: status))
        case .nonHTTP:
            let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (try stage(Data()), response)
        case .fail:
            throw Failure()
        case .missingTemporaryFile:
            return (staging.appending(path: "never-written"), try httpResponse(url: url, status: 200))
        }
    }

    private func stage(_ data: Data) throws -> URL {
        let file = staging.appending(path: UUID().uuidString)
        try data.write(to: file)
        return file
    }

    private func httpResponse(url: URL, status: Int) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw Failure()
        }
        return response
    }
}

@MainActor
@Suite(.uiGate)
struct GithubPackageManagerTests {
    private static let initializeName = "Initialize Directory Structure"
    private static let downloadName = "Download Binary Executable"
    private static let decompressName = "Decompress Binary Executable"
    private static let cloneName = "Clone with Git"
    private static let buildName = "Install From Source"
    private static let repository = "https://github.com/acme/tool"

    private func releaseURL(_ file: String) throws -> URL {
        try #require(URL(string: "\(Self.repository)/releases/download/v1/\(file)"))
    }

    private func binarySource() -> PackageSource {
        PackageManagerFixtures.source(
            type: .github,
            repositoryUrl: Self.repository,
            gitReference: .tag("v1")
        )
    }

    private func buildSource(repositoryUrl: String? = GithubPackageManagerTests.repository) -> PackageSource {
        PackageManagerFixtures.source(
            type: .sourceBuild,
            repositoryUrl: repositoryUrl,
            gitReference: .revision("abc123")
        )
    }

    private func binarySteps(
        manager: GithubPackageManager,
        file: String
    ) throws -> [PackageManagerInstallStep] {
        try manager.install(method: .binaryDownload(source: binarySource(), url: releaseURL(file)))
    }

    private func downloadFailure(_ error: (any Error)?) -> (url: URL, cause: NSError)? {
        guard case .downloadFailed(let url, let cause) = error as? RegistryManagerError else { return nil }
        return (url, cause as NSError)
    }

    @Test
    func binaryDownloadsListDownloadAndDecompressSteps() throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let steps = try binarySteps(manager: manager, file: "tool.zip")

        #expect(steps.map { $0.name } == [Self.initializeName, Self.downloadName, Self.decompressName])
        #expect(steps.map { $0.confirmation.message } == [nil, nil, nil])
    }

    @Test
    func sourceBuildsListCloneAndBuildStepsThatAskForConfirmation() throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make install"))

        #expect(steps.map { $0.name } == [Self.initializeName, Self.cloneName, Self.buildName])
        #expect(steps.map { $0.confirmation.message } == [
            nil,
            "This step will run the following command to clone the package from source control:\n`git clone \(Self.repository)`",
            "This step will run the following to finish installing:\n`make install`"
        ])
    }

    @Test
    func installRejectsStandardPackagesUnknownMethodsAndSourceBuildsWithoutARepository() {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let rejected: [InstallationMethod] = [
            .unknown,
            .standardPackage(source: binarySource()),
            .sourceBuild(source: buildSource(repositoryUrl: nil), command: "make")
        ]
        for method in rejected {
            #expect(errorKind(thrownError { try manager.install(method: method) }) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func isInstalledChecksForGitOnlyWhenBuildingFromSource() async throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let download = manager.isInstalled(method: .binaryDownload(source: binarySource(), url: try releaseURL("tool.zip")))
        let downloadShell = ScriptedShell()
        #expect(download.confirmation.message == nil)
        #expect(await runStep(download, shell: downloadShell).error == nil)
        #expect(downloadShell.commands.isEmpty)

        let build = manager.isInstalled(method: .sourceBuild(source: buildSource(), command: "make"))
        let gitShell = ScriptedShell { _ in FakeProcessRunner.output("git version 2.45.1\n") }
        #expect(build.confirmation.message == "This package requires git to install. Allow Dreamder to run git commands?")
        #expect(await runStep(build, shell: gitShell).error == nil)
        #expect(gitShell.commands == ["git --version"])

        let noGit = ScriptedShell { _ in FakeProcessRunner.output("command not found: git\n") }
        #expect(errorKind(await runStep(build, shell: noGit).error) == "PackageManagerError.packageManagerNotInstalled")

        for method in [InstallationMethod.unknown, .standardPackage(source: binarySource())] {
            let outcome = await runStep(manager.isInstalled(method: method))
            #expect(errorKind(outcome.error) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func binaryPathIsTheBinDirectoryOfThePackage() {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/Language Servers"))
        #expect(manager.getBinaryPath(for: "tool") == "/tmp/Language Servers/tool/bin")
    }

    @Test
    func initializeCreatesTheEntryDirectory() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")

            let outcome = await runStep(manager.initialize(in: package))

            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: package.path(percentEncoded: false)))
        }
    }

    @Test
    func initializeReportsWhyTheDirectoryCouldNotBeCreated() async throws {
        try await withTempDir { root in
            let blocker = root.appending(path: "blocker")
            try Data("file".utf8).write(to: blocker)
            let manager = GithubPackageManager(installationDirectory: root)

            let outcome = await runStep(manager.initialize(in: blocker.appending(path: "child")))

            #expect(errorKind(outcome.error) == "PackageManagerError.initializationFailed")
            #expect(initializationFailureMessage(outcome.error)?.isEmpty == false)
        }
    }

    @Test
    func downloadMovesTheAssetIntoTheEntryDirectory() async throws {
        try await withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let staging = try makeTemporaryDirectory(label: "GithubDownloads")
            defer { removeTemporaryDirectory(staging) }
            let downloader = FakeDownloader(.file(Data("payload".utf8)), staging: staging)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let url = try releaseURL("tool.zip")
            let steps = try binarySteps(manager: manager, file: "tool.zip")
            _ = await runStep(try stepNamed(Self.initializeName, in: steps))

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            #expect(outcome.error == nil)
            #expect(outcome.statuses == ["Downloading \(url)"])
            let stored = try Data(contentsOf: root.appending(path: "tool-entry/tool.zip"))
            #expect(stored == Data("payload".utf8))
            let request = try #require(downloader.requests.first)
            #expect(downloader.requests.count == 1)
            #expect(request.url == url)
            #expect(request.timeoutInterval == 120)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
    }

    @Test
    func downloadReplacesAnEarlierDownloadOfTheSameFile() async throws {
        try await withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let staging = try makeTemporaryDirectory(label: "GithubDownloads")
            defer { removeTemporaryDirectory(staging) }
            let downloader = FakeDownloader(.file(Data("new".utf8)), staging: staging)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let steps = try binarySteps(manager: manager, file: "tool.zip")
            _ = await runStep(try stepNamed(Self.initializeName, in: steps))
            let target = root.appending(path: "tool-entry/tool.zip")
            try Data("old".utf8).write(to: target)

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            #expect(outcome.error == nil)
            #expect(try Data(contentsOf: target) == Data("new".utf8))
        }
    }

    @Test
    func downloadReportsHTTPErrorStatuses() async throws {
        try await withTempDir { root in
            let downloader = FakeDownloader(.status(404), staging: root)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let steps = try binarySteps(manager: manager, file: "tool.zip")

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            let failure = try #require(downloadFailure(outcome.error))
            #expect(failure.url == (try releaseURL("tool.zip")))
            #expect(failure.cause.domain == "HTTP error")
            #expect(failure.cause.code == 404)
        }
    }

    @Test
    func downloadReportsResponsesThatAreNotHTTP() async throws {
        try await withTempDir { root in
            let downloader = FakeDownloader(.nonHTTP, staging: root)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let steps = try binarySteps(manager: manager, file: "tool.zip")

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            let failure = try #require(downloadFailure(outcome.error))
            #expect(failure.cause.domain == "HTTP error")
            #expect(failure.cause.code == -1)
        }
    }

    @Test
    func downloadWrapsTransportErrors() async throws {
        try await withTempDir { root in
            let downloader = FakeDownloader(.fail, staging: root)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let steps = try binarySteps(manager: manager, file: "tool.zip")

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            let failure = try #require(downloadFailure(outcome.error))
            #expect(failure.url == (try releaseURL("tool.zip")))
            #expect(failure.cause.domain == (FakeDownloader.Failure() as NSError).domain)
        }
    }

    @Test
    func downloadWrapsFailuresToStoreTheFile() async throws {
        try await withTempDir { root in
            let downloader = FakeDownloader(.missingTemporaryFile, staging: root)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let steps = try binarySteps(manager: manager, file: "tool.zip")

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            #expect(errorKind(outcome.error) == "RegistryManagerError.downloadFailed")
        }
    }

    @Test
    func theLiveDownloaderRejectsNonHTTPResources() async throws {
        try await withTempDir { root in
            let local = root.appending(path: "tool.zip")
            try Data("local".utf8).write(to: local)
            let manager = GithubPackageManager(installationDirectory: root)
            let steps = try manager.install(method: .binaryDownload(source: binarySource(), url: local))

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            #expect(errorKind(outcome.error) == "RegistryManagerError.downloadFailed")
        }
    }

    @Test
    func decompressUnzipsArchivesAndMakesTheBinaryExecutable() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let archive = StoredZip.make(entries: [(name: "tool", contents: "#!/bin/sh\n")])
            try archive.write(to: package.appending(path: "tool.zip"))
            let shell = ScriptedShell()

            let steps = try binarySteps(manager: manager, file: "tool.zip")
            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(outcome.statuses == ["Decompressing tool.zip", "Decompressed to '\(package.path(percentEncoded: false))'"])
            #expect(shell.commands.isEmpty)
            let binary = package.appending(path: "tool")
            #expect(try String(contentsOf: binary, encoding: .utf8) == "#!/bin/sh\n")
            #expect(isExecutable(binary))
            #expect(!FileManager.default.fileExists(atPath: package.appending(path: "tool.zip").path(percentEncoded: false)))
        }
    }

    @Test
    func decompressFailsForCorruptZipArchives() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("not a zip".utf8).write(to: package.appending(path: "tool.zip"))
            let steps = try binarySteps(manager: manager, file: "tool.zip")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps))

            #expect(outcome.error != nil)
        }
    }

    @Test
    func decompressUsesTheMatchingCommandLineTool() async throws {
        let cases: [(file: String, command: String)] = [
            ("tool.tar.gz", "tar -xzf"),
            ("tool.tar", "tar -xf"),
            ("tool.gz", "gunzip -f")
        ]
        for (file, command) in cases {
            try await withTempDir { directory in
                let root = try PackageManagerFixtures.installRoot(in: directory)
                let manager = GithubPackageManager(installationDirectory: root)
                let package = root.appending(path: "tool-entry")
                try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
                let shell = ScriptedShell()
                let steps = try binarySteps(manager: manager, file: file)

                let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

                #expect(outcome.error == nil, "\(file)")
                let packagePath = package.path(percentEncoded: false)
                #expect(shell.commands == ["cd \"\(packagePath)\" && \(command) \"\(packagePath)/\(file)\""], "\(file)")
            }
        }
    }

    @Test
    func gunzipOutputBecomesExecutable() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let binary = package.appending(path: "tool")
            let shell = ScriptedShell { command in
                if command.contains("gunzip") {
                    try Data("binary".utf8).write(to: binary)
                }
                return FakeProcessRunner.output("")
            }
            let steps = try binarySteps(manager: manager, file: "tool.gz")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(isExecutable(binary))
        }
    }

    @Test
    func decompressSurfacesExtractionFailures() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedShell { _ in ScriptedShell.failing(2) }
            let steps = try binarySteps(manager: manager, file: "tool.tar.gz")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(errorKind(outcome.error) == "ShellClientError.taskTerminated(code: 2)")
        }
    }

    @Test
    func decompressLeavesPlainBinariesExecutable() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let binary = package.appending(path: "tool")
            try Data("binary".utf8).write(to: binary)
            let shell = ScriptedShell()
            let steps = try binarySteps(manager: manager, file: "tool")

            let outcome = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.commands.isEmpty)
            #expect(isExecutable(binary))
        }
    }

    @Test
    func cloneRunsGitInsideTheEntryDirectory() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedShell()
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make"))

            let outcome = await runStep(try stepNamed(Self.cloneName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(root.appending(path: "tool-entry").path(percentEncoded: false))\" && git clone \(Self.repository)"])
        }
    }

    @Test
    func sourceBuildRunsTheRegistryCommandInsideTheClone() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedShell()
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make install"))

            let outcome = await runStep(try stepNamed(Self.buildName, in: steps), shell: shell)

            let clone = root.appending(path: "tool-entry/tool").path(percentEncoded: false)
            #expect(outcome.error == nil)
            #expect(shell.commands == ["cd \"\(clone)\" && make install"])
        }
    }

    @Test
    func sourceBuildFailuresAreReportedAsInstallationFailures() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let shell = ScriptedShell { _ in ScriptedShell.failing(2) }
            let steps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make"))

            let outcome = await runStep(try stepNamed(Self.buildName, in: steps), shell: shell)

            #expect(installationFailureMessage(outcome.error) == "Source build failed.")
        }
    }
}
