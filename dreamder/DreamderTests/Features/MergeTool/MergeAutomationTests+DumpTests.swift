import AppKit
import Foundation
import Testing
@testable import Dreamder

extension MergeAutomationTests {
    @Test
    func focusWorkspaceBringsTheMatchingWorkspaceWindowToTheFront() async throws {
        try await withTempDir { firstDirectory in
            try await withTempDir { secondDirectory in
                let first = WorkspaceDocument()
                try first.read(from: firstDirectory, ofType: "")
                NSDocumentController.shared.addDocument(first)
                first.makeWindowControllers()
                let firstWindow = try #require(first.windowControllers.first?.window)
                firstWindow.isReleasedWhenClosed = false
                let second = WorkspaceDocument()
                try second.read(from: secondDirectory, ofType: "")
                NSDocumentController.shared.addDocument(second)
                second.makeWindowControllers()
                let secondWindow = try #require(second.windowControllers.first?.window)
                secondWindow.isReleasedWhenClosed = false
                defer {
                    firstWindow.close()
                    first.close()
                    secondWindow.close()
                    second.close()
                }
                let secondPath = secondDirectory.path(percentEncoded: false)

                firstWindow.orderOut(nil)
                secondWindow.orderOut(nil)
                await MergeAutomation.perform("focusWorkspace:\(secondPath)")
                #expect(secondWindow.isVisible)
                #expect(firstWindow.isVisible == false)

                secondWindow.orderOut(nil)
                await MergeAutomation.perform("target:\(secondPath)")
                await MergeAutomation.perform("focusWorkspace:")
                #expect(secondWindow.isVisible)
                #expect(firstWindow.isVisible == false)
                await MergeAutomation.perform("target:")
            }
        }
    }

    @Test
    func dumpWithoutOpenWindowsReportsTheEmptyState() async throws {
        try await withSession { session in
            await MergeAutomation.perform("target:\(session.path)")
            MergeAutomation.registerBanner(path: nil, action: nil)

            let lines = try await dumpLines(session)

            #expect(value("target", in: lines) == session.path)
            #expect(value("workspace", in: lines) == session.path)
            #expect(value("documents", in: lines)?.contains(session.path) == true)
            #expect(value("banner.path", in: lines) == "")
            #expect(value("banner.action", in: lines) == "0")
            #expect(value("conflicts.open", in: lines) == "0")
            #expect(value("revisions.open", in: lines) == "0")
        }
    }

    @Test
    func dumpDescribesTheConflictsDialogAndTheRevisionsWindow() async throws {
        try await withSession { session in
            let conflicts = try await openConflicts(session)
            await MergeAutomation.perform("select:\(Self.configPath)")
            MergeAutomation.registerBanner(path: Self.configPath) {}
            let revisions = try await openRevisions(session)
            let merge = try #require(revisions.merge)
            _ = conflicts

            let lines = try await dumpLines(session)

            #expect(value("target", in: lines) == session.path)
            #expect(value("banner.path", in: lines) == Self.configPath)
            #expect(value("banner.action", in: lines) == "1")
            #expect(value("windowTitles", in: lines)?.contains("Conflicts") == true)

            #expect(value("conflicts.open", in: lines) == "1")
            #expect(value("conflicts.summary", in: lines) == Self.mergeSummary)
            #expect(value("conflicts.error", in: lines) == "")
            #expect(value("conflicts.busy", in: lines) == "0")
            #expect(value("conflicts.primary", in: lines) == Self.configPath)
            #expect(value("conflicts.selected", in: lines) == Self.configPath)
            #expect(value("conflicts.count", in: lines) == "2")
            #expect(values("conflicts.entry", in: lines) == [
                "app/config.txt|Modified|Modified",
                "docs/notes.txt|Modified|Modified"
            ])
            #expect(value("conflicts.yoursHeader", in: lines)?.contains("main") == true)
            #expect(value("conflicts.theirsHeader", in: lines)?.contains("feature") == true)

            #expect(value("revisions.open", in: lines) == "1")
            #expect(value("revisions.path", in: lines) == Self.configPath)
            #expect(value("revisions.title", in: lines) == "Merge Revisions for app/config.txt")
            #expect(value("revisions.summary", in: lines) == revisions.summary)
            #expect(value("revisions.error", in: lines) == "")
            #expect(value("revisions.valid", in: lines) == "1")
            #expect(value("revisions.edited", in: lines) == "0")
            #expect(value("revisions.loading", in: lines) == "0")
            #expect(value("revisions.leftTitle", in: lines) == "Your version, branch main")
            #expect(value("revisions.rightTitle", in: lines) == "Theirs, branch feature")
            #expect(value("revisions.conflicts", in: lines) == "1")
            #expect(value("revisions.changes", in: lines) == "2")
            #expect(values("revisions.block", in: lines).count == merge.blocks.count)
            #expect(values("revisions.block", in: lines).contains { $0.hasSuffix("|conflict|unresolved|5-6") })
            #expect(value("revisions.nonConflictingLeft", in: lines) == "1")
            #expect(value("revisions.nonConflictingAll", in: lines) == "1")
            #expect(value("revisions.nonConflictingRight", in: lines) == "1")
            let expectedResult = "alpha\\nbeta-main\\ngamma\\ndelta\\nepsilon\\nzeta\\neta\\n"
                + "theta\\niota\\nkappa\\nfeature-added\\nlambda\\n"
            #expect(value("revisions.result", in: lines) == expectedResult)
            #expect(value("revisions.left", in: lines)?.contains("zeta-main") == true)
            #expect(value("revisions.right", in: lines)?.contains("zeta-feature") == true)
        }
    }

    @Test
    func dumpReportsEditedAndResolvedRevisionState() async throws {
        try await withSession { session in
            let model = try await openRevisions(session)
            let blockID = try conflictBlockID(model)
            await MergeAutomation.perform("resolve:\(blockID):right")
            await MergeAutomation.perform("editResult:one\\ntwo\\\\n")

            let lines = try await dumpLines(session)

            #expect(value("revisions.edited", in: lines) == "1")
            #expect(value("revisions.conflicts", in: lines) == "0")
            #expect(value("revisions.result", in: lines) == "one\\ntwo\\\\n")
            #expect(values("revisions.block", in: lines).contains { $0.hasSuffix("|conflict|right|5-6") })
        }
    }

    @Test
    func dumpWithoutADirectoryWritesIntoTheTemporaryDirectory() async throws {
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "merge.txt")
        defer { try? FileManager.default.removeItem(at: output) }
        try? FileManager.default.removeItem(at: output)
        await MergeAutomation.perform("target:/tmp/dreamder-dump-default")
        await MergeAutomation.perform("dump:")
        await MergeAutomation.perform("target:")

        let text = try String(contentsOf: output, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        #expect(value("target", in: lines) == "/tmp/dreamder-dump-default")
        #expect(value("banner.action", in: lines) != nil)
    }

    @Test
    func dumpReportsAnEmptyPrimaryPathWhenNothingIsSelected() async throws {
        try await withSession { session in
            let conflicts = try await openConflicts(session)
            conflicts.select(nil)

            let lines = try await dumpLines(session)

            #expect(value("conflicts.primary", in: lines) == "")
            #expect(value("conflicts.selected", in: lines) == "")
            #expect(value("conflicts.open", in: lines) == "1")
        }
    }
}
