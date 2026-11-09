import Foundation
import Synchronization
import Testing
@testable import Dreamder

private typealias Fixture = TaskDiscoveryFixture

private final class ProbeRecorder: Sendable {
    private let mainThreadFlags = Mutex<[Bool]>([])

    func record() {
        mainThreadFlags.withLock { $0.append(Thread.isMainThread) }
    }

    var flags: [Bool] {
        mainThreadFlags.withLock { $0 }
    }
}

@Suite struct TaskDiscoveryModelTests {
    @Test(arguments: [
        (TaskSourceKind.npm, "npm"),
        (TaskSourceKind.cargo, "Cargo"),
        (TaskSourceKind.go, "Go"),
        (TaskSourceKind.python, "Python"),
        (TaskSourceKind.swiftPackage, "Swift Package"),
        (TaskSourceKind.make, "Makefile")
    ])
    func kindTitles(kind: TaskSourceKind, title: String) {
        #expect(kind.title == title)
    }

    @Test func kindOrder() {
        #expect(TaskSourceKind.allCases == [.npm, .cargo, .go, .python, .swiftPackage, .make])
    }

    @Test func rootGroupIdentityAndTitle() {
        let group = DiscoveredTaskGroup(kind: .cargo, directory: "", manifest: "Cargo.toml", tasks: [])
        #expect(group.id == "cargo:")
        #expect(group.title == "Cargo")
    }

    @Test func nestedGroupIdentityAndTitle() {
        let group = DiscoveredTaskGroup(kind: .swiftPackage, directory: "libs/core", manifest: "libs/core/Package.swift", tasks: [])
        #expect(group.id == "swiftPackage:libs/core")
        #expect(group.title == "Swift Package — libs/core")
    }
}

@Suite struct NpmTaskDiscoveryTests {
    private static let manifest = #"{"scripts":{"dev":"vite","build":"vite build","skip":1,"nested":{"a":"b"}}}"#

    @Test(arguments: [
        ([String](), "npm"),
        (["package-lock.json"], "npm"),
        (["pnpm-lock.yaml"], "pnpm"),
        (["yarn.lock"], "yarn"),
        (["bun.lockb"], "bun"),
        (["bun.lock"], "bun"),
        (["yarn.lock", "pnpm-lock.yaml"], "pnpm"),
        (["bun.lock", "yarn.lock"], "yarn")
    ])
    func packageManagerByLockfile(lockfiles: [String], packageManager: String) async throws {
        var files = ["package.json": Self.manifest]
        for lockfile in lockfiles {
            files[lockfile] = ""
        }
        let groups = try await Fixture.discover(files)
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "npm:",
            manifest: "package.json",
            commands: ["\(packageManager) run build", "\(packageManager) run dev"]
        ))
        #expect(groups.first?.tasks.map(\.workingDirectory) == ["", ""])
        #expect(groups.first?.tasks.map(\.kind) == [.npm, .npm])
    }

    @Test func lockfileAtRootAppliesToSubdirectoryPackage() async throws {
        let groups = try await Fixture.discover([
            "pnpm-lock.yaml": "",
            "web/package.json": Self.manifest
        ])
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "npm:web",
            manifest: "web/package.json",
            commands: ["pnpm run build", "pnpm run dev"],
            directory: "web"
        ))
        #expect(groups.first?.tasks.map(\.workingDirectory) == ["web", "web"])
        #expect(groups.first?.directory == "web")
    }

    @Test func nearestLockfileWinsOverAncestors() async throws {
        let groups = try await Fixture.discover([
            "pnpm-lock.yaml": "",
            "web/yarn.lock": "",
            "web/package.json": Self.manifest,
            "web/app/package.json": Self.manifest,
            "bun.lock": "",
            "other/package.json": Self.manifest
        ])
        #expect(groups.map(\.id) == ["npm:other", "npm:web", "npm:web/app"])
        #expect(groups.map { $0.tasks.first?.command } == ["pnpm run build", "yarn run build", "yarn run build"])
    }

    @Test func nodeModulesPackagesAreIgnored() async throws {
        let groups = try await Fixture.discover([
            "package.json": Self.manifest,
            "node_modules/dep/package.json": Self.manifest,
            "web/node_modules/dep/package.json": Self.manifest
        ])
        #expect(groups.map(\.id) == ["npm:"])
    }

    @Test(arguments: [
        "",
        "{not json",
        "[]",
        "{}",
        #"{"scripts":{}}"#,
        #"{"scripts":[]}"#,
        #"{"scripts":"build"}"#,
        #"{"scripts":{"a":1,"b":null,"c":["x"]}}"#
    ])
    func malformedOrEmptyScriptsProduceNoGroup(content: String) async throws {
        #expect(try await Fixture.discover(["package.json": content]).isEmpty)
    }

    @Test func unreadablePackageJsonIsSkipped() async throws {
        try await withTempDir { root in
            try Fixture.writeTree(["package.json": Self.manifest], in: root)
            let path = root.appending(path: "package.json", directoryHint: .notDirectory).path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
            let groups = await TaskDiscovery(rootURL: root).discover()
            #expect(groups.isEmpty)
        }
    }
}

