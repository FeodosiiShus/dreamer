import Testing
import Foundation
@testable import Dreamder

@Suite
struct PackageSourceParserTests {
    static let commit = "0123456789abcdef0123456789abcdef01234567"

    func makeItem(name: String = "entry", id: String, sourceExtras: String = "") throws -> RegistryItem {
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

    func standardSource(
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
}
