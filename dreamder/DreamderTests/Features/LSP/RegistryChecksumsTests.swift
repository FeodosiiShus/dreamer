import CryptoKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct RegistryChecksumsTests {
    private static let payload = Data("registry payload".utf8)
    private static let file = "registry.json.zip"

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private let digest = RegistryChecksumsTests.sha256Hex(RegistryChecksumsTests.payload)

    private func outcome(
        _ body: String,
        data: Data = RegistryChecksumsTests.payload,
        file: String = RegistryChecksumsTests.file
    ) -> String {
        outcome(Data(body.utf8), data: data, file: file)
    }

    private func outcome(
        _ body: Data,
        data: Data = RegistryChecksumsTests.payload,
        file: String = RegistryChecksumsTests.file
    ) -> String {
        do {
            try RegistryChecksums(body).verify(data, as: file)
            return "ok"
        } catch RegistryManagerError.checksumMissing(let missing) {
            return "missing:\(missing)"
        } catch RegistryManagerError.checksumMismatch(let mismatched) {
            return "mismatch:\(mismatched)"
        } catch {
            return "other"
        }
    }

    @Test
    func matchingDigestVerifies() {
        #expect(outcome("\(digest)  registry.json.zip\n") == "ok")
    }

    @Test
    func differingContentIsAMismatch() {
        #expect(outcome("\(digest)  registry.json.zip\n", data: Data("tampered".utf8)) == "mismatch:registry.json.zip")
    }

    @Test
    func aFileWithoutALineIsMissing() {
        #expect(outcome("\(digest)  registry.json\n") == "missing:registry.json.zip")
        #expect(outcome("\(digest)  registry.json.zip\n", file: "other.zip") == "missing:other.zip")
    }

    @Test
    func emptyInputHasNoEntries() {
        #expect(outcome("") == "missing:registry.json.zip")
        #expect(outcome(Data()) == "missing:registry.json.zip")
    }

    @Test
    func undecodableBytesHaveNoEntries() {
        #expect(outcome(Data([0xFF, 0xFE, 0x00, 0xC3, 0x28])) == "missing:registry.json.zip")
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func everyLineEndingSeparatesEntries(separator: String) {
        let zeros = String(repeating: "0", count: 64)
        let body = "junk\(separator)\(zeros)  other.zip\(separator)\(digest)  registry.json.zip\(separator)"
        #expect(outcome(body) == "ok")
    }

    @Test
    func aMissingFinalNewlineIsAccepted() {
        #expect(outcome("\(digest)  registry.json.zip") == "ok")
    }

    @Test
    func extraSpacesAroundTheEntryAreIgnored() {
        #expect(outcome("   \(digest)     registry.json.zip   \n") == "ok")
        #expect(outcome("\(digest) registry.json.zip\n") == "ok")
    }

    @Test
    func theBinaryMarkerIsStripped() {
        #expect(outcome("\(digest) *registry.json.zip\n") == "ok")
        #expect(outcome("\(digest)  *registry.json.zip\n") == "ok")
    }

    @Test
    func uppercaseHexDigestsAreAccepted() {
        #expect(outcome("\(digest.uppercased())  registry.json.zip\n") == "ok")
        #expect(outcome("\(digest.uppercased()) *registry.json.zip\n") == "ok")
    }

    @Test
    func uppercaseDigestOfDifferentContentStillMismatches() {
        let other = Self.sha256Hex(Data("other".utf8)).uppercased()
        #expect(outcome("\(other)  registry.json.zip\n") == "mismatch:registry.json.zip")
    }

    @Test
    func digestsWithTheWrongShapeAreIgnored() {
        let short = String(digest.dropLast())
        let long = digest + "0"
        let nonHex = String(digest.dropLast()) + "g"
        let lines = [
            "\(short)  registry.json.zip",
            "\(long)  registry.json.zip",
            "\(nonHex)  registry.json.zip",
            "abc123  registry.json.zip"
        ]
        for line in lines {
            #expect(outcome("\(line)\n") == "missing:registry.json.zip")
        }
    }

    @Test
    func aLineWithoutAFileNameIsIgnored() {
        #expect(outcome("\(digest)\n") == "missing:registry.json.zip")
        #expect(outcome("\(digest)   \n") == "missing:registry.json.zip")
    }

    @Test
    func theLastLineForAFileWins() {
        let wrong = String(repeating: "a", count: 64)
        #expect(outcome("\(wrong)  registry.json.zip\n\(digest)  registry.json.zip\n") == "ok")
        #expect(outcome("\(digest)  registry.json.zip\n\(wrong)  registry.json.zip\n") == "mismatch:registry.json.zip")
    }

    @Test
    func fileNamesMayContainSpaces() {
        #expect(outcome("\(digest)  my registry.json.zip\n", file: "my registry.json.zip") == "ok")
        #expect(outcome("\(digest) *my registry.json.zip\n", file: "my registry.json.zip") == "ok")
        #expect(outcome("\(digest)  my registry.json.zip\n", file: "registry.json.zip") == "missing:registry.json.zip")
    }

    @Test
    func entriesForSeveralFilesAreKeptApart() {
        let other = Self.sha256Hex(Data("other".utf8))
        let body = "\(other)  registry.json\n\(digest)  registry.json.zip\n"
        #expect(outcome(body) == "ok")
        #expect(outcome(body, data: Data("other".utf8), file: "registry.json") == "ok")
        #expect(outcome(body, data: Data("other".utf8)) == "mismatch:registry.json.zip")
    }

    @Test
    func equalBodiesParseToEqualValues() {
        let body = Data("\(digest)  registry.json.zip\n".utf8)
        #expect(RegistryChecksums(body) == RegistryChecksums(body))
        #expect(RegistryChecksums(body) != RegistryChecksums(Data()))
    }
}
