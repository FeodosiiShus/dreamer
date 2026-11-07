import Foundation

nonisolated enum GitCommandLineError: Error, Equatable, Sendable {
    case unterminatedQuote(String)

    var description: String {
        switch self {
        case .unterminatedQuote(let quote): "Malformed git command: unterminated \(quote) quote"
        }
    }
}

nonisolated enum GitCommandLine {
    private static let escapableInDoubleQuotes: Set<Unicode.Scalar> = ["\"", "\\", "$", "`"]
    private static let safeBareScalars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./=:@%+,".unicodeScalars)

    static func tokenize(_ command: String) throws -> [String] {
        let scalars = Array(command.unicodeScalars)
        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        var inToken = false
        var index = 0

        func finishToken() {
            guard inToken else { return }
            tokens.append(String(current))
            current = String.UnicodeScalarView()
            inToken = false
        }

        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            switch scalar {
            case "'":
                inToken = true
                var closed = false
                while index < scalars.count {
                    let inner = scalars[index]
                    index += 1
                    if inner == "'" {
                        closed = true
                        break
                    }
                    current.append(inner)
                }
                if !closed {
                    throw GitCommandLineError.unterminatedQuote("single")
                }
            case "\"":
                inToken = true
                var closed = false
                while index < scalars.count {
                    let inner = scalars[index]
                    index += 1
                    if inner == "\"" {
                        closed = true
                        break
                    }
                    guard inner == "\\", index < scalars.count else {
                        current.append(inner)
                        continue
                    }
                    let escaped = scalars[index]
                    if escapableInDoubleQuotes.contains(escaped) {
                        current.append(escaped)
                        index += 1
                    } else if escaped == "\n" {
                        index += 1
                    } else if escaped == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                        index += 2
                    } else {
                        current.append(inner)
                    }
                }
                if !closed {
                    throw GitCommandLineError.unterminatedQuote("double")
                }
            case "\\":
                guard index < scalars.count else {
                    inToken = true
                    current.append(scalar)
                    break
                }
                let escaped = scalars[index]
                index += 1
                if escaped == "\n" {
                    break
                }
                if escaped == "\r", index < scalars.count, scalars[index] == "\n" {
                    index += 1
                    break
                }
                inToken = true
                current.append(escaped)
            case " ", "\t", "\n", "\r":
                finishToken()
            default:
                inToken = true
                current.append(scalar)
            }
        }
        finishToken()
        return tokens
    }

    static func quote(_ argument: String) -> String {
        guard !argument.isEmpty else { return "''" }
        if argument.unicodeScalars.allSatisfy({ safeBareScalars.contains($0) }) {
            return argument
        }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func display(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}
