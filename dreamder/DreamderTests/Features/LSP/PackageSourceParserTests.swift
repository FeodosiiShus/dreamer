import Testing
import Foundation
@testable import Dreamder

@Suite
struct PackageSourceParserTests {
    private static let commit = "0123456789abcdef0123456789abcdef01234567"

    private func makeItem(name: String = "entry", id: String, sourceExtras: String = "") throws -> RegistryItem {
        let json = """
        {
          "name": "\(name)",
          "description": "d",
          "homepage": "https://example.com",
          "licenses": [],
          "languages": [],
          "categories": [],
          "source": { "id": "\(id)"\(sourceExtras) }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RegistryItem.self, from: Data(json.utf8))
    }

    private func standardSource(
        _ method: InstallationMethod,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> PackageSource {
        guard case .standardPackage(let source) = method else {
            Issue.record("expected a standard package, got \(method)", sourceLocation: sourceLocation)
            throw StandardPackageExpected()
        }
        return source
    }

    private struct StandardPackageExpected: Error {}

    @Test
    func cargoParsesNameAndVersion() throws {
        let item = try makeItem(name: "ruff-lsp", id: "pkg:cargo/ruff@0.1.0")
        let method = PackageSourceParser.parseCargoPackage(item)
        #expect(method == .standardPackage(source: PackageSource(
            sourceId: "pkg:cargo/ruff@0.1.0",
            type: .cargo,
            pkgName: "ruff",
            entryName: "ruff-lsp",
            version: "0.1.0",
            options: ["buildTool": "cargo"]
        )))
    }

    @Test
    func cargoWithoutVersionDefaultsToLatest() throws {
        for id in ["pkg:cargo/ruff", "pkg:cargo/ruff@"] {
            let source = try standardSource(PackageSourceParser.parseCargoPackage(makeItem(id: id)))
            #expect(source.pkgName == "ruff")
            #expect(source.version == "latest")
        }
    }

    @Test
    func cargoKeepsOnlyTheFirstAtSignAsTheVersionSeparator() throws {
        let source = try standardSource(PackageSourceParser.parseCargoPackage(makeItem(id: "pkg:cargo/tool@1.0@beta")))
        #expect(source.pkgName == "tool")
        #expect(source.version == "1.0@beta")
    }

    @Test
    func cargoQualifiersBecomeOptionsAfterPercentDecoding() throws {
        let item = try makeItem(id: "pkg:cargo/ast-grep@0.3.0?features=a%2Cb&locked=true")
        let source = try standardSource(PackageSourceParser.parseCargoPackage(item))
        #expect(source.sourceId == "pkg:cargo/ast-grep@0.3.0?features=a,b&locked=true")
        #expect(source.options == ["buildTool": "cargo", "features": "a,b", "locked": "true"])
        #expect(source.repositoryUrl == nil)
        #expect(source.gitReference == nil)
    }

    @Test
    func cargoQualifierValuesMayContainEqualsSigns() throws {
        let source = try standardSource(PackageSourceParser.parseCargoPackage(makeItem(id: "pkg:cargo/tool@1?a=b=c")))
        #expect(source.options["a"] == "b=c")
    }

    @Test
    func cargoIgnoresQualifiersWithoutAValue() throws {
        let item = try makeItem(id: "pkg:cargo/tool@1?features=&flag&&x=1")
        let source = try standardSource(PackageSourceParser.parseCargoPackage(item))
        #expect(source.options == ["buildTool": "cargo", "x": "1"])
    }

    @Test
    func cargoRepositoryUrlDefaultsToATagForVersions() throws {
        let item = try makeItem(id: "pkg:cargo/hello@1.2.3?repository_url=https://github.com/acme/hello")
        let source = try standardSource(PackageSourceParser.parseCargoPackage(item))
        #expect(source.repositoryUrl == "https://github.com/acme/hello")
        #expect(source.gitReference == .tag("1.2.3"))
        #expect(source.options == ["buildTool": "cargo"])
    }

    @Test
    func cargoRepositoryUrlDefaultsToARevisionForFortyHexCharacterVersions() throws {
        let item = try makeItem(id: "pkg:cargo/hello@\(Self.commit)?repository_url=https%3A%2F%2Fgithub.com%2Facme%2Fhello")
        let source = try standardSource(PackageSourceParser.parseCargoPackage(item))
        #expect(source.repositoryUrl == "https://github.com/acme/hello")
        #expect(source.gitReference == .revision(Self.commit))
    }

    @Test
    func cargoUppercaseOrShortHashesAreTags() throws {
        let upper = String(repeating: "A", count: 40)
        let short = String(repeating: "a", count: 39)
        for version in [upper, short] {
            let item = try makeItem(id: "pkg:cargo/hello@\(version)?repository_url=https://example.com/r")
            let source = try standardSource(PackageSourceParser.parseCargoPackage(item))
            #expect(source.gitReference == .tag(version))
        }
    }

    @Test
    func cargoExplicitRevAndTagQualifiersOverrideTheDefault() throws {
        let revItem = try makeItem(id: "pkg:cargo/hello@v1?repository_url=https://example.com/r&rev=true")
        let rev = try standardSource(PackageSourceParser.parseCargoPackage(revItem))
        #expect(rev.gitReference == .revision("v1"))
        #expect(rev.options == ["buildTool": "cargo"])

        let tagItem = try makeItem(id: "pkg:cargo/hello@\(Self.commit)?repository_url=https://example.com/r&tag=TRUE")
        let tag = try standardSource(PackageSourceParser.parseCargoPackage(tagItem))
        #expect(tag.gitReference == .tag(Self.commit))
    }

    @Test
    func cargoRevQualifierWorksWithoutARepositoryUrl() throws {
        let source = try standardSource(PackageSourceParser.parseCargoPackage(makeItem(id: "pkg:cargo/hello@v1?rev=true")))
        #expect(source.gitReference == .revision("v1"))
        #expect(source.repositoryUrl == nil)
    }

    @Test
    func cargoRevQualifierOtherThanTrueIsAnOrdinaryOption() throws {
        let source = try standardSource(PackageSourceParser.parseCargoPackage(makeItem(id: "pkg:cargo/hello@v1?rev=false")))
        #expect(source.gitReference == nil)
        #expect(source.options == ["buildTool": "cargo", "rev": "false"])
    }

    @Test
    func cargoRejectsOtherSchemes() throws {
        #expect(PackageSourceParser.parseCargoPackage(try makeItem(id: "pkg:npm/tool@1")) == .unknown)
        #expect(PackageSourceParser.parseCargoPackage(try makeItem(id: "cargo/tool@1")) == .unknown)
    }

    @Test
    func golangParsesNameVersionAndDerivesTheRepositoryUrl() throws {
        let item = try makeItem(name: "gopls", id: "pkg:golang/golang.org/x/tools/gopls@v0.15.3")
        let method = PackageSourceParser.parseGolangPackage(item)
        #expect(method == .standardPackage(source: PackageSource(
            sourceId: "pkg:golang/golang.org/x/tools/gopls@v0.15.3",
            type: .golang,
            pkgName: "golang.org/x/tools/gopls",
            entryName: "gopls",
            version: "v0.15.3",
            repositoryUrl: "https://golang.org/x/tools/gopls",
            options: ["buildTool": "golang"]
        )))
    }

    @Test
    func golangWithoutVersionDefaultsToLatest() throws {
        let source = try standardSource(PackageSourceParser.parseGolangPackage(makeItem(id: "pkg:golang/github.com/a/b")))
        #expect(source.pkgName == "github.com/a/b")
        #expect(source.version == "latest")
        #expect(source.repositoryUrl == "https://github.com/a/b")
    }

    @Test
    func golangSubpathAfterHashBecomesAnOption() throws {
        let item = try makeItem(id: "pkg:golang/github.com/a/b@v1.0.0#cmd/b")
        let source = try standardSource(PackageSourceParser.parseGolangPackage(item))
        #expect(source.pkgName == "github.com/a/b")
        #expect(source.version == "v1.0.0")
        #expect(source.options == ["buildTool": "golang", "subpath": "cmd/b"])
    }

    @Test
    func golangWithoutSubpathHasNoSubpathOption() throws {
        let source = try standardSource(PackageSourceParser.parseGolangPackage(makeItem(id: "pkg:golang/github.com/a/b@v1")))
        #expect(source.options["subpath"] == nil)
    }

    @Test
    func golangQualifiersPrecedeTheSubpath() throws {
        let item = try makeItem(
            id: "pkg:golang/example.com/tool@v1.0.0?repository_url=https://git.example.com/tool.git&tag=true&tags=a#cmd/tool"
        )
        let source = try standardSource(PackageSourceParser.parseGolangPackage(item))
        #expect(source.repositoryUrl == "https://git.example.com/tool.git")
        #expect(source.gitReference == .tag("v1.0.0"))
        #expect(source.options == ["buildTool": "golang", "tags": "a", "subpath": "cmd/tool"])
    }

    @Test
    func golangRepositoryUrlDoesNotImplyAGitReference() throws {
        let item = try makeItem(id: "pkg:golang/example.com/tool@v1.0.0?repository_url=https://git.example.com/tool.git")
        let source = try standardSource(PackageSourceParser.parseGolangPackage(item))
        #expect(source.repositoryUrl == "https://git.example.com/tool.git")
        #expect(source.gitReference == nil)
    }

    @Test
    func golangRevQualifierSetsARevisionReference() throws {
        let item = try makeItem(id: "pkg:golang/example.com/tool@\(Self.commit)?rev=true")
        let source = try standardSource(PackageSourceParser.parseGolangPackage(item))
        #expect(source.gitReference == .revision(Self.commit))
        #expect(source.repositoryUrl == "https://example.com/tool")
        #expect(source.options == ["buildTool": "golang"])
    }

    @Test
    func golangDecodesPercentEscapesInTheSourceId() throws {
        let item = try makeItem(id: "pkg:golang/example.com/m%2Fv2@v2.0.0")
        let source = try standardSource(PackageSourceParser.parseGolangPackage(item))
        #expect(source.sourceId == "pkg:golang/example.com/m/v2@v2.0.0")
        #expect(source.pkgName == "example.com/m/v2")
    }

    @Test
    func golangRejectsOtherSchemes() throws {
        #expect(PackageSourceParser.parseGolangPackage(try makeItem(id: "pkg:cargo/tool@1")) == .unknown)
    }

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
        #expect(PackageSourceParser.parseGithubPackage(try makeItem(id: "pkg:github/acme@v1", sourceExtras: build)) == .unknown)
        #expect(PackageSourceParser.parseGithubPackage(try makeItem(id: "pkg:github/@v1", sourceExtras: build)) == .unknown)
        #expect(PackageSourceParser.parseGithubPackage(try makeItem(id: "pkg:gitlab/acme/tool@v1", sourceExtras: build)) == .unknown)
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
        let method = PackageSourceParser.parseGithubPackage(try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: builds))
        guard case .sourceBuild(_, let command) = method else {
            Issue.record("expected a source build, got \(method)")
            return
        }
        #expect(command == "make mac")
    }

    @Test
    func githubSourceBuildWithoutDarwinTargetOrWithoutBuildIsUnknown() throws {
        let linuxOnly = #", "build": [{ "target": "linux_x64", "run": "make" }]"#
        #expect(PackageSourceParser.parseGithubPackage(try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: linuxOnly)) == .unknown)
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

    @Test
    func registryParsersRejectSourceIdsWithoutAPackageName() throws {
        let parsers: [(String, (RegistryItem) -> InstallationMethod)] = [
            ("pkg:cargo/", PackageSourceParser.parseCargoPackage),
            ("pkg:cargo/?a=b", PackageSourceParser.parseCargoPackage),
            ("pkg:gem/", PackageSourceParser.parseRubyGem),
            ("pkg:golang/", PackageSourceParser.parseGolangPackage),
            ("pkg:golang/#sub", PackageSourceParser.parseGolangPackage),
            ("pkg:npm/", PackageSourceParser.parseNpmPackage),
            ("pkg:npm/?a=b", PackageSourceParser.parseNpmPackage),
            ("pkg:pypi/", PackageSourceParser.parsePythonPackage),
            ("pkg:github/", PackageSourceParser.parseGithubPackage)
        ]
        for (id, parse) in parsers {
            #expect(parse(try makeItem(id: id)) == .unknown, "\(id)")
        }
    }

    @Test
    func qualifiersWithoutAnEqualsSignAreSkippedByEveryParser() throws {
        let cases: [(String, String, (RegistryItem) -> InstallationMethod)] = [
            ("pkg:cargo/name?flag", "cargo", PackageSourceParser.parseCargoPackage),
            ("pkg:gem/name?flag", "gem", PackageSourceParser.parseRubyGem),
            ("pkg:golang/name?flag", "golang", PackageSourceParser.parseGolangPackage),
            ("pkg:npm/name?flag", "npm", PackageSourceParser.parseNpmPackage),
            ("pkg:pypi/name?flag", "pip", PackageSourceParser.parsePythonPackage)
        ]
        for (id, buildTool, parse) in cases {
            let source = try standardSource(parse(makeItem(id: id)))
            #expect(source.pkgName == "name", "\(id)")
            #expect(source.options == ["buildTool": buildTool], "\(id)")
        }
    }

    @Test
    func npmParsesPlainAndScopedPackageNames() throws {
        let cases: [(id: String, name: String, version: String)] = [
            ("pkg:npm/tool@1.2.3", "tool", "1.2.3"),
            ("pkg:npm/tool", "tool", "latest"),
            ("pkg:npm/tool@", "tool", "latest"),
            ("pkg:npm/@org/tool@1.0.0", "@org/tool", "1.0.0"),
            ("pkg:npm/%40org%2Ftool@1.0.0", "@org/tool", "1.0.0"),
            ("pkg:npm/@org/tool", "@org/tool", "latest")
        ]
        for (id, name, version) in cases {
            let item = try makeItem(name: "entry", id: id)
            let source = try standardSource(PackageSourceParser.parseNpmPackage(item))
            #expect(source.pkgName == name, "\(id)")
            #expect(source.version == version, "\(id)")
            #expect(source.type == .npm)
            #expect(source.entryName == "entry")
        }
    }

    @Test
    func npmRejectsOtherSchemes() throws {
        #expect(PackageSourceParser.parseNpmPackage(try makeItem(id: "pkg:cargo/tool@1")) == .unknown)
    }

    @Test
    func everyStandardParserHandlesRepositoryRevisionTagAndPlainQualifiers() throws {
        let parsers: [(prefix: String, buildTool: String, parse: (RegistryItem) -> InstallationMethod)] = [
            ("pkg:npm/tool@1.0.0", "npm", PackageSourceParser.parseNpmPackage),
            ("pkg:gem/tool@1.0.0", "gem", PackageSourceParser.parseRubyGem),
            ("pkg:pypi/tool@1.0.0", "pip", PackageSourceParser.parsePythonPackage)
        ]
        for (prefix, buildTool, parse) in parsers {
            let repository = try standardSource(parse(makeItem(id: "\(prefix)?repository_url=https://example.com/tool")))
            #expect(repository.repositoryUrl == "https://example.com/tool", "\(prefix)")
            #expect(repository.gitReference == nil, "\(prefix)")
            #expect(repository.options == ["buildTool": buildTool], "\(prefix)")

            let revision = try standardSource(parse(makeItem(id: "\(prefix)?rev=true")))
            #expect(revision.gitReference == .revision("1.0.0"), "\(prefix)")
            #expect(revision.options == ["buildTool": buildTool], "\(prefix)")

            let tag = try standardSource(parse(makeItem(id: "\(prefix)?tag=TRUE")))
            #expect(tag.gitReference == .tag("1.0.0"), "\(prefix)")

            let plain = try standardSource(parse(makeItem(id: "\(prefix)?extra=a,b&rev=false&dev=true")))
            #expect(plain.gitReference == nil, "\(prefix)")
            #expect(plain.options == ["buildTool": buildTool, "extra": "a,b", "rev": "false", "dev": "true"], "\(prefix)")
        }
    }

    @Test
    func gemAndPypiParseNamesAndVersions() throws {
        let gem = try standardSource(PackageSourceParser.parseRubyGem(makeItem(id: "pkg:gem/rubocop@1.2")))
        #expect(gem.pkgName == "rubocop")
        #expect(gem.version == "1.2")
        #expect(gem.type == .gem)
        #expect(PackageSourceParser.parseRubyGem(try makeItem(id: "pkg:pypi/ruff@1")) == .unknown)
        #expect(PackageSourceParser.parseRubyGem(try makeItem(id: "pkg:gem/@1")) == .unknown)

        let pypi = try standardSource(PackageSourceParser.parsePythonPackage(makeItem(id: "pkg:pypi/ruff")))
        #expect(pypi.pkgName == "ruff")
        #expect(pypi.version == "latest")
        #expect(pypi.type == .pip)
        #expect(PackageSourceParser.parsePythonPackage(try makeItem(id: "pkg:gem/ruff@1")) == .unknown)
        #expect(PackageSourceParser.parsePythonPackage(try makeItem(id: "pkg:pypi/@1")) == .unknown)
    }

    @Test
    func installMethodDispatchesEveryRegistryScheme() throws {
        let cases: [(String, PackageManagerType)] = [
            ("pkg:npm/tool@1", .npm),
            ("pkg:pypi/tool@1", .pip),
            ("pkg:gem/tool@1", .gem)
        ]
        for (id, type) in cases {
            let method = try #require(try makeItem(id: id).installMethod, "\(id)")
            #expect(method.packageManagerType == type, "\(id)")
            #expect(method.packageDescription == "tool@1", "\(id)")
        }

        let build = try #require(try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: #", "build": { "run": "make" }"#).installMethod)
        #expect(build.packageManagerType == .sourceBuild)

        let asset = #", "asset": { "target": "darwin", "file": "tool.zip" }"#
        let download = try #require(try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: asset).installMethod)
        #expect(download.packageManagerType == .github)
    }
}
