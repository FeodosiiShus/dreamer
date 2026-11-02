import Foundation
import Testing
@testable import Dreamder

@Suite
struct DiffPathTests {
    @Test
    func rootWithTrailingSlashResolvesRelativePath() {
        let root = URL(fileURLWithPath: "/tmp/project/", isDirectory: true)
        let file = URL(fileURLWithPath: "/tmp/project/Sources/App/main.swift")
        #expect(DiffPath.relativePath(of: file, from: root) == "Sources/App/main.swift")
    }

    @Test
    func rootWithoutTrailingSlashResolvesRelativePath() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let file = URL(fileURLWithPath: "/tmp/project/README.md")
        #expect(DiffPath.relativePath(of: file, from: root) == "README.md")
    }

    @Test
    func siblingDirectorySharingPrefixIsOutsideRoot() {
        let root = URL(fileURLWithPath: "/tmp/project/", isDirectory: true)
        let file = URL(fileURLWithPath: "/tmp/project-other/README.md")
        #expect(DiffPath.relativePath(of: file, from: root).isEmpty)
    }
}
