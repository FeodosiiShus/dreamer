import Foundation
import Testing

nonisolated enum IntelliJTestData {
    struct Pair: Sendable, CustomStringConvertible {
        let name: String
        let input: String
        let expected: String

        var description: String { name }
    }

    static let repositoryRoot: URL = {
        var url = URL(filePath: #filePath).deletingLastPathComponent()
        while url.pathComponents.count > 1 {
            let candidate = url.appending(path: "platform/platform-tests")
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        return URL(filePath: #filePath).deletingLastPathComponent()
    }()

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appending(path: relativePath)
    }

    static func text(_ relativePath: String) throws -> String {
        let contents = try String(contentsOf: url(relativePath), encoding: .utf8)
        return contents.replacingOccurrences(of: "\r\n", with: "\n")
    }

    static func files(in relativeDirectory: String, suffix: String) throws -> [String] {
        let directory = url(relativeDirectory)
        return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(suffix) }
            .sorted()
    }

    static func pairs(
        in relativeDirectory: String,
        inputSuffix: String = "_in.txt",
        expectedSuffix: String = "_out.txt"
    ) throws -> [Pair] {
        try files(in: relativeDirectory, suffix: inputSuffix).map { inputName in
            let name = String(inputName.dropLast(inputSuffix.count))
            return Pair(
                name: name,
                input: try text("\(relativeDirectory)/\(inputName)"),
                expected: try text("\(relativeDirectory)/\(name)\(expectedSuffix)")
            )
        }
    }
}
