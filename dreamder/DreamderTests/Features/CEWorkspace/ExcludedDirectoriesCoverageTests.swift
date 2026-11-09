import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ExcludedDirectoriesCoverageTests {
    private let root = URL(fileURLWithPath: "/tmp/dreamder-exclusions-cov-\(UUID().uuidString)", isDirectory: true)

    @Test
    func urlsOutsideTheRootAreNeverExcluded() {
        let rules = ExclusionRules(rootURL: root)
        let outside = URL(fileURLWithPath: "/elsewhere/node_modules/pkg/index.js")

        #expect(rules.relativePath(of: outside) == nil)
        #expect(!rules.isExcluded(outside))
        #expect(!rules.isExcluded(root))
    }

    @Test
    func excludingOrCancellingOutsideTheRootChangesNothing() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let model = ExcludedDirectories(rootURL: root, defaults: isolated.defaults)
        let outside = URL(fileURLWithPath: "/elsewhere/generated")

        model.exclude(outside)
        model.cancelExclusion(outside)

        let rootPath = model.rules.rootPath
        #expect(model.rules == ExclusionRules(rootURL: root))
        #expect(isolated.defaults.stringArray(forKey: ExcludedDirectories.excludedKeyPrefix + rootPath) == nil)
        #expect(isolated.defaults.stringArray(forKey: ExcludedDirectories.cancelledKeyPrefix + rootPath) == nil)
    }

    @Test
    func theInnermostRegisteredRootCoversANestedPath() throws {
        let isolated = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(isolated.defaults, suiteName: isolated.suiteName) }
        let innerRoot = root.appending(path: "inner", directoryHint: .isDirectory)
        let outer = ExcludedDirectories(rootURL: root, defaults: isolated.defaults)
        let inner = ExcludedDirectories(rootURL: innerRoot, defaults: isolated.defaults)
        inner.exclude(innerRoot.appending(path: "special"))

        let nested = ExcludedDirectories.rules(covering: innerRoot.appending(path: "leaf"))
        let sibling = ExcludedDirectories.rules(covering: root.appending(path: "other"))

        #expect(nested.rootPath == inner.rules.rootPath)
        #expect(nested.isExclusionRoot(innerRoot.appending(path: "special")))
        #expect(sibling.rootPath == outer.rules.rootPath)
        #expect(!sibling.isExclusionRoot(innerRoot.appending(path: "special")))
    }
}
