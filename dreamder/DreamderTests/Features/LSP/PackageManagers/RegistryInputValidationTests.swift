import Foundation
import Testing
@testable import Dreamder

nonisolated private func unsafePayload<Result>(_ body: () throws -> Result) -> String? {
    do {
        _ = try body()
        return nil
    } catch PackageManagerError.unsafeValue(let value) {
        return value
    } catch {
        return nil
    }
}

nonisolated private enum Samples {
    static let safeComponents = [
        "tool", "a.b-c", "1.2.3", "@scope", "x+y", "~home", "name-", "a..b",
        "...", "UPPER", "0"
    ]

    static let unsafeComponents = [
        "", "../x", "../../x", "a/b", "/abs", "a/", "a\u{0}b", "-rf", "-", "a b", " a", "a ", "a;rm -rf ~",
        "$(touch x)", "`id`", "a\nb", "a\tb", "a'b", "a\"b", "a%20b", "%2e%2e", "a:b", "a=b", "a^b", "a,b", "a*b",
        "a?b", "a\\b", "a|b", "a&b", "a>b", "a<b", "a(b)", "a[b]", "a{b}", "a#b", "a!b",
        "é", "\u{0430}bc", "\u{2025}", "\u{FF0E}\u{FF0E}", "a\u{200B}b", "名前", "😀"
    ]

    static let safeArguments = [
        "^1.2.3", "a,b", "pkg/sub", "@scope/pkg", "1.0+build", "x~y", "./x", "a/b/c", "UPPER", "x,y,z", "1.2.3", "a..b"
    ]

    static let unsafeArguments = [
        "", "-x", "--flag", "a b", " a", "a;b", "$x", "$(id)", "`id`", "'a'", "\"a\"", "a:b", "a=b", "[x]", "a\nb",
        "..", "../x", "../../x", "a/../b", "a/..", "/abs", "/", "a\u{0}b", "(x)", "a|b", "a&b",
        "a\\b", "a*b", "a%b", "a#b", "é", "😀", "{a}", "a>b", "a<b", "a!b"
    ]
}

@Suite
struct RegistryInputValidationComponentTests {
    @Test(arguments: Samples.safeComponents)
    func acceptsSafeComponentsUnchanged(value: String) throws {
        #expect(try RegistryInputValidation.component(value) == value)
    }

    @Test(arguments: Samples.unsafeComponents)
    func rejectsUnsafeComponentsAndReportsTheValue(value: String) {
        #expect(unsafePayload { try RegistryInputValidation.component(value) } == value)
    }
}

