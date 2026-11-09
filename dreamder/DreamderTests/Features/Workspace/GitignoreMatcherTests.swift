import Foundation
import Testing
@testable import Dreamder

struct GitignoreCase: Sendable, CustomTestStringConvertible {
    let rules: String
    let path: String
    let isDirectory: Bool
    let ignored: Bool

    var testDescription: String {
        "\(rules.debugDescription) vs \(path)\(isDirectory ? "/" : "") -> \(ignored)"
    }

    static func make(_ rules: String, _ path: String, _ ignored: Bool, dir: Bool = false) -> GitignoreCase {
        GitignoreCase(rules: rules, path: path, isDirectory: dir, ignored: ignored)
    }

    static let table: [GitignoreCase] = [
        make("*.log", "a.log", true),
        make("*.log", "dir/a.log", true),
        make("*.log", "a.logx", false),
        make("*.log", "log", false),
        make("*.log", "x.log", true, dir: true),
        make("build/", "build", false),
        make("build/", "build", true, dir: true),
        make("build/", "sub/build", true, dir: true),
        make("build/", "sub/build/a.txt", false),
        make("/build", "build", true),
        make("/build", "sub/build", false),
        make("doc/frotz", "doc/frotz", true),
        make("doc/frotz", "a/doc/frotz", false),
        make("doc/frotz/", "doc/frotz", true, dir: true),
        make("doc/frotz/", "doc/frotz", false),
        make("a/**/b", "a/b", true),
        make("a/**/b", "a/x/b", true),
        make("a/**/b", "a/x/y/b", true),
        make("a/**/b", "ab", false),
        make("a/**/b", "x/a/b", false),
        make("**/foo", "foo", true),
        make("**/foo", "a/foo", true),
        make("**/foo", "a/b/foo", true),
        make("**/foo", "a/b/foo2", false),
        make("**/b/c", "a/b/c", true),
        make("**/b/c", "b/c", true),
        make("**/b/c", "a/bb/c", false),
        make("foo/**", "foo/bar", true),
        make("foo/**", "foo/bar/baz", true),
        make("foo/**", "foo", false),
        make("**", "x", true),
        make("**", "a/b", true),
        make("foo**bar", "fooXbar", true),
        make("foo**bar", "foobar", true),
        make("foo**bar", "foo/bar", false),
        make("a**", "abc", true),
        make("*", "x", true),
        make("*", "a/b", true),
        make("/*", "a", true),
        make("/*", "a/b", false),
        make("dir/*.txt", "dir/a.txt", true),
        make("dir/*.txt", "dir/sub/a.txt", false),
        make("dir/*.txt", "x/dir/a.txt", false),
        make("*.py[co]", "a.pyc", true),
        make("*.py[co]", "a.pyo", true),
        make("*.py[co]", "a.pyd", false),
        make("[a-c]x", "bx", true),
        make("[a-c]x", "dx", false),
        make("[!a-c]x", "dx", true),
        make("[!a-c]x", "bx", false),
        make("[^a-c]x", "dx", true),
        make("[^a-c]x", "ax", false),
        make("?at", "cat", true),
        make("?at", "at", false),
        make("?at", "caat", false),
        make("x/a?b", "x/a/b", false),
        make("x/a?b", "x/aXb", true),
        make("a[/]b", "a/b", false),
        make("\\#file", "#file", true),
        make("\\!important", "!important", true),
        make("#comment", "#comment", false),
        make("# header\nfoo", "foo", true),
        make("foo\\ ", "foo ", true),
        make("foo\\ ", "foo", false),
        make("foo   ", "foo", true),
        make("foo\r", "foo", true),
        make("*.log\n!keep.log", "a.log", true),
        make("*.log\n!keep.log", "keep.log", false),
        make("!keep.log\n*.log", "keep.log", true),
        make("!foo", "foo", false),
        make("[[:digit:]]", "5", true),
        make("[[:digit:]]", "a", false),
        make("[[:alpha:]]", "a", true),
        make("[[:alpha:]]", "1", false),
        make("[[:alnum:]]", "1", true),
        make("[[:alnum:]]", "a", true),
        make("[[:alnum:]]", "-", false),
        make("[[:blank:]]", "\t", true),
        make("[[:blank:]]", "a", false),
        make("[[:cntrl:]]", "\u{01}", true),
        make("[[:cntrl:]]", "a", false),
        make("[[:graph:]]", "a", true),
        make("[[:graph:]]", " ", false),
        make("[[:lower:]]", "a", true),
        make("[[:lower:]]", "A", false),
        make("[[:print:]]", " ", true),
        make("[[:print:]]", "\u{01}", false),
        make("[[:punct:]]", "!", true),
        make("[[:punct:]]", "a", false),
        make("[[:space:]]", "\u{0B}", true),
        make("[[:space:]]", "a", false),
        make("[[:upper:]]", "A", true),
        make("[[:upper:]]", "a", false),
        make("[[:xdigit:]]", "f", true),
        make("[[:xdigit:]]", "g", false),
        make("[[:foo:]]", "a", false),
        make("a\\*b", "a*b", true),
        make("a\\*b", "axb", false),
        make("a[]]b", "a]b", true),
        make("a[]]b", "axb", false),
        make("[a-]", "-", true),
        make("[a-]", "a", true),
        make("[a-]", "b", false),
        make("[\\]]x", "]x", true),
        make("[a-\\z]", "m", true),
        make("[abc", "a", false),
        make("[abc", "[abc", false),
        make("[[:alpha", "a", false),
        make("[[:alpha", "[", false),
        make("[a\\", "a", false),
        make("[a-\\", "a", false),
        make("abc\\", "abc", false),
        make("é*", "éa", true),
        make("*é", "caé", true),
        make("*a*a*a*a*a*a*a*b", String(repeating: "a", count: 60), false),
        make("*a*a*a*a*a*a*a*b", String(repeating: "a", count: 60) + "b", true),
        make("a/b/", "a/b", true, dir: true),
        make("a/b/", "a/b", false),
        make("/", "a", false),
        make("!", "a", false),
        make("", "a", false)
    ]
}

