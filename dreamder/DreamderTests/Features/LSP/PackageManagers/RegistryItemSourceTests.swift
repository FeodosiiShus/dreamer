import Foundation
import Testing
@testable import Dreamder

private typealias Source = RegistryItem.Source

private struct Holder<Value: Codable>: Codable {
    let value: Value
}

private func decode<Value: Codable>(_ type: Value.Type, _ json: String) throws -> Value {
    let holder = try JSONDecoder().decode(Holder<Value>.self, from: Data(#"{"value": \#(json)}"#.utf8))
    return holder.value
}

private func encoded<Value: Codable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(Holder(value: value))
    return String(decoding: data, as: UTF8.self)
}

@Suite
struct RegistryItemSourceTests {
    @Test
    func assetContainerDecodesEveryShapeOfTheRegistry() throws {
        let single = try decode(Source.AssetContainer.self, #"{ "target": "darwin", "file": "a.zip" }"#)
        guard case .single(let asset) = single else {
            Issue.record("expected a single asset, got \(single)")
            return
        }
        #expect(asset.file == "a.zip")

        let multiple = try decode(Source.AssetContainer.self, #"[{ "target": "darwin", "file": "a.zip" }, { "target": ["linux"], "file": "b.zip" }]"#)
        guard case .multiple(let assets) = multiple else {
            Issue.record("expected an asset list, got \(multiple)")
            return
        }
        #expect(assets.map(\.file) == ["a.zip", "b.zip"])

        let simple = try decode(Source.AssetContainer.self, #"{ "file": "c.zip" }"#)
        guard case .simpleFile("c.zip") = simple else {
            Issue.record("expected a simple file, got \(simple)")
            return
        }
    }

    @Test
    func assetContainerFallsBackToNoneForUnrecognizedShapes() throws {
        for json in ["123", #"{ "file": "a", "other": "b" }"#, #"{ "other": "b" }"#, #""text""#] {
            let container = try decode(Source.AssetContainer.self, json)
            guard case .none = container else {
                Issue.record("expected no asset for \(json), got \(container)")
                continue
            }
            #expect(container.getDarwinFileName() == nil)
        }
    }

    @Test
    func assetContainerEncodesBackToItsRegistryShape() throws {
        let single = try decode(Source.AssetContainer.self, #"{ "target": "darwin", "file": "a.zip" }"#)
        #expect(try encoded(single) == #"{"value":{"file":"a.zip","target":"darwin"}}"#)

        let multiple = try decode(Source.AssetContainer.self, #"[{ "target": ["darwin", "unix"], "file": "a.zip" }]"#)
        #expect(try encoded(multiple) == #"{"value":[{"file":"a.zip","target":["darwin","unix"]}]}"#)

        #expect(try encoded(Source.AssetContainer.simpleFile("c.zip")) == #"{"value":{"file":"c.zip"}}"#)
        #expect(try encoded(Source.AssetContainer.none) == #"{"value":null}"#)
    }

    @Test
    func darwinFileNameSkipsOtherPlatforms() throws {
        let linuxOnly = try decode(Source.AssetContainer.self, #"{ "target": "linux_x64", "file": "a.zip" }"#)
        #expect(linuxOnly.getDarwinFileName() == nil)

        let linuxList = try decode(Source.AssetContainer.self, #"[{ "target": "linux_x64", "file": "a.zip" }, { "target": ["win_x64"], "file": "b.zip" }]"#)
        #expect(linuxList.getDarwinFileName() == nil)

        let mixed = try decode(Source.AssetContainer.self, #"[{ "target": "linux_x64", "file": "a.zip" }, { "target": ["linux", "darwin"], "file": "b.zip" }]"#)
        #expect(mixed.getDarwinFileName() == "b.zip")

        #expect(Source.AssetContainer.simpleFile("c.zip").getDarwinFileName() == "c.zip")
    }

    @Test
    func buildContainerDecodesAndEncodesItsShapes() throws {
        let single = try decode(Source.BuildContainer.self, #"{ "run": "make", "env": { "A": "1" } }"#)
        guard case .single(let build) = single else {
            Issue.record("expected a single build, got \(single)")
            return
        }
        #expect(build.run == "make")
        #expect(build.env == ["A": "1"])
        #expect(try encoded(single) == #"{"value":{"env":{"A":"1"},"run":"make"}}"#)

        let multiple = try decode(Source.BuildContainer.self, #"[{ "target": "darwin", "run": "make mac", "bin": "tool" }]"#)
        guard case .multiple(let builds) = multiple else {
            Issue.record("expected a build list, got \(multiple)")
            return
        }
        #expect(builds.map(\.run) == ["make mac"])
        #expect(try encoded(multiple) == #"{"value":[{"bin":"tool","run":"make mac","target":"darwin"}]}"#)

        let none = try decode(Source.BuildContainer.self, "123")
        guard case .none = none else {
            Issue.record("expected no build, got \(none)")
            return
        }
        #expect(try encoded(none) == #"{"value":null}"#)
    }

    @Test
    func unixBuildCommandPicksTheMatchingBuild() throws {
        let single = try decode(Source.BuildContainer.self, #"{ "run": "make" }"#)
        #expect(single.getUnixBuildCommand() == "make")

        let list = try decode(Source.BuildContainer.self, #"[{ "run": "none" }, { "target": "linux_x64", "run": "linux" }, { "target": "darwin", "run": "mac" }]"#)
        #expect(list.getUnixBuildCommand() == "mac")

        let linuxOnly = try decode(Source.BuildContainer.self, #"[{ "target": "linux_x64", "run": "linux" }]"#)
        #expect(linuxOnly.getUnixBuildCommand() == nil)

        #expect(Source.BuildContainer.none.getUnixBuildCommand() == nil)
    }

    @Test
    func targetsAcceptStringsAndListsOnly() throws {
        let single = try decode(Source.Target.self, #""darwin""#)
        let multiple = try decode(Source.Target.self, #"["linux", "unix"]"#)
        #expect(single.isDarwinTarget())
        #expect(multiple.isDarwinTarget())
        #expect(try encoded(single) == #"{"value":"darwin"}"#)
        #expect(try encoded(multiple) == #"{"value":["linux","unix"]}"#)

        #expect(throws: DecodingError.self) {
            try decode(Source.Target.self, "42")
        }
    }

    @Test
    func darwinTargetsCoverDarwinAndUnix() throws {
        for name in ["darwin", "unix"] {
            #expect(try decode(Source.Target.self, "\"\(name)\"").isDarwinTarget(), "\(name)")
            #expect(try decode(Source.Target.self, "[\"linux_x64\", \"\(name)\"]").isDarwinTarget(), "\(name)")
        }
        #expect(try decode(Source.Target.self, #""linux_x64""#).isDarwinTarget() == false)
        #expect(try decode(Source.Target.self, #"["linux_x64", "win_x64"]"#).isDarwinTarget() == false)
    }

    @Test
    func binContainersAcceptNamesAndMappings() throws {
        let single = try decode(Source.BinContainer.self, #""tool""#)
        let multiple = try decode(Source.BinContainer.self, #"{ "tool": "bin/tool" }"#)
        guard case .single("tool") = single, case .multiple(let mapping) = multiple else {
            Issue.record("unexpected bin shapes \(single) \(multiple)")
            return
        }
        #expect(mapping == ["tool": "bin/tool"])
        #expect(try encoded(single) == #"{"value":"tool"}"#)
        #expect(try encoded(multiple) == #"{"value":{"tool":"bin/tool"}}"#)

        #expect(throws: DecodingError.self) {
            try decode(Source.BinContainer.self, "[1, 2]")
        }
    }

    @Test
    func assetsKeepTheirBinaryMapping() throws {
        let asset = try decode(Source.Asset.self, #"{ "target": "darwin", "file": "a.zip", "bin": { "tool": "bin/tool" } }"#)
        #expect(asset.file == "a.zip")
        guard case .multiple(let mapping) = asset.bin else {
            Issue.record("expected a bin mapping")
            return
        }
        #expect(mapping == ["tool": "bin/tool"])
    }

    @Test
    func versionOverridesCarryTheirOwnAssets() throws {
        let override = try decode(
            Source.VersionOverride.self,
            #"{ "constraint": "semver:<=1.0.0", "id": "pkg:github/a/b@v1", "asset": { "file": "old.zip" } }"#
        )
        #expect(override.constraint == "semver:<=1.0.0")
        #expect(override.id == "pkg:github/a/b@v1")
        #expect(override.asset?.getDarwinFileName() == "old.zip")
    }
}