@Suite
struct RegistryInputValidationChildTests {
    @Test(arguments: ["tool", "a.b", "1.2.3", "@scope", "...", "x+y", "~home", "name-"])
    func safeNamesResolveStrictlyInsideTheRoot(name: String) throws {
        try withTempDir { directory in
            let root = directory.appending(path: "Language Servers", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            let child = try RegistryInputValidation.child(of: root, named: name)

            let rootPath = root.standardizedFileURL.path
            #expect(child.standardizedFileURL.path == rootPath + "/" + name)
            #expect(child.standardizedFileURL.path.hasPrefix(rootPath + "/"))
        }
    }

    @Test
    func aTrailingSlashRootStillYieldsAStrictChild() throws {
        try withTempDir { directory in
            let root = URL(
                filePath: directory.path(percentEncoded: false) + "/with space/",
                directoryHint: .isDirectory
            )

            let child = try RegistryInputValidation.child(of: root, named: "tool")

            #expect(child.standardizedFileURL.path == root.standardizedFileURL.path + "/tool")
        }
    }

    @Test(arguments: Samples.unsafeComponents)
    func unsafeNamesThrowBeforeAnythingIsResolved(name: String) throws {
        try withTempDir { directory in
            let root = directory.appending(path: "root", directoryHint: .isDirectory)
            #expect(unsafePayload { try RegistryInputValidation.child(of: root, named: name) } == name)
        }
    }

    @Test(arguments: [".", ".."])
    func dotNamesAreRejectedBecauseTheyEscapeOrEqualTheRoot(name: String) throws {
        try withTempDir { directory in
            let root = directory.appending(path: "root", directoryHint: .isDirectory)
            let sibling = directory.appending(path: "sibling", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            let sentinel = sibling.appending(path: "sentinel.txt")
            try Data("keep".utf8).write(to: sentinel)

            #expect(unsafePayload { try RegistryInputValidation.child(of: root, named: name) } == name)
            #expect(FileManager.default.fileExists(atPath: sentinel.path(percentEncoded: false)))
        }
    }
}

@Suite
struct RegistryInputValidationArgumentTests {
    @Test(arguments: Samples.safeArguments)
    func acceptsSafeArgumentsUnchanged(value: String) throws {
        #expect(try RegistryInputValidation.argument(value) == value)
    }

    @Test(arguments: Samples.unsafeArguments)
    func rejectsUnsafeArgumentsAndReportsTheValue(value: String) {
        #expect(unsafePayload { try RegistryInputValidation.argument(value) } == value)
    }
}

@Suite
struct RegistryInputValidationHTTPSURLTests {
    @Test(arguments: [
        "https://github.com/owner/repo.git",
        "https://example.com/a/b",
        "https://host:8080/x",
        "https://user@host.example/x",
        "https://a.b/~u/x^y,z",
        "https://github.com/owner/repo"
    ])
    func acceptsPlainHTTPSURLs(value: String) throws {
        #expect(try RegistryInputValidation.httpsURL(value) == value)
    }

    @Test(arguments: [
        "",
        "http://github.com/owner/repo",
        "ftp://example.com/x",
        "ext::sh -c x",
        "ext::sh -c touch% x",
        "https:///x",
        "https://",
        "https://a b/x",
        "https://host/a b",
        "-https://example.com/x",
        "-evil",
        "file:///etc/passwd",
        "HTTPS://github.com/x",
        "https://github.com/a?x=1",
        "https://github.com/a;b",
        "https://github.com/$(id)",
        "https://github.com/a%20b",
        "https://github.com/`id`",
        "https://github.com/a\nb",
        "https://github.com/a\u{0}b",
        "git@github.com:owner/repo.git"
    ])
    func rejectsEverythingElse(value: String) {
        #expect(unsafePayload { try RegistryInputValidation.httpsURL(value) } == value)
    }
}

@Suite
struct RegistryInputValidationBuildCommandTests {
    @Test(arguments: ["make", "cmake", "cargo", "npm", "yarn", "pnpm", "go", "dotnet", "swift", "zig"])
    func acceptsEveryAllowlistedExecutable(executable: String) throws {
        #expect(try RegistryInputValidation.buildCommand(executable) == [[executable]])
        let withArguments = try RegistryInputValidation.buildCommand("\(executable) build --release")
        #expect(withArguments == [[executable, "build", "--release"]])
    }

    @Test
    func splitsLinesAndTokensOnWhitespaceSkippingBlankLines() throws {
        let command = "  make   -j4\tinstall  \n\n   \nnpm run build:prod\r\ngo build -o bin/x ./cmd/x\n"
        #expect(try RegistryInputValidation.buildCommand(command) == [
            ["make", "-j4", "install"],
            ["npm", "run", "build:prod"],
            ["go", "build", "-o", "bin/x", "./cmd/x"]
        ])
    }

