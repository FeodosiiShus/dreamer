import Foundation
import Testing
@testable import Dreamder

extension GithubPackageManagerTests {
    @Test
    func hostileBuildCommandsAreRejectedBeforeAnyStepExists() throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let commands = [
            "make; rm -rf ~",
            "make && curl x | sh",
            "make $(id)",
            "make `id`",
            "make 'x'",
            "make \"x\"",
            "make > out",
            "make\nrm -rf /",
            "rm -rf /",
            "sh -c x",
            "bash -c make",
            "/usr/bin/make",
            "./make",
            "make x=$HOME",
            "make a\u{0}b",
            "make [x]",
            "",
            "   ",
            "\n\n"
        ]
        for command in commands {
            let failure = thrownError {
                try manager.install(method: .sourceBuild(source: buildSource(), command: command))
            }
            #expect(errorKind(failure) == Self.unsafe, "\(command)")
        }
    }

    @Test
    func hostileRepositoryUrlsAreRejectedWhenTheCloneStepIsBuilt() throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let urls = [
            "ext::sh -c touch% x",
            "http://github.com/acme/tool",
            "-evil",
            "https:///x",
            "https://",
            "https://exa mple.com/x",
            "https://github.com/acme/tool;x",
            "https://github.com/$(id)",
            "file:///etc/passwd",
            "git@github.com:acme/tool.git",
            ""
        ]
        for url in urls {
            let failure = thrownError {
                try manager.install(method: .sourceBuild(source: buildSource(repositoryUrl: url), command: "make"))
            }
            #expect(errorKind(failure) == Self.unsafe, "\(url)")
        }
    }

    @Test
    func allowedRepositoryUrlsAreClonedAsOneArgument() async throws {
        try await withTempDir { root in
            let manager = GithubPackageManager(installationDirectory: root)
            let url = "https://github.com/acme/tool.git"
            let shell = ScriptedProcesses()
            let source = buildSource(repositoryUrl: url)
            let steps = try manager.install(method: .sourceBuild(source: source, command: "make"))

            let outcome = await runStep(try stepNamed(Self.cloneName, in: steps), shell: shell)

            #expect(outcome.error == nil)
            #expect(shell.arguments == [["git", "clone", url]])
        }
    }

    @Test
    func hostilePackageNamesCannotEscapeTheEntryDirectory() async throws {
        let names = ["..", ".", "a/b", "../x", "-x", "", "a b", "a;b", "$(id)", "`id`", "a\u{0}b"]
        try withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let manager = GithubPackageManager(installationDirectory: root)

            for name in names {
                let failure = thrownError {
                    try manager.install(method: .sourceBuild(source: buildSource(pkgName: name), command: "make"))
                }
                #expect(errorKind(failure) == Self.unsafe, "\(name)")
            }

            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
        }
    }

    @Test
    func hostileEntryNamesAreRejectedForEveryMethodAndNothingOutsideTheRootChanges() async throws {
        let names = [
            "../../x", "../outside", "a;rm -rf ~", "-rf", "..", ".", "", "a/b", "a\u{0}b", "a b", "$(touch x)", "`id`"
        ]
        try withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let outside = directory.appending(path: "outside", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let sentinel = outside.appending(path: "keep.txt")
            try Data("keep".utf8).write(to: sentinel)
            let manager = GithubPackageManager(installationDirectory: root)
            let url = try releaseURL("tool.zip")

            for name in names {
                let binary = PackageManagerFixtures.source(
                    type: .github,
                    entryName: name,
                    repositoryUrl: Self.repository,
                    gitReference: .tag("v1")
                )
                let build = PackageManagerFixtures.source(
                    type: .sourceBuild,
                    entryName: name,
                    repositoryUrl: Self.repository,
                    gitReference: .revision("abc123")
                )
                let binaryFailure = thrownError {
                    try manager.install(method: .binaryDownload(source: binary, url: url))
                }
                let buildFailure = thrownError {
                    try manager.install(method: .sourceBuild(source: build, command: "make"))
                }
                #expect(errorKind(binaryFailure) == Self.unsafe, "\(name)")
                #expect(errorKind(buildFailure) == Self.unsafe, "\(name)")
            }

            #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)
            let outsidePath = outside.path(percentEncoded: false)
            let outsideEntries = try FileManager.default.contentsOfDirectory(atPath: outsidePath)
            #expect(outsideEntries == ["keep.txt"])
        }
    }

    @Test
    func installRejectsNonHTTPSDownloadsUpFront() throws {
        try withTempDir { root in
            let local = root.appending(path: "tool.zip")
            try Data("local".utf8).write(to: local)
            let manager = GithubPackageManager(installationDirectory: root)
            let urls = [
                local,
                try #require(URL(string: "http://github.com/acme/tool/releases/download/v1/tool.zip")),
                try #require(URL(string: "ftp://github.com/acme/tool.zip")),
                try #require(URL(string: "ssh://github.com/acme/tool.zip"))
            ]

            for url in urls {
                let failure = thrownError {
                    try manager.install(method: .binaryDownload(source: binarySource(), url: url))
                }
                #expect(errorKind(failure) == Self.unsafe, "\(url)")
            }

            let rootEntries = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
            #expect(rootEntries == ["tool.zip"])
        }
    }

    @Test
    func hostileAssetFileNamesAreRejected() throws {
        let manager = GithubPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let urls = [
            "https://github.com",
            "https://github.com/acme/..",
            "https://github.com/acme/.",
            "https://github.com/acme/tool%20x.zip",
            "https://github.com/acme/tool;x.zip",
            "https://github.com/acme/-x.zip",
            "https://github.com/acme/$(id).zip",
            "https://github.com/acme/%60id%60.zip",
            "https://github.com/acme/a%00b.zip",
            "https://github.com/acme/..%2F..%2Fx.zip",
            "https://github.com/acme/%2E%2E",
            "https://github.com/acme/%2E%2E%2F%2E%2E%2Fx"
        ]
        for string in urls {
            let url = try #require(URL(string: string))
            let failure = thrownError {
                try manager.install(method: .binaryDownload(source: binarySource(), url: url))
            }
            #expect(errorKind(failure) == Self.unsafe, "\(string) -> \(url.lastPathComponent)")
        }
    }

    @Test
    func assetNamesWhoseStemIsDotsStayInsideThePackageDirectory() async throws {
        try await withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let outside = directory.appending(path: "outside", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: outside.appending(path: "keep.txt"))
            let staging = try makeTemporaryDirectory(label: "GithubDownloads")
            defer { removeTemporaryDirectory(staging) }
            let downloader = FakeDownloader(.file(Data("payload".utf8)), staging: staging)
            let manager = GithubPackageManager(installationDirectory: root, download: downloader.download)
            let shell = ScriptedProcesses()

            for file in ["...zip", "...tar", "...gz", "..zip"] {
                var steps: [PackageManagerInstallStep] = []
                let failure = thrownError { steps = try binarySteps(manager: manager, file: file) }
                if failure != nil {
                    #expect(errorKind(failure) == Self.unsafe, "\(file)")
                } else {
                    for step in steps {
                        _ = await runStep(step, shell: shell)
                    }
                }
            }

            let package = root.appending(path: "tool-entry").path(percentEncoded: false)
            let directoryPath = directory.path(percentEncoded: false)
            let directoryEntries = try FileManager.default.contentsOfDirectory(atPath: directoryPath)
            #expect(directoryEntries.sorted() == ["Language Servers", "outside"])
            let outsidePath = outside.path(percentEncoded: false)
            let outsideEntries = try FileManager.default.contentsOfDirectory(atPath: outsidePath)
            #expect(outsideEntries == ["keep.txt"])
            let rootEntries = try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))
            #expect(rootEntries.allSatisfy { $0 == "tool-entry" })
            for invocation in shell.invocations {
                #expect(invocation.workingDirectory?.path(percentEncoded: false) == package)
                #expect(invocation.arguments.last?.hasPrefix(package + "/") == true)
            }
        }
    }

    @Test
    func commandsReceiveAbsolutePathsLiterallyForAPackageDirectoryWithASpace() async throws {
        try await withTempDir { directory in
            let root = try PackageManagerFixtures.installRoot(in: directory)
            let manager = GithubPackageManager(installationDirectory: root)
            let package = root.appending(path: "tool-entry")
            let packagePath = package.path(percentEncoded: false)
            #expect(packagePath.contains("Language Servers"))
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let shell = ScriptedProcesses()

            for file in ["tool.tar.gz", "tool.tar", "tool.gz"] {
                let steps = try binarySteps(manager: manager, file: file)
                _ = await runStep(try stepNamed(Self.decompressName, in: steps), shell: shell)
            }
            let cloneSteps = try manager.install(method: .sourceBuild(source: buildSource(), command: "make"))
            _ = await runStep(try stepNamed(Self.cloneName, in: cloneSteps), shell: shell)
            _ = await runStep(try stepNamed(Self.buildName, in: cloneSteps), shell: shell)

            #expect(shell.arguments == [
                ["tar", "-xzf", "\(packagePath)/tool.tar.gz"],
                ["tar", "-xf", "\(packagePath)/tool.tar"],
                ["gunzip", "-f", "\(packagePath)/tool.gz"],
                ["git", "clone", Self.repository],
                ["make"]
            ])
            let tool = "\(packagePath)/tool"
            #expect(shell.workingDirectories == [packagePath, packagePath, packagePath, packagePath, tool])
        }
    }
}