@Suite struct CargoTaskDiscoveryTests {
    private static let packageCommands = ["cargo run", "cargo test", "cargo build"]
    private static let workspaceCommands = ["cargo build --workspace", "cargo test --workspace"]

    @Test func packageManifest() async throws {
        let groups = try await Fixture.discover(["Cargo.toml": "[package]\nname = \"app\"\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(id: "cargo:", manifest: "Cargo.toml", commands: Self.packageCommands))
        #expect(groups.first?.tasks.map(\.workingDirectory) == ["", "", ""])
    }

    @Test func virtualWorkspaceManifest() async throws {
        let groups = try await Fixture.discover(["Cargo.toml": "[workspace]\nmembers = [\"crates/*\"]\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(id: "cargo:", manifest: "Cargo.toml", commands: Self.workspaceCommands))
    }

    @Test func packageWithWorkspaceYieldsBothSetsPackageFirst() async throws {
        let groups = try await Fixture.discover(["Cargo.toml": "[workspace]\nmembers = []\n\n[package]\nname = \"app\"\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "cargo:",
            manifest: "Cargo.toml",
            commands: Self.packageCommands + Self.workspaceCommands
        ))
    }

    @Test(arguments: [
        "# [package]\n",
        "[dependencies]\nserde = \"1\"\n",
        "[workspace.dependencies]\nserde = \"1\"\n",
        "[package.metadata]\n",
        "[ package ]\n",
        ""
    ])
    func manifestsWithoutPackageOrWorkspaceProduceNoGroup(content: String) async throws {
        #expect(try await Fixture.discover(["Cargo.toml": content]).isEmpty)
    }

    @Test func headersTolerateCommentsAndWhitespace() async throws {
        let groups = try await Fixture.discover(["Cargo.toml": "  [package]   # the crate\r\nname = \"x\"\r\n"])
        #expect(groups.map(\.id) == ["cargo:"])
        #expect(groups.first?.tasks.map(\.command) == Self.packageCommands)
    }

    @Test func nestedWorkspacesAndMembersEachProduceGroup() async throws {
        let groups = try await Fixture.discover([
            "Cargo.toml": "[workspace]\nmembers = [\"crates/*\"]\n",
            "crates/a/Cargo.toml": "[package]\nname = \"a\"\n",
            "crates/b/Cargo.toml": "[package]\nname = \"b\"\n",
            "tools/ws/Cargo.toml": "[workspace]\nmembers = [\"members/*\"]\n",
            "tools/ws/members/x/Cargo.toml": "[package]\nname = \"x\"\n"
        ])
        #expect(groups.map(\.id) == [
            "cargo:",
            "cargo:crates/a",
            "cargo:crates/b",
            "cargo:tools/ws",
            "cargo:tools/ws/members/x"
        ])
        let expected = Fixture.lines(id: "cargo:", manifest: "Cargo.toml", commands: Self.workspaceCommands)
            + Fixture.lines(id: "cargo:crates/a", manifest: "crates/a/Cargo.toml", commands: Self.packageCommands, directory: "crates/a")
            + Fixture.lines(id: "cargo:crates/b", manifest: "crates/b/Cargo.toml", commands: Self.packageCommands, directory: "crates/b")
            + Fixture.lines(id: "cargo:tools/ws", manifest: "tools/ws/Cargo.toml", commands: Self.workspaceCommands, directory: "tools/ws")
            + Fixture.lines(
                id: "cargo:tools/ws/members/x",
                manifest: "tools/ws/members/x/Cargo.toml",
                commands: Self.packageCommands,
                directory: "tools/ws/members/x"
            )
        #expect(Fixture.summary(groups) == expected)
        #expect(groups[1].tasks.map(\.workingDirectory) == ["crates/a", "crates/a", "crates/a"])
    }

    @Test func invalidUtf8ManifestIsSkipped() async throws {
        try await withTempDir { root in
            try Fixture.writeFile("Cargo.toml", Data([0xFF, 0xFE, 0xFD]), in: root)
            #expect(await TaskDiscovery(rootURL: root).discover().isEmpty)
        }
    }
}

@Suite struct GoAndSwiftPackageTaskDiscoveryTests {
    @Test func goModule() async throws {
        let groups = try await Fixture.discover(["go.mod": "module example.com/app\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(id: "go:", manifest: "go.mod", commands: ["go run .", "go test ./..."]))
        #expect(groups.first?.title == "Go")
    }

    @Test func nestedGoModule() async throws {
        let groups = try await Fixture.discover(["svc/api/go.mod": "module api\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "go:svc/api",
            manifest: "svc/api/go.mod",
            commands: ["go run .", "go test ./..."],
            directory: "svc/api"
        ))
        #expect(groups.first?.title == "Go — svc/api")
    }

    @Test func swiftPackage() async throws {
        let groups = try await Fixture.discover(["Package.swift": "// swift-tools-version: 6.0\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "swiftPackage:",
            manifest: "Package.swift",
            commands: ["swift build", "swift test"]
        ))
    }

    @Test func nestedSwiftPackage() async throws {
        let groups = try await Fixture.discover(["Packages/Core/Package.swift": ""])
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "swiftPackage:Packages/Core",
            manifest: "Packages/Core/Package.swift",
            commands: ["swift build", "swift test"],
            directory: "Packages/Core"
        ))
    }
}

@Suite struct PythonTaskDiscoveryTests {
    @Test func testsDirectoryWithPythonFileWithoutVirtualEnvironment() async throws {
        let groups = try await Fixture.discover(["tests/test_app.py": ""])
        #expect(Fixture.summary(groups) == ["python: [tests] pytest => pytest"])
        #expect(groups.first?.tasks.map(\.workingDirectory) == [""])
        #expect(groups.first?.tasks.map(\.kind) == [.python])
    }

    @Test func testsDirectoryWithVirtualEnvironment() async throws {
        let groups = try await Fixture.discover([
            ".venv/bin/python": "",
            "tests/test_app.py": ""
        ])
        #expect(Fixture.summary(groups) == ["python: [tests] pytest => .venv/bin/python -m pytest"])
    }

    @Test func mainScriptWithoutVirtualEnvironment() async throws {
        let groups = try await Fixture.discover(["main.py": "print(1)\n"])
        #expect(Fixture.summary(groups) == ["python: [main.py] python main.py => python3 main.py"])
    }

    @Test func mainScriptWithVirtualEnvironment() async throws {
        let groups = try await Fixture.discover([
            ".venv/bin/python": "",
            "main.py": "print(1)\n"
        ])
        #expect(Fixture.summary(groups) == ["python: [main.py] python main.py => .venv/bin/python main.py"])
    }

    @Test func pyprojectIsTheManifestAndPytestComesFirst() async throws {
        let groups = try await Fixture.discover([
            "pyproject.toml": "[project]\n",
            "main.py": "",
            "tests/test_a.py": ""
        ])
        #expect(Fixture.summary(groups) == [
            "python: [pyproject.toml] pytest => pytest",
            "python: [pyproject.toml] python main.py => python3 main.py"
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.tasks.map(\.manifest) == ["tests", "main.py"])
    }

    @Test func pytestIniIsTheManifestWhenNoPyproject() async throws {
        let groups = try await Fixture.discover([
            "pytest.ini": "",
            "main.py": ""
        ])
        #expect(Fixture.summary(groups) == ["python: [pytest.ini] python main.py => python3 main.py"])
    }

    @Test(arguments: [
        ["tests/README.md": "", "tests/conftest.txt": ""],
        ["tests/unit/test_a.py": ""],
        ["tests": "plain file"],
        ["pyproject.toml": ""],
        ["pytest.ini": "", "setup.cfg": ""],
        ["src/app.py": ""]
    ] as [[String: String]])
    func directoriesWithoutPythonEntryPointsProduceNoGroup(files: [String: String]) async throws {
        #expect(try await Fixture.discover(files).isEmpty)
    }

    @Test func unreadableTestsDirectoryProducesNoGroup() async throws {
        try await withTempDir { root in
            try Fixture.writeFile("tests/test_app.py", Data(), in: root)
            let testsPath = root.appending(path: "tests").path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: testsPath)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: testsPath) }