@Suite("GitignoreRuleSet")
struct GitignoreRuleSetTests {
    @Test(arguments: GitignoreCase.table)
    func rulesDecideLikeGit(_ item: GitignoreCase) {
        let ruleSet = GitignoreRuleSet(text: item.rules)
        #expect(ruleSet.isIgnored(relativePath: item.path, isDirectory: item.isDirectory) == item.ignored)
    }

    @Test
    func blankCommentAndBareSeparatorLinesProduceNoRules() {
        #expect(GitignoreRuleSet(text: "\n# note\n   \n/\n!\n!/\n").isEmpty)
        #expect(GitignoreRuleSet(lines: ["#x", "", "/"]).isEmpty)
        #expect(GitignoreRuleSet(lines: ["//", "!//"]).isEmpty)
        #expect(GitignoreRuleSet.empty.isEmpty)
    }

    @Test
    func crlfLineEndingsSplitIntoSeparateRules() {
        let ruleSet = GitignoreRuleSet(text: "a.txt\r\nb.txt\r\n")
        #expect(GitignoreRuleSet(lines: ["c.txt\r"]).isIgnored(relativePath: "c.txt", isDirectory: false))
        #expect(ruleSet.rules.count == 2)
        #expect(ruleSet.isIgnored(relativePath: "a.txt", isDirectory: false))
        #expect(ruleSet.isIgnored(relativePath: "b.txt", isDirectory: false))
    }

    @Test
    func linesInitializerParsesGlobsFromSettings() {
        let ruleSet = GitignoreRuleSet(lines: ["*.tmp", "cache/"])
        #expect(ruleSet.isIgnored(relativePath: "x/a.tmp", isDirectory: false))
        #expect(ruleSet.isIgnored(relativePath: "cache", isDirectory: true))
        #expect(!ruleSet.isIgnored(relativePath: "cache", isDirectory: false))
    }

    @Test
    func ruleKeepsFlagsFromItsLine() throws {
        let negated = try #require(GitignoreRule(line: "!/a/b/"))
        #expect(negated.isNegated)
        #expect(negated.isDirectoryOnly)
        #expect(negated.isAnchored)
        let plain = try #require(GitignoreRule(line: "name"))
        #expect(!plain.isNegated)
        #expect(!plain.isDirectoryOnly)
        #expect(!plain.isAnchored)
        #expect(plain == GitignoreRule(line: "name"))
    }
}

@Suite("GitignoreMatcher")
struct GitignoreMatcherTests {
    private func write(_ root: URL, _ path: String, _ text: String = "") throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test(arguments: ["new_folder/", "new_folder", "*"])
    func directoryIsIgnoredByEquivalentIntelliJGitIgnoreEntries(_ content: String) throws {
        try withTempDir { root in
            try write(root, ".gitignore", content)
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(matcher.isIgnored(root.appending(path: "new_folder"), isDirectory: true))
        }
    }

    @Test(arguments: ["", "!new_folder/", "!new_folder", "*\n!new_folder\n!new_folder/**"])
    func directoryIsNotIgnoredWhenNothingOrANegationMatches(_ content: String) throws {
        try withTempDir { root in
            if !content.isEmpty { try write(root, ".gitignore", content) }
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(!matcher.isIgnored(root.appending(path: "new_folder"), isDirectory: true))
        }
    }

