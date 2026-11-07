//
//  Registry.swift
//  Dreamder
//
//  Created by Abe Malla on 2/2/25.
//

import Testing
import Foundation
@testable import Dreamder

@Suite()
@MainActor
struct RegistryTests {
    private static let fixture = #"""
    [
      {
        "name": "actionlint",
        "description": "Static checker for GitHub Actions workflow files.",
        "homepage": "https://github.com/rhysd/actionlint",
        "licenses": ["MIT"],
        "languages": ["YAML"],
        "categories": ["Linter"],
        "source": {
          "id": "pkg:github/rhysd/actionlint@v1.7.7",
          "asset": [
            { "target": "linux_x64", "file": "actionlint_linux.tar.gz", "bin": "actionlint" },
            { "target": "darwin", "file": "actionlint_darwin.tar.gz", "bin": "actionlint" }
          ]
        },
        "bin": { "actionlint": "github:actionlint" }
      },
      {
        "name": "ada-language-server",
        "description": "Language server for Ada\nand SPARK.",
        "homepage": "https://github.com/AdaCore/ada_language_server",
        "licenses": ["GPL-3.0-or-later"],
        "languages": ["Ada"],
        "categories": ["LSP"],
        "source": {
          "id": "pkg:github/AdaCore/ada_language_server@26.0.202509",
          "asset": {
            "target": ["darwin_x64", "darwin_arm64"],
            "file": "als-darwin.tar.gz"
          },
          "version_overrides": [
            {
              "constraint": "semver:<=25.0.1",
              "id": "pkg:github/AdaCore/ada_language_server@25.0.1",
              "asset": { "target": "darwin", "file": "als-25.0.1-darwin.tar.gz" }
            }
          ]
        }
      },
      {
        "name": "typescript-language-server",
        "description": "Language Server Protocol implementation for TypeScript.",
        "homepage": "https://github.com/typescript-language-server/typescript-language-server",
        "licenses": ["Apache-2.0"],
        "languages": ["TypeScript", "JavaScript"],
        "categories": ["LSP"],
        "source": { "id": "pkg:npm/typescript-language-server@4.3.4" },
        "bin": { "typescript-language-server": "npm:typescript-language-server" }
      },
      {
        "name": "vtsls",
        "description": "LSP wrapper around the TypeScript extension.",
        "homepage": "https://github.com/yioneko/vtsls",
        "licenses": ["MIT"],
        "languages": ["TypeScript"],
        "categories": ["LSP"],
        "source": { "id": "pkg:npm/%40vtsls%2Flanguage-server@0.2.9" }
      },
      {
        "name": "source-built-ls",
        "description": "Built from source.",
        "homepage": "https://example.com",
        "licenses": ["MIT"],
        "languages": ["Zig"],
        "categories": ["LSP"],
        "source": {
          "id": "pkg:github/acme/server@0123456789abcdef0123456789abcdef01234567",
          "build": { "run": "make" }
        }
      },
      {
        "name": "nuget-tool",
        "description": "Unsupported source scheme.",
        "homepage": "https://example.com/tool/",
        "licenses": ["MIT"],
        "languages": ["C#"],
        "categories": ["Formatter"],
        "source": { "id": "pkg:nuget/Tool@1.0.0" }
      },
      {
        "name": "simple-file-tool",
        "description": "Single file asset.",
        "homepage": "https://example.com",
        "licenses": ["MIT"],
        "languages": ["Lua"],
        "categories": ["LSP"],
        "source": {
          "id": "pkg:github/acme/simple@v2.0.0",
          "asset": { "file": "simple.zip" }
        }
      }
    ]
    """#

    private func decodeFixture() throws -> [RegistryItem] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([RegistryItem].self, from: Data(Self.fixture.utf8))
    }

    private func item(_ name: String) throws -> RegistryItem {
        try #require(decodeFixture().first { $0.name == name }, "fixture is missing \(name)")
    }

    @Test
    func fixtureDecodesEveryEntryInOrder() throws {
        let names = try decodeFixture().map(\.name)
        #expect(names == [
            "actionlint", "ada-language-server", "typescript-language-server", "vtsls",
            "source-built-ls", "nuget-tool", "simple-file-tool"
        ])
    }

    @Test
    func decodesScalarAndListFields() throws {
        let actionlint = try item("actionlint")
        #expect(actionlint.description == "Static checker for GitHub Actions workflow files.")
        #expect(actionlint.licenses == ["MIT"])
        #expect(actionlint.languages == ["YAML"])
        #expect(actionlint.categories == ["Linter"])
        #expect(actionlint.bin == ["actionlint": "github:actionlint"])
        #expect(try item("vtsls").bin == nil)
    }

    @Test
    func handlesVersionOverrides() throws {
        let overrides = try #require(try item("ada-language-server").source.versionOverrides)
        #expect(overrides.count == 1)
        #expect(overrides.first?.constraint == "semver:<=25.0.1")
        #expect(overrides.first?.id == "pkg:github/AdaCore/ada_language_server@25.0.1")
        #expect(overrides.first?.asset?.getDarwinFileName() == "als-25.0.1-darwin.tar.gz")
        #expect(try item("actionlint").source.versionOverrides == nil)
    }

    @Test
    func assetContainerAcceptsSingleListAndFileShapes() throws {
        let single = try #require(try item("ada-language-server").source.asset)
        guard case .single = single else {
            Issue.record("expected a single asset")
            return
        }
        let multiple = try #require(try item("actionlint").source.asset)
        guard case .multiple(let assets) = multiple else {
            Issue.record("expected an asset list")
            return
        }
        #expect(assets.count == 2)
        let simple = try #require(try item("simple-file-tool").source.asset)
        guard case .simpleFile(let file) = simple else {
            Issue.record("expected a bare file asset")
            return
        }
        #expect(file == "simple.zip")
        #expect(try item("typescript-language-server").source.asset == nil)
    }

    @Test
    func darwinFileNameSkipsAssetsForOtherPlatforms() throws {
        #expect(try item("actionlint").source.asset?.getDarwinFileName() == "actionlint_darwin.tar.gz")
        #expect(try item("ada-language-server").source.asset?.getDarwinFileName() == "als-darwin.tar.gz")
        #expect(try item("simple-file-tool").source.asset?.getDarwinFileName() == "simple.zip")
    }

    @Test
    func presentationHelpersNormalizeText() throws {
        #expect(try item("ada-language-server").sanitizedName == "Ada Language Server")
        #expect(try item("source-built-ls").sanitizedName == "Source Built LS")
        #expect(try item("ada-language-server").sanitizedDescription == "Language server for Ada and SPARK.")
        #expect(try item("actionlint").homepagePretty == "github.com/rhysd/actionlint")
        #expect(try item("nuget-tool").homepagePretty == "example.com/tool/")
    }

    @Test
    func npmSourceBecomesAStandardPackage() throws {
        let method = try #require(try item("typescript-language-server").installMethod)
        let expected = PackageSource(
            sourceId: "pkg:npm/typescript-language-server@4.3.4",
            type: .npm,
            pkgName: "typescript-language-server",
            entryName: "typescript-language-server",
            version: "4.3.4",
            options: ["buildTool": "npm"]
        )
        #expect(method == .standardPackage(source: expected))
        #expect(method.packageDescription == "typescript-language-server@4.3.4")
    }

    @Test
    func scopedNpmPackagesKeepTheirScopeAndDecodePercentEscapes() throws {
        let method = try #require(try item("vtsls").installMethod)
        #expect(method.packageName == "@vtsls/language-server")
        #expect(method.version == "0.2.9")
        #expect(method.packageManagerType == .npm)
    }

    @Test
    func githubAssetBecomesABinaryDownloadForTheTag() throws {
        let method = try #require(try item("actionlint").installMethod)
        let expectedURL = try #require(
            URL(string: "https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_darwin.tar.gz")
        )
        guard case .binaryDownload(let source, let url) = method else {
            Issue.record("expected a binary download, got \(method)")
            return
        }
        #expect(url == expectedURL)
        #expect(source.type == .github)
        #expect(source.gitReference == .tag("v1.7.7"))
    }

    @Test
    func githubWithoutAssetBuildsFromSourceAtTheCommit() throws {
        let method = try #require(try item("source-built-ls").installMethod)
        guard case .sourceBuild(let source, let command) = method else {
            Issue.record("expected a source build, got \(method)")
            return
        }
        #expect(command == "make")
        #expect(source.type == .sourceBuild)
        #expect(source.repositoryUrl == "https://github.com/acme/server")
        #expect(source.gitReference == .revision("0123456789abcdef0123456789abcdef01234567"))
    }

    @Test
    func unsupportedSourceSchemesHaveNoInstallMethod() throws {
        #expect(try item("nuget-tool").installMethod == nil)
    }

    @Test
    func malformedEntriesFailToDecode() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        #expect(throws: DecodingError.self) {
            try decoder.decode([RegistryItem].self, from: Data(#"[{"name": "only-a-name"}]"#.utf8))
        }
    }
}
