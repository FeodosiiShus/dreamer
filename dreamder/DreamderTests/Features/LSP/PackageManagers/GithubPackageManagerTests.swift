import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct GithubPackageManagerTests {
    static let unsafe = "PackageManagerError.unsafeValue"
    static let initializeName = "Initialize Directory Structure"
    static let downloadName = "Download Binary Executable"
    static let decompressName = "Decompress Binary Executable"
    static let cloneName = "Clone with Git"
    static let buildName = "Install From Source"
    static let repository = "https://github.com/acme/tool"

    func releaseURL(_ file: String) throws -> URL {
        try #require(URL(string: "\(Self.repository)/releases/download/v1/\(file)"))
    }

    func binarySource() -> PackageSource {
        PackageManagerFixtures.source(
            type: .github,
            repositoryUrl: Self.repository,
            gitReference: .tag("v1")
        )
    }

    func buildSource(
        repositoryUrl: String? = GithubPackageManagerTests.repository,
        pkgName: String = "tool"
    ) -> PackageSource {
        PackageManagerFixtures.source(
            type: .sourceBuild,
            pkgName: pkgName,
            repositoryUrl: repositoryUrl,
            gitReference: .revision("abc123")
        )
    }

    func binarySteps(
        manager: GithubPackageManager,
        file: String
    ) throws -> [PackageManagerInstallStep] {
        try manager.install(method: .binaryDownload(source: binarySource(), url: releaseURL(file)))
    }

    func downloadFailure(_ error: (any Error)?) -> (url: URL, cause: NSError)? {
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
            "This step will run the following command to clone the package from source control:\n"
                + "`git clone \(Self.repository)`",
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
            let failure = thrownError { try manager.install(method: method) }
            #expect(errorKind(failure) == "PackageManagerError.invalidConfiguration")
        }
    }

    @Test
    func isInstalledChecksForGitOnlyWhenBuildingFromSource() async throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))

        let downloadMethod = InstallationMethod.binaryDownload(source: binarySource(), url: try releaseURL("tool.zip"))
        let download = manager.isInstalled(method: downloadMethod)
        let downloadShell = ScriptedProcesses()
        #expect(download.confirmation.message == nil)
        #expect(await runStep(download, shell: downloadShell).error == nil)
        #expect(downloadShell.invocations.isEmpty)

        let build = manager.isInstalled(method: .sourceBuild(source: buildSource(), command: "make"))
        let gitShell = ScriptedProcesses { _ in FakeProcessRunner.output("git version 2.45.1\n") }
        let gitMessage = "This package requires git to install. Allow Dreamder to run git commands?"
        #expect(build.confirmation.message == gitMessage)
        #expect(await runStep(build, shell: gitShell).error == nil)
        #expect(gitShell.arguments == [["git", "--version"]])
        #expect(gitShell.invocations.first?.executable == PackageManagerProgressModel.envExecutable)

        let noGit = ScriptedProcesses { _ in FakeProcessRunner.output("command not found: git\n") }
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
    func theDefaultDownloaderReportsAnUnreachableHostAsADownloadFailure() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let unreachable = try #require(URL(string: "https://127.0.0.1:1/tool.zip"))
            let steps = try manager.install(method: .binaryDownload(source: binarySource(), url: unreachable))

            let outcome = await runStep(try stepNamed(Self.downloadName, in: steps))

            let failure = try #require(downloadFailure(outcome.error))
            #expect(failure.url == unreachable)
            #expect(failure.cause.domain == NSURLErrorDomain)
        }
    }
}
