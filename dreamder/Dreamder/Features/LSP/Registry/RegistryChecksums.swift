import CryptoKit
import Foundation

nonisolated struct RegistryChecksums: Equatable, Sendable {
    private static let digestLength = 64

    private let digests: [String: String]

    init(_ data: Data) {
        var digests: [String: String] = [:]
        let text = String(bytes: data, encoding: .utf8) ?? ""
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2,
                  fields[0].count == Self.digestLength,
                  fields[0].allSatisfy(\.isHexDigit) else { continue }
            let file = fields[1].trimmingCharacters(in: .whitespaces)
            digests[file.hasPrefix("*") ? String(file.dropFirst()) : file] = fields[0].lowercased()
        }
        self.digests = digests
    }

    func verify(_ data: Data, as file: String) throws {
        guard let expected = digests[file] else {
            throw RegistryManagerError.checksumMissing(file: file)
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw RegistryManagerError.checksumMismatch(file: file)
        }
    }
}
