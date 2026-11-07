import Foundation
import Testing
@testable import Dreamder

nonisolated struct PatchChange: Sendable, Equatable, CustomStringConvertible {
    let left: Range<Int>
    let right: Range<Int>

    var description: String { "-\(left) +\(right)" }
}

nonisolated struct PatchFileCase: Sendable, CustomStringConvertible {
    let id: String
    let before: String
    let after: String
    let expectedChanges: [PatchChange]

    var description: String { id }
}

nonisolated enum PatchFixtureLoader {
    static let directory = "platform/platform-tests/testData/diff/patch"

    static func cases() throws -> [PatchFileCase] {
        let manager = FileManager.default
        var result: [PatchFileCase] = []
        for name in try IntelliJTestData.files(in: directory, suffix: "") {
            let patchPath = "\(directory)/\(name)/expected.patch"
            guard manager.fileExists(atPath: IntelliJTestData.url(patchPath).path(percentEncoded: false)) else { continue }
            let sections = changesByFile(in: try IntelliJTestData.text(patchPath))
            let fileNames = try fixtureFileNames(in: "\(directory)/\(name)")
            for fileName in fileNames {
                result.append(PatchFileCase(
                    id: "\(name)/\(fileName)",
                    before: try side("before", directory: "\(directory)/\(name)", fileName: fileName),
                    after: try side("after", directory: "\(directory)/\(name)", fileName: fileName),
                    expectedChanges: sections[fileName] ?? []
                ))
            }
        }
        return result
    }

    private static func fixtureFileNames(in caseDirectory: String) throws -> [String] {
        var names = Set<String>()
        for side in ["before", "after"] {
            let url = IntelliJTestData.url("\(caseDirectory)/\(side)")
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { continue }
            names.formUnion(try IntelliJTestData.files(in: "\(caseDirectory)/\(side)", suffix: ".txt"))
        }
        return names.sorted()
    }

    private static func side(_ side: String, directory: String, fileName: String) throws -> String {
        let path = "\(directory)/\(side)/\(fileName)"
        guard FileManager.default.fileExists(atPath: IntelliJTestData.url(path).path(percentEncoded: false)) else { return "" }
        return try IntelliJTestData.text(path)
    }

    static func changesByFile(in patch: String) -> [String: [PatchChange]] {
        var result: [String: [PatchChange]] = [:]
        var fileName: String?
        var parser = RunCollector()
        func finishFile() {
            if let fileName { result[fileName] = parser.finish() }
            parser = RunCollector()
        }
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("Index: ") {
                finishFile()
                let indexedPath = line.dropFirst("Index: ".count)
                fileName = indexedPath.split(separator: "/").last.map(String.init) ?? String(indexedPath)
            } else if let hunk = GitDiffParser.hunk(fromHeader: line) {
                parser.startHunk(hunk)
            } else {
                parser.consume(line)
            }
        }
        finishFile()
        return result
    }

    nonisolated struct RunCollector {
        private var changes: [PatchChange] = []
        private var oldCursor = 0
        private var newCursor = 0
        private var inHunk = false
        private var oldLines: [Substring] = []
        private var newLines: [Substring] = []
        private var runOldStart = 0
        private var runNewStart = 0

        mutating func startHunk(_ hunk: GitDiffParser.Hunk) {
            flushRun()
            oldCursor = Self.zeroBasedStart(start: hunk.oldStart, count: hunk.oldCount)
            newCursor = Self.zeroBasedStart(start: hunk.newStart, count: hunk.newCount)
            inHunk = true
        }

        mutating func consume(_ line: Substring) {
            guard inHunk, let marker = line.first else { return }
            let content = line.dropFirst()
            switch marker {
            case " ":
                flushRun()
                oldCursor += 1
                newCursor += 1
            case "-":
                beginRunIfNeeded()
                oldLines.append(content)
                oldCursor += 1
            case "+":
                beginRunIfNeeded()
                newLines.append(content)
                newCursor += 1
            default:
                break
            }
        }

        mutating func finish() -> [PatchChange] {
            flushRun()
            let result = changes
            changes = []
            inHunk = false
            return result
        }

        private mutating func beginRunIfNeeded() {
            guard oldLines.isEmpty, newLines.isEmpty else { return }
            runOldStart = oldCursor
            runNewStart = newCursor
        }

        private mutating func flushRun() {
            defer {
                oldLines = []
                newLines = []
            }
            guard !oldLines.isEmpty || !newLines.isEmpty else { return }
            var prefix = 0
            while prefix < oldLines.count, prefix < newLines.count, oldLines[prefix] == newLines[prefix] {
                prefix += 1
            }
            var suffix = 0
            while suffix < oldLines.count - prefix,
                  suffix < newLines.count - prefix,
                  oldLines[oldLines.count - 1 - suffix] == newLines[newLines.count - 1 - suffix] {
                suffix += 1
            }
            let oldChanged = oldLines.count - prefix - suffix
            let newChanged = newLines.count - prefix - suffix
            guard oldChanged > 0 || newChanged > 0 else { return }
            changes.append(PatchChange(
                left: (runOldStart + prefix)..<(runOldStart + prefix + oldChanged),
                right: (runNewStart + prefix)..<(runNewStart + prefix + newChanged)
            ))
        }

        private static func zeroBasedStart(start: Int, count: Int) -> Int {
            guard count == 0 else { return start - 1 }
            return start <= 1 ? 0 : start
        }
    }
}

@Suite
struct TextDiffPatchFixtureTests {
    static let cases: [PatchFileCase] = (try? PatchFixtureLoader.cases()) ?? []

    @Test
    func patchFixturesAreDiscovered() {
        #expect(Self.cases.count >= 26)
        #expect(Self.cases.contains { !$0.expectedChanges.isEmpty })
    }

    @Test(arguments: cases)
    func changedLineRangesMatchTheIntelliJPatch(fixture: PatchFileCase) throws {
        let diff = try TextDiff.compute(left: fixture.before, right: fixture.after)
        let actual = diff.hunks.map { PatchChange(left: $0.leftLines, right: $0.rightLines) }
        #expect(actual == fixture.expectedChanges)
    }
}
