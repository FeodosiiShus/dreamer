import Foundation

nonisolated struct ConsoleFileLinkPayload: Sendable, Equatable {
    let path: String
    let line: Int
    let column: Int

    private static let lineKey = "line"
    private static let columnKey = "column"
    private static let allowedPathCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ";:%")
        return allowed
    }()

    init(path: String, line: Int, column: Int) {
        self.path = path
        self.line = line
        self.column = column
    }

    init(target: ConsoleFileLinkTarget) {
        self.init(path: target.url.path(percentEncoded: false), line: target.line, column: target.column)
    }

    init?(link: String, params: [String: String]) {
        guard let path = link.removingPercentEncoding,
              let line = params[Self.lineKey].flatMap({ Int($0) }),
              let column = params[Self.columnKey].flatMap({ Int($0) })
        else { return nil }
        self.init(path: path, line: line, column: column)
    }

    var cellValue: String {
        let encodedPath = path.utf8.reduce(into: "") { encoded, byte in
            let scalar = Unicode.Scalar(byte)
            if Self.allowedPathCharacters.contains(scalar) {
                encoded.unicodeScalars.append(scalar)
            } else {
                encoded += String(format: "%%%02X", byte)
            }
        }
        return "\(Self.lineKey)=\(line):\(Self.columnKey)=\(column);\(encodedPath)"
    }
}
