import Foundation
import Observation
import SwiftUI

nonisolated struct GitConsoleEntry: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date: Date
    let directory: String
    let command: String
    let errorLines: [String]

    @MainActor
    var header: String {
        "\(GitConsoleEntry.timeFormatter.string(from: date)): [\(directory)] git \(command)"
    }

    @MainActor
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

@Observable
@MainActor
final class GitConsoleLog {
    private(set) var entries: [GitConsoleEntry] = []
    var isDismissed = false

    private static var logs: [String: GitConsoleLog] = [:]
    nonisolated static let maximumEntries = 1000

    nonisolated static let changingCommands: Set<String> = [
        "add", "am", "branch", "checkout", "cherry-pick", "clean", "clone", "commit", "fetch", "init",
        "merge", "mv", "pull", "push", "rebase", "remote", "reset", "restore", "revert", "rm",
        "stash", "switch", "tag", "worktree"
    ]

    nonisolated static let readOnlyBranchFlags: Set<String> = ["--list", "-l", "--show-current", "-a", "-r", "--format", "-v", "-vv"]

    static func log(for directory: URL) -> GitConsoleLog {
        var key = directory.standardizedFileURL.path(percentEncoded: false)
        while key.count > 1, key.hasSuffix("/") {
            key.removeLast()
        }
        if let log = logs[key] {
            return log
        }
        let log = GitConsoleLog()
        logs[key] = log
        return log
    }

    nonisolated static func subcommand(of command: String) -> String? {
        let tokens = command.split(separator: " ").map(String.init)
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "-c" || token == "-C" {
                index += 2
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            return token
        }
        return nil
    }

    nonisolated static func changesRepository(_ command: String) -> Bool {
        guard let subcommand = subcommand(of: command), changingCommands.contains(subcommand) else {
            return false
        }
        let arguments = command.split(separator: " ").map(String.init)
        if subcommand == "branch" || subcommand == "tag" {
            let flags = arguments.drop { $0 != subcommand }.dropFirst()
            if flags.isEmpty || flags.contains(where: { flag in readOnlyBranchFlags.contains(where: { flag.hasPrefix($0) }) }) {
                return false
            }
        }
        if subcommand == "remote" {
            let rest = arguments.drop { $0 != "remote" }.dropFirst()
            return rest.first.map { ["add", "remove", "rename", "set-url", "prune"].contains($0) } ?? false
        }
        if subcommand == "stash" {
            let rest = arguments.drop { $0 != "stash" }.dropFirst()
            return rest.first.map { $0 != "list" && $0 != "show" } ?? true
        }
        if subcommand == "worktree" {
            let rest = arguments.drop { $0 != "worktree" }.dropFirst()
            return rest.first.map { $0 != "list" } ?? false
        }
        return true
    }

    nonisolated static func errorLines(in output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                line.hasPrefix("fatal:") || line.hasPrefix("error:") || line.hasPrefix("CONFLICT")
                    || line.hasPrefix("! [rejected]") || line.hasPrefix("hint:")
            }
    }

    func record(command: String, directory: URL, output: String, date: Date = Date()) {
        let entry = GitConsoleEntry(
            date: date,
            directory: directory.standardizedFileURL.path(percentEncoded: false),
            command: command,
            errorLines: Self.errorLines(in: output)
        )
        entries.append(entry)
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        isDismissed = false
    }

    func clear() {
        entries.removeAll()
    }
}

struct GitConsoleView: View {
    let log: GitConsoleLog

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.entries) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.header)
                                .foregroundStyle(Islands.foreground)
                            ForEach(Array(entry.errorLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .foregroundStyle(Islands.errorForeground)
                            }
                        }
                        .id(entry.id)
                    }
                }
                .font(Islands.codeFont)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .onChange(of: log.entries.count) { _, _ in
                if let last = log.entries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct GitConsoleTab: View {
    let log: GitConsoleLog
    @Binding var isSelected: Bool

    var body: some View {
        if !log.entries.isEmpty, !log.isDismissed {
            ToolWindowTab(
                title: "Console",
                isSelected: isSelected,
                onClose: {
                    log.isDismissed = true
                    isSelected = false
                },
                action: {
                    isSelected = true
                }
            )
        }
    }
}