            let groups = await TaskDiscovery(rootURL: root).discover()

            #expect(groups.isEmpty)
        }
    }

    @Test func nestedDirectoryUsesItsOwnVirtualEnvironmentAndSuffix() async throws {
        let groups = try await Fixture.discover([
            "main.py": "",
            "app/.venv/bin/python": "",
            "app/main.py": "",
            "app/tests/test_app.py": ""
        ])
        #expect(Fixture.summary(groups) == [
            "python: [main.py] python main.py => python3 main.py",
            "python:app [app/tests] pytest (app) => .venv/bin/python -m pytest",
            "python:app [app/tests] python main.py (app) => .venv/bin/python main.py"
        ])
        #expect(groups[1].tasks.map(\.workingDirectory) == ["app", "app"])
        #expect(groups[1].title == "Python — app")
        #expect(groups[1].tasks.map(\.manifest) == ["app/tests", "app/main.py"])
    }
}

@Suite struct MakeTaskDiscoveryTests {
    @Test func phonyTargetsAreListedEvenWithoutRules() async throws {
        let groups = try await Fixture.discover([
            "Makefile": ".PHONY: build test\nbuild:\n\tgo build\nlint:\n\techo lint\n"
        ])
        #expect(Fixture.summary(groups) == Fixture.lines(id: "make:", manifest: "Makefile", commands: ["make build", "make test"]))
        #expect(groups.first?.tasks.map(\.kind) == [.make, .make])
    }