    @Test
    func allowsEqualsColonCommaCaretAndLeadingDashTokens() throws {
        #expect(try RegistryInputValidation.buildCommand("cmake -DA=1 --target=x86:y a,b ^c ..") == [
            ["cmake", "-DA=1", "--target=x86:y", "a,b", "^c", ".."]
        ])
    }

    @Test(arguments: [
        "make; rm -rf ~",
        "make && ls",
        "make || ls",
        "make $(id)",
        "make `id`",
        "make > out",
        "make < in",
        "make | sh",
        "make 'x'",
        "make \"x\"",
        "make x\\y",
        "make a(b)",
        "make $HOME",
        "make a\u{0}b",
        "make *",
        "make ~/x%",
        "make x;"
    ])
    func rejectsUnsafeTokensReportingTheOffendingLine(line: String) {
        #expect(unsafePayload { try RegistryInputValidation.buildCommand(line) } == line)
    }

    @Test(arguments: [
        "sh -c x", "rm -rf /", "bash", "./make", "/usr/bin/make", "curl https://x", "git status", "python3 x",
        "MAKE", "make2", "-rf", "../make"
    ])
    func rejectsExecutablesOutsideTheBuildAllowlist(line: String) {
        #expect(unsafePayload { try RegistryInputValidation.buildCommand(line) } == line)
    }

    @Test
    func aDeniedExecutableOnALaterLineRejectsTheWholeCommand() {
        #expect(unsafePayload { try RegistryInputValidation.buildCommand("make\nrm -rf ~\nnpm install") } == "rm -rf ~")
        let payload = unsafePayload { try RegistryInputValidation.buildCommand("make\nnpm install; id") }
        #expect(payload == "npm install; id")
    }

    @Test
    func aDeniedLineIsReportedWithoutItsLineTerminator() {
        #expect(unsafePayload { try RegistryInputValidation.buildCommand("  make ; x \n") } == "  make ; x ")
    }

    @Test(arguments: ["", " ", "   \n\t\n", "\n\n", "\r\n"])
    func rejectsCommandsWithoutAnyExecutable(command: String) {
        #expect(unsafePayload { try RegistryInputValidation.buildCommand(command) } == command)
    }
}

@Suite
struct RegistryInputValidationExecutableTests {
    @Test(arguments: [
        "npm", "cargo", "go", "git", "python", "python3", "pip3", "tar", "gunzip",
        "make", "cmake", "yarn", "pnpm", "dotnet", "swift", "zig",
        "/bin/sh", "/", "/usr/bin/python3", "/tmp/dir with space/venv/bin/pip"
    ])
    func allowsAllowlistedBareNamesAndAbsolutePaths(executable: String) {
        #expect(RegistryInputValidation.isAllowedExecutable(executable))
    }

    @Test(arguments: [
        "", "sh", "bash", "zsh", "rm", "curl", "wget", "env", "-rf", "./make", "../npm", "bin/npm", "NPM", " npm",
        "npm ", "~/x", "npm\u{0}", "node", "pip"
    ])
    func deniesEverythingElse(executable: String) {
        #expect(!RegistryInputValidation.isAllowedExecutable(executable))
    }

    @Test
    func theAllowlistsAreExactlyTheDocumentedSets() {
        #expect(RegistryInputValidation.packageManagerExecutables == [
            "npm", "cargo", "go", "git", "python", "python3", "pip3", "tar", "gunzip"
        ])
        #expect(RegistryInputValidation.buildExecutables == [
            "make", "cmake", "cargo", "npm", "yarn", "pnpm", "go", "dotnet", "swift", "zig"
        ])
    }
}

@MainActor
@Suite
struct PackageManagerUnsafeValueErrorTests {
    @Test
    func carriesTheOffendingValueInItsDescription() {
        let error = PackageManagerError.unsafeValue("a;rm -rf ~")
        #expect(error.errorDescription == "The package registry contained a value that is not allowed: a;rm -rf ~")
        #expect(error.failureReason == nil)
        #expect(errorKind(error) == "PackageManagerError.unsafeValue")
    }

    @Test
    func validationThrowsTheSameErrorKind() {
        let error = thrownError { try RegistryInputValidation.component("-rf") }
        #expect(errorKind(error) == "PackageManagerError.unsafeValue")
        #expect(error?.localizedDescription == "The package registry contained a value that is not allowed: -rf")
    }
}
