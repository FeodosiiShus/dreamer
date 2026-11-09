import Testing
import Foundation
@testable import Dreamder

struct ParserBuildCase {
    let id: String
    let buildTool: String
    let parse: (RegistryItem) -> InstallationMethod
}

struct NpmNameCase {
    let id: String
    let name: String
    let version: String
}

struct InvalidEscapeCase {
    let id: String
    let type: PackageManagerType
    let parse: (RegistryItem) -> InstallationMethod
}

extension PackageSourceParserTests {
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
        let cases = [
            ParserBuildCase(
                id: "pkg:cargo/name?flag",
                buildTool: "cargo",
                parse: PackageSourceParser.parseCargoPackage
            ),
            ParserBuildCase(id: "pkg:gem/name?flag", buildTool: "gem", parse: PackageSourceParser.parseRubyGem),
            ParserBuildCase(
                id: "pkg:golang/name?flag",
                buildTool: "golang",
                parse: PackageSourceParser.parseGolangPackage
            ),
            ParserBuildCase(id: "pkg:npm/name?flag", buildTool: "npm", parse: PackageSourceParser.parseNpmPackage),
            ParserBuildCase(id: "pkg:pypi/name?flag", buildTool: "pip", parse: PackageSourceParser.parsePythonPackage)
        ]
        for testCase in cases {
            let id = testCase.id
            let source = try standardSource(testCase.parse(makeItem(id: id)))
            #expect(source.pkgName == "name", "\(id)")
            #expect(source.options == ["buildTool": testCase.buildTool], "\(id)")
        }
    }

    @Test
    func npmParsesPlainAndScopedPackageNames() throws {
        let cases = [
            NpmNameCase(id: "pkg:npm/tool@1.2.3", name: "tool", version: "1.2.3"),
            NpmNameCase(id: "pkg:npm/tool", name: "tool", version: "latest"),
            NpmNameCase(id: "pkg:npm/tool@", name: "tool", version: "latest"),
            NpmNameCase(id: "pkg:npm/@org/tool@1.0.0", name: "@org/tool", version: "1.0.0"),
            NpmNameCase(id: "pkg:npm/%40org%2Ftool@1.0.0", name: "@org/tool", version: "1.0.0"),
            NpmNameCase(id: "pkg:npm/@org/tool", name: "@org/tool", version: "latest")
        ]
        for testCase in cases {
            let id = testCase.id
            let item = try makeItem(name: "entry", id: id)
            let source = try standardSource(PackageSourceParser.parseNpmPackage(item))
            #expect(source.pkgName == testCase.name, "\(id)")
            #expect(source.version == testCase.version, "\(id)")
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
        let parsers = [
            ParserBuildCase(id: "pkg:npm/tool@1.0.0", buildTool: "npm", parse: PackageSourceParser.parseNpmPackage),
            ParserBuildCase(id: "pkg:gem/tool@1.0.0", buildTool: "gem", parse: PackageSourceParser.parseRubyGem),
            ParserBuildCase(id: "pkg:pypi/tool@1.0.0", buildTool: "pip", parse: PackageSourceParser.parsePythonPackage)
        ]
        for testCase in parsers {
            let prefix = testCase.id
            let buildTool = testCase.buildTool
            let parse = testCase.parse
            let repositoryId = "\(prefix)?repository_url=https://example.com/tool"
            let repository = try standardSource(parse(makeItem(id: repositoryId)))
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
            let expectedOptions = ["buildTool": buildTool, "extra": "a,b", "rev": "false", "dev": "true"]
            #expect(plain.options == expectedOptions, "\(prefix)")
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

        let buildExtras = #", "build": { "run": "make" }"#
        let build = try #require(try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: buildExtras).installMethod)
        #expect(build.packageManagerType == .sourceBuild)

        let asset = #", "asset": { "target": "darwin", "file": "tool.zip" }"#
        let download = try #require(try makeItem(id: "pkg:github/acme/tool@v1", sourceExtras: asset).installMethod)
        #expect(download.packageManagerType == .github)
    }

    @Test
    func sourceIdsWithInvalidPercentEscapesAreParsedVerbatim() throws {
        let cases = [
            InvalidEscapeCase(id: "pkg:npm/tool%zz@1.0.0", type: .npm, parse: PackageSourceParser.parseNpmPackage),
            InvalidEscapeCase(id: "pkg:gem/tool%zz@1.0.0", type: .gem, parse: PackageSourceParser.parseRubyGem),
            InvalidEscapeCase(
                id: "pkg:cargo/tool%zz@1.0.0",
                type: .cargo,
                parse: PackageSourceParser.parseCargoPackage
            ),
            InvalidEscapeCase(
                id: "pkg:golang/example.com/tool%zz@1.0.0",
                type: .golang,
                parse: PackageSourceParser.parseGolangPackage
            )
        ]
        for testCase in cases {
            let id = testCase.id
            let source = try standardSource(testCase.parse(makeItem(id: id)))
            #expect(source.sourceId == id, "\(id)")
            #expect(source.type == testCase.type, "\(id)")
            #expect(source.pkgName.hasSuffix("tool%zz"), "\(id)")
            #expect(source.version == "1.0.0", "\(id)")
        }
    }
}
