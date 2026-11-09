import Testing
import Foundation
@testable import Dreamder

extension PackageSourceParserTests {
    @Test
    func installMethodDispatchesOnTheSourceScheme() throws {
        let cargo = try #require(try makeItem(id: "pkg:cargo/ruff@0.1.0").installMethod)
        #expect(cargo.packageManagerType == .cargo)
        #expect(cargo.packageDescription == "ruff@0.1.0")

        let golang = try #require(try makeItem(id: "pkg:golang/github.com/a/b@v1").installMethod)
        #expect(golang.packageManagerType == .golang)
        #expect(golang.packageDescription == "github.com/a/b@v1")

        #expect(try makeItem(id: "pkg:generic/tool@1").installMethod == nil)
        #expect(try makeItem(id: "").installMethod == nil)
    }

    @Test
    func githubWithoutVersionTracksMain() throws {
        let item = try makeItem(id: "pkg:github/acme/tool", sourceExtras: #", "build": { "run": "make" }"#)
        let method = PackageSourceParser.parseGithubPackage(item)
        #expect(method == .sourceBuild(
            source: PackageSource(
                sourceId: "pkg:github/acme/tool",
                type: .sourceBuild,
                pkgName: "tool",
                entryName: "entry",
                version: "main",
                repositoryUrl: "https://github.com/acme/tool",
                gitReference: .tag("main"),
                options: [:]
            ),
            command: "make"
        ))
    }

    @Test
    func githubTrailingAtSignMeansNoVersion() throws {
        let item = try makeItem(id: "pkg:github/acme/tool@", sourceExtras: #", "build": { "run": "make" }"#)
        #expect(PackageSourceParser.parseGithubPackage(item).version == "main")
    }

    @Test
    func githubRequiresOwnerAndRepository() throws {
        let build = #", "build": { "run": "make" }"#
        #expect(
            PackageSourceParser.parseGithubPackage(
                try makeItem(id: "pkg:github/acme@v1", sourceExtras: build)
            ) == .unknown
        )
        #expect(
            PackageSourceParser.parseGithubPackage(
                try makeItem(id: "pkg:github/@v1", sourceExtras: build)
            ) == .unknown
        )
        #expect(
            PackageSourceParser.parseGithubPackage(
                try makeItem(id: "pkg:gitlab/acme/tool@v1", sourceExtras: build)
            ) == .unknown
        )
    }

    @Test
    func githubOnlyLowercaseFortyHexVersionsAreRevisions() throws {
        let build = #", "build": { "run": "make" }"#
        let upper = String(repeating: "F", count: 40)
        let cases: [(String, PackageSource.GitReference)] = [
            (Self.commit, .revision(Self.commit)),
            (upper, .tag(upper)),
            ("v1.0.0", .tag("v1.0.0"))
        ]
        for (version, reference) in cases {
            let method = PackageSourceParser.parseGithubPackage(
                try makeItem(id: "pkg:github/acme/tool@\(version)", sourceExtras: build)
            )
            guard case .sourceBuild(let source, _) = method else {
                Issue.record("expected a source build, got \(method)")
                continue
            }
            #expect(source.gitReference == reference)
        }
    }

    @Test
    func githubSourceBuildPicksTheDarwinBuildFromAList() throws {
        let builds = #"""
        , "build": [
          { "target": "linux_x64", "run": "make linux" },
          { "run": "make untargeted" },
          { "target": "darwin", "run": "make mac" }
        ]
        """#
        let method = PackageSourceParser.parseGithubPackage(
            try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: builds)
        )
        guard case .sourceBuild(_, let command) = method else {
            Issue.record("expected a source build, got \(method)")
            return
        }
        #expect(command == "make mac")
    }

    @Test
    func githubSourceBuildWithoutDarwinTargetOrWithoutBuildIsUnknown() throws {
        let linuxOnly = #", "build": [{ "target": "linux_x64", "run": "make" }]"#
        #expect(
            PackageSourceParser.parseGithubPackage(
                try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: linuxOnly)
            ) == .unknown
        )
        #expect(PackageSourceParser.parseGithubPackage(try makeItem(id: "pkg:github/acme/tool@v1")) == .unknown)
    }

    @Test
    func githubAssetFileNameTemplateIsRenderedAgainstTheRegistryItem() throws {
        let asset = #"""
        , "asset": { "target": "darwin", "file": "{{ name }}_{{ version | strip_prefix \"v\" }}_darwin.tar.gz" }
        """#
        let item = try makeItem(name: "protolint", id: "pkg:github/yoheimuta/protolint@v0.53.0", sourceExtras: asset)
        let method = PackageSourceParser.parseGithubPackage(item)
        let expectedURL = try #require(URL(
            string: "https://github.com/yoheimuta/protolint/releases/download/v0.53.0/protolint_0.53.0_darwin.tar.gz"
        ))
        #expect(method == .binaryDownload(
            source: PackageSource(
                sourceId: "pkg:github/yoheimuta/protolint@v0.53.0",
                type: .github,
                pkgName: "protolint",
                entryName: "protolint",
                version: "v0.53.0",
                repositoryUrl: "https://github.com/yoheimuta/protolint",
                gitReference: .tag("v0.53.0"),
                options: [:]
            ),
            url: expectedURL
        ))
    }

    @Test
    func githubBinaryDownloadFailsForUnresolvableTemplatesAndMissingFiles() throws {
        let id = "pkg:github/acme/tool@v1.0.0"
        let unknownVariable = #", "asset": { "target": "darwin", "file": "tool_{{ nope }}.zip" }"#
        let linuxOnly = #", "asset": { "target": "linux_x64", "file": "tool.zip" }"#
        let emptyFile = #", "asset": { "target": "darwin", "file": "" }"#
        let noFile = #", "asset": { "target": "darwin" }"#
        for extras in [unknownVariable, linuxOnly, emptyFile, noFile] {
            #expect(PackageSourceParser.parseGithubPackage(try makeItem(id: id, sourceExtras: extras)) == .unknown)
        }
    }

    @Test
    func githubBinaryDownloadNeedsATagNotACommit() throws {
        let asset = #", "asset": { "target": "darwin", "file": "tool.zip" }"#
        let item = try makeItem(id: "pkg:github/acme/tool@\(Self.commit)", sourceExtras: asset)
        #expect(PackageSourceParser.parseGithubPackage(item) == .unknown)
    }
}
