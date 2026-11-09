import AppKit
import Foundation
import Testing
@testable import Dreamder

extension ProjectNavigatorMenuTests {
    @Test
    func markingADirectoryExcludesAndCancelsItsExclusion() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let excluded = try #require(harness.workspace.excludedDirectories)
            let sourcesStreamPath = "\(harness.fileManager.exclusionPolicy().streamRootPath)/Sources"
            let streamExclusions = { harness.fileManager.fsEventStream?.exclusionPaths ?? [] }
            let menu = harness.buildMenu(clicking: sources)
            #expect(!excluded.rules.isExclusionRoot(sources.url))
            #expect(!streamExclusions().contains(sourcesStreamPath))

            #expect(try harness.perform("Excluded", in: menu))
            #expect(excluded.rules.isExclusionRoot(sources.url))
            #expect(streamExclusions().contains(sourcesStreamPath))

            let rebuilt = harness.buildMenu(clicking: sources)
            #expect(harness.menuItem(titled: "Excluded", in: rebuilt) == nil)
            #expect(try harness.perform("Cancel Exclusion", in: rebuilt))
            #expect(!excluded.rules.isExclusionRoot(sources.url))
            #expect(!streamExclusions().contains(sourcesStreamPath))
        }
    }

    @Test
    func itemsWithoutAFileDoNothingWhenMarkingDirectories() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let sources = try harness.file("Sources")
            let menu = harness.buildMenu(clicking: sources)
            let exclude = try #require(harness.menuItem(titled: "Excluded", in: menu))
            let excluded = try #require(harness.workspace.excludedDirectories)
            menu.item = nil
            let action = try #require(exclude.action)
            #expect(NSApplication.shared.sendAction(action, to: exclude.target, from: exclude))
            #expect(!excluded.rules.isExclusionRoot(sources.url))

            menu.item = sources
            let cancelMenu = harness.buildMenu(clicking: sources)
            try harness.perform("Excluded", in: cancelMenu)
            let rebuilt = harness.buildMenu(clicking: sources)
            let cancel = try #require(harness.menuItem(titled: "Cancel Exclusion", in: rebuilt))
            rebuilt.item = nil
            let cancelAction = try #require(cancel.action)
            #expect(NSApplication.shared.sendAction(cancelAction, to: cancel.target, from: cancel))
            #expect(excluded.rules.isExclusionRoot(sources.url))
            rebuilt.item = sources
            try harness.perform("Cancel Exclusion", in: rebuilt)
            #expect(!excluded.rules.isExclusionRoot(sources.url))
        }
    }

    @Test
    func menuCopiesAndDecodesBackIntoAProjectNavigatorMenu() async throws {
        try await Harness.run(folders: Self.folders, files: Self.files) { harness in
            let fresh = ProjectNavigatorMenu(harness.controller)
            let copy = fresh.copy()
            #expect(copy is ProjectNavigatorMenu)

            let data = try NSKeyedArchiver.archivedData(withRootObject: fresh, requiringSecureCoding: false)
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
            unarchiver.finishDecoding()
            #expect(decoded is ProjectNavigatorMenu)
        }
    }
}
