import Foundation
import Testing
@testable import Dreamder

@Suite
struct ExcludedDirectoriesTests {
    private let root = URL(fileURLWithPath: "/tmp/dreamder-exclusions-\(UUID().uuidString)", isDirectory: true)

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "dreamder.tests.exclusions.\(UUID().uuidString)") ?? .standard
    }

    @Test
    func nodeModulesAreExcludedByDefaultAndTheirContentsToo() {
        let rules = ExclusionRules(rootURL: root)
        let modules = root.appending(path: "web/node_modules")
        #expect(rules.isExclusionRoot(modules))
        #expect(rules.isExcluded(modules.appending(path: "react/index.js")))
        #expect(rules.isExcluded(root.appending(path: "web/src/app.ts")) == false)
        #expect(rules.isExclusionRoot(URL(fileURLWithPath: "/elsewhere/node_modules")) == false)
    }

    @Test
    func markingAndCancellingIsRememberedPerProject() {
        let store = defaults()
        let model = ExcludedDirectories(rootURL: root, defaults: store)
        let generated = root.appending(path: "generated")
        let modules = root.appending(path: "node_modules")

        model.exclude(generated)
        model.cancelExclusion(modules)
        #expect(model.rules.isExcluded(generated.appending(path: "a.swift")))
        #expect(model.rules.isExclusionRoot(modules) == false)

        let reopened = ExcludedDirectories(rootURL: root, defaults: store)
        #expect(reopened.rules.isExclusionRoot(generated))
        #expect(reopened.rules.isExclusionRoot(modules) == false)

        reopened.cancelExclusion(generated)
        reopened.exclude(modules)
        #expect(reopened.rules.isExclusionRoot(generated) == false)
        #expect(reopened.rules.isExclusionRoot(modules))
        #expect(ExcludedDirectories.rules(covering: root.appending(path: "sub")).isExclusionRoot(modules))
    }

    @Test
    func scannersSkipExcludedDirectories() async throws {
        try await withTempDir { dir in
            let fileManager = FileManager.default
            for path in ["src/a.swift", "node_modules/pkg/index.js", "generated/out.swift"] {
                let url = dir.appending(path: path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try "x".write(to: url, atomically: true, encoding: .utf8)
            }
            let model = ExcludedDirectories(rootURL: dir, defaults: defaults())
            model.exclude(dir.appending(path: "generated"))

            let indexed = WorkspaceDocument.SearchState.fileURLs(at: dir, excluding: model.rules)
                .map { $0.lastPathComponent }
            #expect(indexed == ["a.swift"])

            let scanned = await SearchEverywhereFileScanner.urls(in: dir).map(\.lastPathComponent)
            #expect(scanned == ["a.swift"])
        }
    }
}
