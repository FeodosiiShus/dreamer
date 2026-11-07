import Foundation

nonisolated struct GitCommandResult: Sendable, Equatable {
    var exitCode: Int32
    var terminatedBySignal: Bool
    var startFailure: String?
    var standardOutput: Data
    var standardError: Data

    init(
        exitCode: Int32,
        terminatedBySignal: Bool = false,
        startFailure: String? = nil,
        standardOutput: Data = Data(),
        standardError: Data = Data()
    ) {
        self.exitCode = exitCode
        self.terminatedBySignal = terminatedBySignal
        self.startFailure = startFailure
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    init(_ output: ProcessOutput) {
        self.init(
            exitCode: output.exitCode,
            terminatedBySignal: output.terminatedBySignal,
            standardOutput: output.standardOutput,
            standardError: output.standardError
        )
    }

    static func startFailed(_ message: String) -> GitCommandResult {
        GitCommandResult(exitCode: -1, startFailure: message)
    }

    var success: Bool {
        success(ignoring: [])
    }

    func success(ignoring ignoredExitCodes: Set<Int32>) -> Bool {
        guard startFailure == nil, !terminatedBySignal else { return false }
        return exitCode == 0 || ignoredExitCodes.contains(exitCode)
    }

    var outputText: String {
        String(decoding: standardOutput, as: UTF8.self)
    }

    var standardErrorText: String {
        String(decoding: standardError, as: UTF8.self)
    }

    var combinedText: String {
        let output = outputText
        let error = startFailure ?? standardErrorText
        guard !error.isEmpty else { return output }
        guard !output.isEmpty else { return error }
        return output.hasSuffix("\n") ? output + error : output + "\n" + error
    }

    var output: [String] {
        Self.lines(in: outputText)
    }

    var errorOutput: [String] {
        if let startFailure {
            return [startFailure]
        }
        return Self.lines(in: standardErrorText).filter { !Self.looksLikeProgress($0) }
    }

    var errorMessage: String {
        var lines = errorOutput
        if lines.isEmpty {
            if success { return "" }
            let stdout = output
            if !stdout.isEmpty {
                lines = stdout
            } else if terminatedBySignal {
                lines = ["git was terminated by signal \(exitCode)"]
            } else {
                lines = ["git exited with code \(exitCode)"]
            }
        }
        return lines
            .filter { !Self.isErrorHeaderLine($0) }
            .map(Self.cleanupErrorPrefixes)
            .joined(separator: "\n")
    }

    static func lines(in text: String) -> [String] {
        var lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    static func cleanupErrorPrefixes(_ message: String) -> String {
        var cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["fatal:", "error:"] where cleaned.hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    static func isErrorHeaderLine(_ line: String) -> Bool {
        line.hasPrefix("@") && line.hasSuffix("@")
    }

    private static let remoteProgressPrefix = "remote: "

    private static let suppressedProgressIndicators = [
        "Counting objects: ",
        "Enumerating objects: ",
        "Compressing objects: ",
        "Writing objects: ",
        "Receiving objects: ",
        "Resolving deltas: ",
        "Finding sources: ",
        "Updating files: ",
        "Checking out files: ",
        "Expanding reachable commits in commit graph: ",
        "Delta compression using up to "
    ]

    static func looksLikeProgress(_ line: String) -> Bool {
        if matchesPercentageProgress(line) {
            return true
        }
        return suppressedProgressIndicators.contains { indicator in
            if line.hasPrefix(indicator) {
                return true
            }
            return line.hasPrefix(remoteProgressPrefix) && line.dropFirst(remoteProgressPrefix.count).hasPrefix(indicator)
        }
    }

    private static func matchesPercentageProgress(_ line: String) -> Bool {
        var searchRange = line.startIndex..<line.endIndex
        while let marker = line.range(of: "% (", range: searchRange) {
            searchRange = marker.upperBound..<line.endIndex
            let beforeMarker = line[..<marker.lowerBound]
            let percentDigits = beforeMarker.reversed().prefix(while: isDigit)
            guard (1...3).contains(percentDigits.count) else { continue }
            let beforeDigits = beforeMarker.dropLast(percentDigits.count)
            guard beforeDigits.reversed().first(where: { !$0.isWhitespace }) == ":" else { continue }

            let afterMarker = line[marker.upperBound...]
            let completed = afterMarker.prefix(while: isDigit)
            guard !completed.isEmpty else { continue }
            let afterCompleted = afterMarker.dropFirst(completed.count)
            guard afterCompleted.first == "/" else { continue }
            let afterSlash = afterCompleted.dropFirst()
            let total = afterSlash.prefix(while: isDigit)
            guard !total.isEmpty, afterSlash.dropFirst(total.count).first == ")" else { continue }
            return true
        }
        return false
    }

    private static func isDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character)
    }
}