    @Test
    func nestedGitignoreAppliesToItsSubtreeAndOverridesParents() throws {
        try withTempDir { root in
            try write(root, ".gitignore", "*.log\n")
            try write(root, "sub/.gitignore", "!keep.log\nlocal.txt\n/anchored.txt\n")
            let matcher = GitignoreMatcher(rootURL: root)

            #expect(matcher.isIgnored(root.appending(path: "a.log"), isDirectory: false))
            #expect(matcher.isIgnored(root.appending(path: "sub/x.log"), isDirectory: false))
            #expect(!matcher.isIgnored(root.appending(path: "sub/keep.log"), isDirectory: false))
            #expect(matcher.isIgnored(root.appending(path: "sub/local.txt"), isDirectory: false))
            #expect(matcher.isIgnored(root.appending(path: "sub/deep/local.txt"), isDirectory: false))
            #expect(!matcher.isIgnored(root.appending(path: "other/local.txt"), isDirectory: false))
            #expect(matcher.isIgnored(root.appending(path: "sub/anchored.txt"), isDirectory: false))
            #expect(!matcher.isIgnored(root.appending(path: "sub/deep/anchored.txt"), isDirectory: false))
        }
    }

    @Test
    func ignoredDirectoryCannotBeReincludedThroughItsChildren() throws {
        try withTempDir { root in
            try write(root, ".gitignore", "build/\n!build/keep.txt\n")
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(matcher.isIgnored(root.appending(path: "build/keep.txt"), isDirectory: false))
            #expect(matcher.isIgnored(root.appending(path: "build/a/b/c.txt"), isDirectory: false))
            #expect(!matcher.isIgnored(root.appending(path: "src/build.txt"), isDirectory: false))
        }
    }

    @Test
    func gitInfoExcludeHasLowerPrecedenceThanGitignore() throws {
        try withTempDir { root in
            try write(root, ".git/info/exclude", "secret.txt\nlocal/\n")
            try write(root, ".gitignore", "!secret.txt\n")
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(!matcher.isIgnored(root.appending(path: "secret.txt"), isDirectory: false))
            #expect(matcher.isIgnored(root.appending(path: "local"), isDirectory: true))
            #expect(matcher.isIgnored(root.appending(path: "a/local/b.txt"), isDirectory: false))
        }
    }

    @Test
    func pathsOutsideTheRootAndTheRootItselfAreNeverIgnored() throws {
        try withTempDir { root in
            try write(root, ".gitignore", "*\n")
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(!matcher.isIgnored(root, isDirectory: true))
            #expect(!matcher.isIgnored(URL(fileURLWithPath: "/somewhere/else/a.txt"), isDirectory: false))
            #expect(!matcher.isIgnored(relativePath: "", isDirectory: false))
            #expect(matcher.relativePath(of: root.appending(path: "a/b.txt")) == "a/b.txt")
            #expect(matcher.relativePath(of: root) == "")
            #expect(matcher.relativePath(of: URL(fileURLWithPath: "/somewhere/else")) == nil)
        }
    }

    @Test
    func rulesAreCachedUntilReset() throws {
        try withTempDir { root in
            try write(root, ".gitignore", "a.txt\n")
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(matcher.isIgnored(relativePath: "a.txt", isDirectory: false))

            try write(root, ".gitignore", "b.txt\n")
            #expect(matcher.isIgnored(relativePath: "a.txt", isDirectory: false))
            #expect(!matcher.isIgnored(relativePath: "b.txt", isDirectory: false))

            matcher.reset()
            #expect(!matcher.isIgnored(relativePath: "a.txt", isDirectory: false))
            #expect(matcher.isIgnored(relativePath: "b.txt", isDirectory: false))
        }
    }

    @Test
    func chainDescendsThroughDirectoriesWithOwnIgnoreFiles() throws {
        try withTempDir { root in
            try write(root, "a/.gitignore", "only-in-a.txt\n")
            try write(root, "a/b/file.txt")
            let matcher = GitignoreMatcher(rootURL: root)

            let rootChain = matcher.rootChain()
            #expect(rootChain.levels.isEmpty)
            #expect(!rootChain.isIgnored(relativePath: "a/only-in-a.txt", isDirectory: false))

            let chain = matcher.descend(rootChain, into: "a")
            #expect(chain.levels.count == 1)
            #expect(chain.isIgnored(relativePath: "a/only-in-a.txt", isDirectory: false))
            #expect(chain.isIgnored(relativePath: "a/b/only-in-a.txt", isDirectory: false))
            #expect(!chain.isIgnored(relativePath: "only-in-a.txt", isDirectory: false))

            let sameChain = matcher.descend(chain, into: "a/b")
            #expect(sameChain.levels.count == 1)
        }
    }

    @Test
    func unreadableOrMissingIgnoreFilesAreTreatedAsEmpty() throws {
        try withTempDir { root in
            try FileManager.default.createDirectory(
                at: root.appending(path: ".gitignore"),
                withIntermediateDirectories: true
            )
            let matcher = GitignoreMatcher(rootURL: root)
            #expect(!matcher.isIgnored(relativePath: "anything", isDirectory: false))
        }
    }
}
