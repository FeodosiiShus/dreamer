import Foundation

actor BranchesPopupTemplateRepository {
    static let local = BranchesPopupTemplateRepository { root in
        let fixture = try await GitMergeFixture(root: root)
        try fixture.write("a.txt", "a\n")
        try await fixture.commit("initial")
        try await fixture.run("tag", "v1.0")
        try await fixture.run("checkout", "-q", "-b", "feature")
        try fixture.write("feature.txt", "feature\n")
        try await fixture.commit("feature work")
        try await fixture.run("checkout", "-q", "main")
        try await fixture.run("branch", "obsolete")
    }

    static let cloned = BranchesPopupTemplateRepository { root in
        let originRoot = root.appending(path: "origin")
        try FileManager.default.createDirectory(at: originRoot, withIntermediateDirectories: true)
        let origin = try await GitMergeFixture(root: originRoot)
        try origin.write("a.txt", "base\n")
        try await origin.commit("initial")
        try await origin.run("branch", "feature")
        let cloneRoot = root.appending(path: "clone")
        try await origin.run(
            "clone",
            "-q",
            originRoot.path(percentEncoded: false),
            cloneRoot.path(percentEncoded: false)
        )
        let clone = GitMergeFixture(existing: cloneRoot)
        try await clone.run("config", "user.email", "clone@dreamder.test")
        try await clone.run("config", "user.name", "Clone")
        try await clone.run("checkout", "-q", "-b", "feature", "--track", "origin/feature")
        try await clone.run("checkout", "-q", "main")
        try await clone.run("tag", "v1")
        try await clone.run("branch", "obsolete")
    }

    private let build: @Sendable (URL) async throws -> Void
    private var template: Task<URL, any Error>?

    init(build: @escaping @Sendable (URL) async throws -> Void) {
        self.build = build
    }

    func copy(into directory: URL) async throws {
        let source = try await templateURL()
        for item in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: item, to: directory.appending(path: item.lastPathComponent))
        }
    }

    private func templateURL() async throws -> URL {
        if let template {
            return try await template.value
        }
        let build = build
        let task = Task<URL, any Error> {
            let root = try makeTemporaryDirectory(label: "BranchesPopupTemplate")
            try await build(root)
            return root
        }
        template = task
        return try await task.value
    }
}
