//
//  GitClient+Status.swift
//  Dreamder
//
//  Created by Albert Vinizhanau on 10/20/23.
//

import Foundation

/// Methods for parsing git's porcelain v2 format and returning the info in a ``GitClient/Status`` struct.
///
/// Git defines five types of changes to parse in the v2 format:
/// - Ordinary
/// - Renamed/Copied
/// - Unmerged
/// - Untracked
/// - Ignored
///
/// These are documented here: https://git-scm.com/docs/git-status.
///
/// There is one method for each change type that can be returned with the exception of ignored which is, well, ignored.

nonisolated extension GitClient {
    struct Status {
        var changedFiles: [GitChangedFile]
        var unmergedChanges: [GitChangedFile]
        var untrackedFiles: [GitChangedFile]
    }

    /// Fetches and parses the git repository's status.
    /// - Returns: A ``GitClient/Status`` struct with information about the changed files in the repository.
    /// - Throws: Can throw ``GitClient/GitClientError`` errors if it finds unexpected output.
    @concurrent
    func getStatus() async throws -> Status {
        let output = try await run(arguments: ["status", "-z", "--porcelain=2", "-unormal"] + scopePathspecArguments)
        return try parseStatusString(output)
    }

    /// Parses a status string from ``getStatus()`` and returns a ``Status`` object if possible.
    /// - Parameter output: The git output from running `status`. Expects a porcelain v2 string.
    /// - Returns: A status object if parseable.
    func parseStatusString(_ output: String) throws -> Status {
        var contiguous = output
        return try contiguous.withUTF8 { try parseStatus(bytes: $0) }
    }

    /// Discard changes for file
    func discardChanges(for file: URL) async throws {
        _ = try await run(arguments: ["restore", "--", file.path(percentEncoded: false)])
    }

    /// Discard unstaged changes
    func discardAllChanges() async throws {
        _ = try await run(arguments: ["restore", "."])
    }

    private func parseStatus(bytes: UnsafeBufferPointer<UInt8>) throws -> Status {
        var status = Status(changedFiles: [], unmergedChanges: [], untrackedFiles: [])
        var scanner = StatusScanner(bytes: bytes)

        while scanner.cursor < bytes.count {
            let type = bytes[scanner.cursor]
            try scanner.skip(2)

            switch type {
            case UInt8(ascii: "1"):
                status.changedFiles.append(try parseOrdinary(&scanner))
            case UInt8(ascii: "2"):
                status.changedFiles.append(try parseRenamed(&scanner))
            case UInt8(ascii: "u"):
                status.unmergedChanges.append(try parseUnmerged(&scanner))
            case UInt8(ascii: "?"):
                status.untrackedFiles.append(try parseUntracked(&scanner))
            case UInt8(ascii: "!"), UInt8(ascii: "#"):
                _ = try scanner.readField()
            default:
                throw GitClientError.statusInvalidChangeType(Character(Unicode.Scalar(type)))
            }
        }

        return status
    }

    /// Parses an ordinary change.
    /// ```
    /// 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
    /// ```
    private func parseOrdinary(_ scanner: inout StatusScanner) throws -> GitChangedFile {
        let stagedStatus = try scanner.readStatus()
        let status = try scanner.readStatus()
        try scanner.skipFields(6)
        let filename = try scanner.readField()
        return GitChangedFile(
            status: status,
            stagedStatus: stagedStatus,
            fileURL: URL(filePath: filename, relativeTo: directoryURL),
            originalFilename: nil
        )
    }

    /// Parses a renamed or copied change.
    /// ```
    /// 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path><sep><origPath>
    /// ```
    private func parseRenamed(_ scanner: inout StatusScanner) throws -> GitChangedFile {
        let stagedStatus = try scanner.readStatus()
        let status = try scanner.readStatus()
        try scanner.skipFields(7)
        let filename = try scanner.readField()
        let originalFilename = try scanner.readField()
        return GitChangedFile(
            status: status,
            stagedStatus: stagedStatus,
            fileURL: URL(filePath: filename, relativeTo: directoryURL),
            originalFilename: originalFilename
        )
    }

    /// Parses an unmerged change.
    /// ```
    /// u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
    /// ```
    private func parseUnmerged(_ scanner: inout StatusScanner) throws -> GitChangedFile {
        let stagedStatus = try scanner.readStatus()
        let status = try scanner.readStatus()
        try scanner.skipFields(8)
        let filename = try scanner.readField()
        return GitChangedFile(
            status: status,
            stagedStatus: stagedStatus,
            fileURL: URL(filePath: filename, relativeTo: directoryURL),
            originalFilename: nil
        )
    }

    /// Parses an untracked change.
    /// ```
    /// ? <path>
    /// ```
    private func parseUntracked(_ scanner: inout StatusScanner) throws -> GitChangedFile {
        let filename = try scanner.readField()
        return GitChangedFile(
            status: .untracked,
            stagedStatus: .none,
            fileURL: URL(filePath: filename, relativeTo: directoryURL),
            originalFilename: nil
        )
    }
}

nonisolated private struct StatusScanner {
    private static let space = UInt8(ascii: " ")
    private static let separator: UInt8 = 0

    let bytes: UnsafeBufferPointer<UInt8>
    var cursor = 0

    init(bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    mutating func skip(_ count: Int) throws {
        guard cursor + count <= bytes.count else {
            throw GitClient.GitClientError.statusParseEarlyEnd
        }
        cursor += count
    }

    mutating func readStatus() throws -> GitStatus {
        guard cursor < bytes.count else {
            throw GitClient.GitClientError.statusParseEarlyEnd
        }
        let scalar = Unicode.Scalar(bytes[cursor])
        guard let status = GitStatus(rawValue: String(scalar)) else {
            throw GitClient.GitClientError.invalidStatus(Character(scalar))
        }
        cursor += 1
        return status
    }

    mutating func skipFields(_ count: Int) throws {
        for _ in 0..<count {
            repeat {
                try skip(1)
                guard cursor < bytes.count else {
                    throw GitClient.GitClientError.statusParseEarlyEnd
                }
            } while bytes[cursor] != Self.space
        }
        try skip(1)
    }

    mutating func readField() throws -> String {
        guard cursor <= bytes.count,
              let terminator = bytes[cursor...].firstIndex(of: Self.separator) else {
            throw GitClient.GitClientError.statusParseEarlyEnd
        }
        let field = String(decoding: bytes[cursor..<terminator], as: UTF8.self)
        cursor = terminator + 1
        return field
    }
}