    @Test func phonyDeclarationsSupportContinuationsMultipleLinesAndComments() async throws {
        let makefile = """
        .PHONY: a \\
            b c
        .PHONY : d # trailing comment
        .PHONY: $(VARS) e a .hidden x/y p%q
        .PHONY: \\
        """
        let groups = try await Fixture.discover(["Makefile": makefile])
        #expect(groups.first?.tasks.map(\.name) == ["make a", "make b", "make c", "make d", "make e"])
    }

    @Test func ruleTargetsAreTheFallbackWithoutPhony() async throws {
        let makefile = [
            "CC := gcc",
            "VAR = a:b",
            "X ::= 1",
            ".PHONY foo",
            "all: build",
            "build: main.o",
            "\tgcc -o app main.o",
            "    spaced: not a rule",
            ".hidden:",
            "%.o: %.c",
            "$(BIN): x",
            "a/b:",
            "# comment: here",
            "",
            "build:",
            "lint test: build",
            "target-spec: FLAGS=-g",
            "ifeq ($(A),b)",
            "endif"
        ].joined(separator: "\n")
        let groups = try await Fixture.discover(["Makefile": makefile])
        #expect(groups.first?.tasks.map(\.name) == ["make all", "make build", "make lint", "make test"])
    }

    @Test(arguments: ["Makefile", "makefile", "GNUmakefile"])
    func manifestFileNames(fileName: String) async throws {
        let groups = try await Fixture.discover([fileName: "all:\n\techo\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(id: "make:", manifest: fileName, commands: ["make all"]))
    }

    @Test func nestedMakefileGetsDirectorySuffix() async throws {
        let groups = try await Fixture.discover(["tools/Makefile": ".PHONY: lint\n"])
        #expect(Fixture.summary(groups) == Fixture.lines(
            id: "make:tools",
            manifest: "tools/Makefile",
            commands: ["make lint"],
            directory: "tools"
        ))
        #expect(groups.first?.tasks.map(\.workingDirectory) == ["tools"])
    }

