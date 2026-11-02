import Foundation
import Testing
@testable import Dreamder

@Suite
struct GitConsoleLogTests {
    @Test(arguments: [
        "commit --message=\"x\"",
        "-c core.quotePath=false checkout \"main\"",
        "branch -D \"old\"",
        "branch -m \"a\" \"b\"",
        "tag -d \"v1\"",
        "push \"origin\" --delete \"x\"",
        "merge --no-edit \"feature\"",
        "fetch --all --prune",
        "stash",
        "stash pop",
        "remote add origin url",
        "worktree add ../wt main",
        "restore --source=HEAD --staged --worktree -- 'a.txt'"
    ])
    func changingCommandsAreLogged(command: String) {
        #expect(GitConsoleLog.changesRepository(command))
    }

    @Test(arguments: [
        "status -z --porcelain=2 -u",
        "log --date-order -z -n 10",
        "diff --name-status 'HEAD'",
        "rev-parse --is-inside-work-tree",
        "branch --format \"%(refname:short)\"",
        "branch --show-current",
        "branch",
        "tag",
        "show 'HEAD:a.txt'",
        "stash list",
        "remote -v",
        "worktree list",
        "for-each-ref refs/tags",
        "-c core.quotePath=false ls-files --others"
    ])
    func readOnlyCommandsAreNotLogged(command: String) {
        #expect(GitConsoleLog.changesRepository(command) == false)
    }

    @Test
    func subcommandSkipsGlobalOptions() {
        #expect(GitConsoleLog.subcommand(of: "-c core.quotePath=false -C dir diff --stat") == "diff")
        #expect(GitConsoleLog.subcommand(of: "--no-pager log") == "log")
        #expect(GitConsoleLog.subcommand(of: "") == nil)
    }

    @Test
    func errorLinesKeepOnlyGitFailures() {
        let output = """
        Auto-merging a.txt
        CONFLICT (content): Merge conflict in a.txt
        Automatic merge failed; fix conflicts and then commit the result.
        error: could not apply 1234
        hint: resolve all conflicts manually
        """
        #expect(GitConsoleLog.errorLines(in: output) == [
            "CONFLICT (content): Merge conflict in a.txt",
            "error: could not apply 1234",
            "hint: resolve all conflicts manually"
        ])
    }

    @MainActor
    @Test
    func recordingFormatsHeaderAndCapsHistory() {
        let log = GitConsoleLog()
        let date = Date(timeIntervalSince1970: 0)
        log.record(command: "checkout main", directory: URL(fileURLWithPath: "/tmp/repo"), output: "", date: date)

        let entry = try? #require(log.entries.first)
        let time = GitConsoleEntry.timeFormatter.string(from: date)
        #expect(entry?.header == "\(time): [/tmp/repo] git checkout main")
        #expect(entry?.errorLines.isEmpty == true)

        for index in 0..<(GitConsoleLog.maximumEntries + 5) {
            log.record(command: "commit \(index)", directory: URL(fileURLWithPath: "/tmp/repo"), output: "")
        }
        #expect(log.entries.count == GitConsoleLog.maximumEntries)
        #expect(log.entries.last?.command == "commit \(GitConsoleLog.maximumEntries + 4)")
    }

    @Test
    func logsAreSharedPerRepository() {
        let first = GitConsoleLog.log(for: URL(fileURLWithPath: "/tmp/repo-a"))
        let second = GitConsoleLog.log(for: URL(fileURLWithPath: "/tmp/repo-a/"))
        let other = GitConsoleLog.log(for: URL(fileURLWithPath: "/tmp/repo-b"))
        #expect(first === second)
        #expect(first !== other)
    }
}
