import Foundation
import Testing
@testable import Dreamder

extension CargoPackageManagerTests {
    @Test
    func hostileEntryNamesAreRejectedBeforeAnyStepExists() {
        for name in Self.hostileNames {
            let source = PackageManagerFixtures.source(type: .cargo, entryName: name)
            #expect(unsafeInstall(source) == "PackageManagerError.unsafeValue", "\(name)")
        }
    }

    @Test
    func hostilePackageNamesAndVersionsAreRejected() {
        for value in Self.hostileArguments {
            let name = PackageManagerFixtures.source(type: .cargo, pkgName: value)
            #expect(unsafeInstall(name) == "PackageManagerError.unsafeValue", "name \(value)")
            let version = PackageManagerFixtures.source(type: .cargo, version: value)
            #expect(unsafeInstall(version) == "PackageManagerError.unsafeValue", "version \(value)")
        }
    }

    @Test
    func hostileFeaturesAreRejected() {
        for value in Self.hostileArguments {
            let source = PackageManagerFixtures.source(type: .cargo, options: ["features": value])
            #expect(unsafeInstall(source) == "PackageManagerError.unsafeValue", "features \(value)")
        }
    }

    @Test
    func hostileRepositoryUrlsAreRejected() {
        let urls = [
            "ext::sh -c touch% x", "http://github.com/acme/tool", "-evil", "https:///x", "https://a b/x",
            "file:///etc/passwd", "https://github.com/a;b", "", "https://"
        ]
        for url in urls {
            let tag = PackageManagerFixtures.source(type: .cargo, repositoryUrl: url, gitReference: .tag("v1"))
            #expect(unsafeInstall(tag) == "PackageManagerError.unsafeValue", "url \(url)")
            let revision = PackageManagerFixtures.source(
                type: .cargo, repositoryUrl: url, gitReference: .revision("abc")
            )
            #expect(unsafeInstall(revision) == "PackageManagerError.unsafeValue", "url \(url)")
        }
    }

    @Test
    func hostileGitReferencesAreRejected() {
        for value in Self.hostileArguments {
            let tag = PackageManagerFixtures.source(
                type: .cargo, repositoryUrl: Self.repository, gitReference: .tag(value)
            )
            #expect(unsafeInstall(tag) == "PackageManagerError.unsafeValue", "tag \(value)")
            let revision = PackageManagerFixtures.source(
                type: .cargo, repositoryUrl: Self.repository, gitReference: .revision(value)
            )
            #expect(unsafeInstall(revision) == "PackageManagerError.unsafeValue", "revision \(value)")
        }
    }

    @Test
    func theBuilderItselfThrowsForHostileValuesWithoutRunningAnything() throws {
        let manager = CargoPackageManager(installationDirectory: URL(filePath: "/tmp/ls"))
        let package = URL(filePath: "/tmp/ls/tool")
        let source = PackageManagerFixtures.source(type: .cargo, version: "1;touch x")
        let shell = ScriptedProcesses()

        let failure = thrownError { try manager.runCargoInstall(source, in: package) }
        #expect(errorKind(failure) == "PackageManagerError.unsafeValue")
        #expect(shell.invocations.isEmpty)
    }

    @Test
    func hostileEntryNamesNeverTouchTheFileSystemOutsideTheInstallRoot() async throws {
        try await withTempDir { base in
            let root = base.appending(path: "Language Servers", directoryHint: .isDirectory)
            let sibling = base.appending(path: "sibling", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            let sentinel = sibling.appending(path: "keep.txt")
            try Data("keep".utf8).write(to: sentinel)
            let shell = ScriptedProcesses()

            for name in ["../sibling", "..", ".", "../sibling/keep.txt"] {
                let source = PackageManagerFixtures.source(type: .cargo, entryName: name)
                #expect(unsafeInstall(source, root: root) == "PackageManagerError.unsafeValue", "\(name)")
            }

            #expect(shell.invocations.isEmpty)
            #expect(FileManager.default.fileExists(atPath: sentinel.path(percentEncoded: false)))
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false)).isEmpty)

            let steps = try CargoPackageManager(installationDirectory: root)
                .install(method: .standardPackage(source: PackageManagerFixtures.source(type: .cargo)))
            let outcome = await runStep(try stepNamed(Self.initializeName, in: steps), shell: shell)
            #expect(outcome.error == nil)
            #expect(FileManager.default.fileExists(atPath: sentinel.path(percentEncoded: false)))
        }
    }
}