    @Test(arguments: ["", "\n\n", "# only a comment\n", "\tindented: recipe\n", "VAR = 1\n"])
    func makefilesWithoutTargetsProduceNoGroup(content: String) async throws {
        #expect(try await Fixture.discover(["Makefile": content]).isEmpty)
    }

    @Test func invalidUtf8MakefileIsSkipped() async throws {
        try await withTempDir { root in
            try Fixture.writeFile("Makefile", Data([0xFF, 0xFE, 0xFD]), in: root)
            #expect(await TaskDiscovery(rootURL: root).discover().isEmpty)
        }
    }
}

@Suite struct TaskDiscoveryScanTests {
    private static let manifest = #"{"scripts":{"dev":"vite"}}"#

    @Test func emptyWorkspaceProducesNothing() async throws {
        #expect(try await Fixture.discover([:]).isEmpty)
    }

    @Test func missingRootProducesNothing() async {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)", isDirectory: true)
        #expect(await TaskDiscovery(rootURL: missing).discover().isEmpty)
    }

    @Test(arguments: [
        ".hidden", ".venv", ".build", "node_modules", "target", "build", "dist", "venv", "__pycache__", "Pods", "DerivedData", "vendor"
    ])
    func skippedDirectories(name: String) async throws {
        let groups = try await Fixture.discover([
            "\(name)/package.json": Self.manifest,
            "\(name)/inner/Cargo.toml": "[package]\n",
            "src/\(name)/go.mod": ""
        ])
        #expect(groups.isEmpty)
    }

    @Test func excludedClosureReceivesDirectoryAndPrunesSubtree() async throws {
        let groups = try await Fixture.discover(
            [
                "skipme/package.json": Self.manifest,
                "skipme/inner/package.json": Self.manifest,
                "keep/package.json": Self.manifest,
                "keep/skipme/package.json": Self.manifest,
                "keep/deeper/package.json": Self.manifest
            ],
            isExcluded: { $0.lastPathComponent == "skipme" }
        )
        #expect(groups.map(\.id) == ["npm:keep", "npm:keep/deeper"])
    }

    @Test func orderingIsByDepthThenPathThenKind() async throws {
        let files = [
            "Makefile": "all:\n",
            "main.py": "",
            "Package.swift": "",
            "go.mod": "",
            "Cargo.toml": "[package]\n",
            "package.json": Self.manifest,
            "b/go.mod": "",
            "a/package.json": Self.manifest,
            "a/b/go.mod": "",
            "z/Cargo.toml": "[package]\n",
            "a/b/c/Makefile": "all:\n"
        ]
        let first = try await Fixture.discover(files)
        let second = try await Fixture.discover(files)
        #expect(first.map(\.id) == [
            "npm:",
            "cargo:",
            "go:",
            "python:",
            "swiftPackage:",
            "make:",
            "npm:a",
            "go:b",
            "cargo:z",
            "go:a/b",
            "make:a/b/c"
        ])
        #expect(first == second)
    }

    @Test func manifestsAtMaximumDepthAreFoundAndDeeperOnesAreNot() async throws {
        let atLimit = (1...TaskDiscovery.defaultMaxDepth).map { "d\($0)" }.joined(separator: "/")
        let beyondLimit = atLimit + "/d9"
        let groups = try await Fixture.discover([
            "\(atLimit)/package.json": Self.manifest,
            "\(beyondLimit)/go.mod": ""
        ])
        #expect(groups.map(\.id) == ["npm:\(atLimit)"])
    }

    @Test func visitedDirectoryLimitStopsBreadthFirstScan() async throws {
        try await withTempDir { root in
            try Fixture.writeTree([
                "package.json": Self.manifest,
                "a/package.json": Self.manifest,
                "b/package.json": Self.manifest,
                "c/package.json": Self.manifest,
                "a/x/package.json": Self.manifest
            ], in: root)
            let discovery = TaskDiscovery(
                rootURL: root,
                isExcluded: { _ in false },
                scanProbe: {},
                maxDepth: TaskDiscovery.defaultMaxDepth,
                maxVisitedDirectories: 3
            )
            #expect(await discovery.discover().map(\.id) == ["npm:", "npm:a", "npm:b"])
        }
    }

    @Test func customDepthLimitIsHonoured() async throws {
        try await withTempDir { root in
            try Fixture.writeTree([
                "package.json": Self.manifest,
                "a/package.json": Self.manifest,
                "a/x/package.json": Self.manifest
            ], in: root)
            let discovery = TaskDiscovery(
                rootURL: root,
                isExcluded: { _ in false },
                scanProbe: {},
                maxDepth: 1,
                maxVisitedDirectories: TaskDiscovery.defaultMaxVisitedDirectories
            )
            #expect(await discovery.discover().map(\.id) == ["npm:", "npm:a"])
        }
    }

    @Test func symlinkedDirectoriesAreNotFollowed() async throws {
        try await withTempDir { root in
            try await withTempDir { external in
                try Fixture.writeTree(["package.json": Self.manifest], in: root)
                try Fixture.writeTree(["package.json": Self.manifest], in: external)
                try FileManager.default.createSymbolicLink(
                    at: root.appending(path: "linked", directoryHint: .notDirectory),
                    withDestinationURL: external
                )
                try FileManager.default.createSymbolicLink(
                    at: root.appending(path: "loop", directoryHint: .notDirectory),
                    withDestinationURL: root
                )
                let groups = await TaskDiscovery(rootURL: root).discover()
                #expect(groups.map(\.id) == ["npm:"])
            }
        }
    }

    @Test func unreadableDirectoryIsSkippedSilently() async throws {
        try await withTempDir { root in
            try Fixture.writeTree([
                "package.json": Self.manifest,
                "locked/package.json": Self.manifest,
                "open/package.json": Self.manifest
            ], in: root)
            let locked = root.appending(path: "locked", directoryHint: .isDirectory).path(percentEncoded: false)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
            let groups = await TaskDiscovery(rootURL: root).discover()
            #expect(groups.map(\.id) == ["npm:", "npm:open"])
        }
    }

    @MainActor @Test func scanProbeRunsOnceOffTheMainThread() async throws {
        let recorder = ProbeRecorder()
        try await withTempDir { root in
            try Fixture.writeTree(["package.json": Self.manifest], in: root)
            let discovery = TaskDiscovery(rootURL: root, scanProbe: { recorder.record() })
            let groups = await discovery.discover()
            #expect(groups.map(\.id) == ["npm:"])
        }
        #expect(recorder.flags == [false])
    }

    @Test func discoveredTasksAreHashableValues() async throws {
        let groups = try await Fixture.discover(["go.mod": ""])
        #expect(Set(groups).count == 1)
        #expect(Set(groups.flatMap(\.tasks)).count == 2)
    }
}
