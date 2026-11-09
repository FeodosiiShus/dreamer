import AppKit
import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct ProjectNavigatorExclusionAndSortTests {
    typealias Harness = ProjectNavigatorControllerHarness

    private static let treeFolders = ["src/deep", "node_modules/pkg", "build/out", "gen/inner", "lib"]
    private static let treeFiles = [
        "a.txt",
        "debug.log",
        "src/deep/x.swift",
        "src/deep/y.js",
        "node_modules/pkg/i.js",
        "build/out/o.txt",
        "gen/inner/g.txt",
        "lib/l.txt"
    ]

    private func components(_ color: NSColor?) -> [CGFloat] {
        guard let converted = color?.usingColorSpace(.sRGB) else { return [] }
        return [converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent]
    }

    private func nameColor(_ cell: ProjectNavigatorTableViewCell?) -> [CGFloat] {
        components(cell?.textField?.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
    }

    private func ordered(
        _ lhs: CEWorkspaceFile,
        _ rhs: CEWorkspaceFile,
        _ mode: FolderSortMode,
        foldersOnTop: Bool = true
    ) -> Bool {
        ProjectNavigatorSorter.areInIncreasingOrder(lhs, rhs, mode: mode, foldersOnTop: foldersOnTop)
    }

    private func ghost(_ name: String) -> CEWorkspaceFile {
        CEWorkspaceFile(url: URL(filePath: "/tmp/dreamder-sort-ghost/\(name)"))
    }

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let (defaults, suite) = try makeIsolatedDefaults()
        defer { removeIsolatedDefaults(defaults, suiteName: suite) }
        try body(defaults, suite)
    }

    private func storedModes(_ defaults: UserDefaults, root: String) -> [String: String]? {
        defaults.dictionary(forKey: ProjectNavigatorSortModes.keyPrefix + root) as? [String: String]
    }

    private func openIgnoreFile(_ harness: Harness, _ text: String) throws {
        try harness.write(".gitignore", text)
        harness.workspace.fileScope?.reload()
    }

    private func rootKey(_ harness: Harness) -> String {
        var path = harness.root.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    @Test
    func foldersComeFirstWhenFoldersOnTopIsEnabledInBothModes() async throws {
        try withTempDir { dir in
            let folderURL = dir.appending(path: "zdir", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let folder = CEWorkspaceFile(url: folderURL)
            let file = ghost("a.md")

            for mode in FolderSortMode.allCases {
                #expect(ordered(folder, file, mode))
                #expect(!ordered(file, folder, mode))
            }
        }
    }

    @Test
    func nameModeIgnoresFolderKindWhenFoldersOnTopIsDisabled() async throws {
        try withTempDir { dir in
            let folderURL = dir.appending(path: "zdir", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let folder = CEWorkspaceFile(url: folderURL)
            let file = ghost("a.md")

            #expect(ordered(file, folder, .name, foldersOnTop: false))
            #expect(!ordered(folder, file, .name, foldersOnTop: false))
        }
    }

    @Test
    func nameModeComparesCaseInsensitivelyAndBreaksTiesByExactName() {
        #expect(ordered(ghost("alpha"), ghost("Beta"), .name))
        #expect(!ordered(ghost("Beta"), ghost("alpha"), .name))
        #expect(ordered(ghost("A.txt"), ghost("a.txt"), .name))
        #expect(!ordered(ghost("a.txt"), ghost("A.txt"), .name))
        #expect(!ordered(ghost("a.txt"), ghost("a.txt"), .name))
    }

    @Test
    func typeModeGroupsByLowercasedExtensionThenByName() {
        #expect(ordered(ghost("z.md"), ghost("a.txt"), .type))
        #expect(!ordered(ghost("a.txt"), ghost("z.md"), .type))
        #expect(ordered(ghost("b.MD"), ghost("c.md"), .type))
        #expect(!ordered(ghost("c.md"), ghost("b.MD"), .type))
        #expect(ordered(ghost("Makefile"), ghost("a.md"), .type))
    }

    @Test
    func typeModeKeysFoldersAsEmptyEvenWhenFoldersOnTopIsDisabled() async throws {
        try withTempDir { dir in
            let folderURL = dir.appending(path: "zdir", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let folder = CEWorkspaceFile(url: folderURL)

            #expect(ordered(folder, ghost("a.md"), .type, foldersOnTop: false))
            #expect(!ordered(ghost("a.md"), folder, .type, foldersOnTop: false))
            #expect(ordered(ghost("Makefile"), folder, .type, foldersOnTop: false))
            #expect(!ordered(folder, ghost("Makefile"), .type, foldersOnTop: false))
        }
    }

    @Test
    func sortModesDefaultToNameAndPersistTheChosenModePerFolder() throws {
        try withDefaults { defaults, _ in
            let root = URL(filePath: "/tmp/dreamder-sort-root")
            let modes = ProjectNavigatorSortModes(rootURL: root, defaults: defaults)
            let src = root.appending(path: "src")
            let deep = src.appending(path: "deep")

            #expect(modes.mode(for: root) == .name)
            #expect(modes.mode(for: src) == .name)
            #expect(modes.modes.isEmpty)
            #expect(storedModes(defaults, root: "/tmp/dreamder-sort-root") == nil)

            modes.set(.type, for: root)
            modes.set(.type, for: deep)

            #expect(modes.mode(for: root) == .type)
            #expect(modes.mode(for: deep) == .type)
            #expect(modes.mode(for: src) == .name)
            #expect(modes.modes == ["": .type, "src/deep": .type])
            #expect(storedModes(defaults, root: "/tmp/dreamder-sort-root") == ["": "type", "src/deep": "type"])
        }
    }

    @Test
    func persistedModesReloadIntoASecondInstance() throws {
        try withDefaults { defaults, _ in
            let root = URL(filePath: "/tmp/dreamder-sort-reload")
            let first = ProjectNavigatorSortModes(rootURL: root, defaults: defaults)
            first.set(.type, for: root.appending(path: "docs"))

            let second = ProjectNavigatorSortModes(rootURL: root, defaults: defaults)

            #expect(second.mode(for: root.appending(path: "docs")) == .type)
            #expect(second.mode(for: root) == .name)
            #expect(second.modes == ["docs": .type])
        }
    }

    @Test
    func settingNameRemovesTheStoredEntry() throws {
        try withDefaults { defaults, _ in
            let root = URL(filePath: "/tmp/dreamder-sort-remove")
            let modes = ProjectNavigatorSortModes(rootURL: root, defaults: defaults)
            let docs = root.appending(path: "docs")
            modes.set(.type, for: docs)
            modes.set(.type, for: root)

            modes.set(.name, for: docs)

            #expect(modes.mode(for: docs) == .name)
            #expect(modes.modes == ["": .type])
            #expect(storedModes(defaults, root: "/tmp/dreamder-sort-remove") == ["": "type"])

            modes.set(.name, for: root)

            #expect(modes.modes.isEmpty)
            #expect(storedModes(defaults, root: "/tmp/dreamder-sort-remove") == [:])
            #expect(ProjectNavigatorSortModes(rootURL: root, defaults: defaults).modes.isEmpty)
        }
    }

    @Test
    func foldersOutsideTheRootAreKeyedByTheirAbsolutePath() throws {
        try withDefaults { defaults, _ in
            let root = URL(filePath: "/tmp/dreamder-sort-outside")
            let modes = ProjectNavigatorSortModes(rootURL: root, defaults: defaults)
            let elsewhere = URL(filePath: "/var/elsewhere/docs")
            let sibling = URL(filePath: "/tmp/dreamder-sort-outside-sibling")

            modes.set(.type, for: elsewhere)
            modes.set(.type, for: sibling)

            #expect(modes.mode(for: elsewhere) == .type)
            #expect(modes.mode(for: sibling) == .type)
            #expect(modes.mode(for: root) == .name)
            #expect(modes.modes == [
                "/var/elsewhere/docs": .type,
                "/tmp/dreamder-sort-outside-sibling": .type
            ])
        }
    }

    @Test
    func trailingSlashesOfTheRootAreIgnoredAndTheFilesystemRootKeepsItsSlash() throws {
        try withDefaults { defaults, _ in
            let slashed = URL(filePath: "/tmp/dreamder-sort-slash/", directoryHint: .isDirectory)
            let modes = ProjectNavigatorSortModes(rootURL: slashed, defaults: defaults)
            modes.set(.type, for: URL(filePath: "/tmp/dreamder-sort-slash/docs"))

            #expect(storedModes(defaults, root: "/tmp/dreamder-sort-slash") == ["docs": "type"])

            let filesystemRoot = ProjectNavigatorSortModes(rootURL: URL(filePath: "/"), defaults: defaults)
            filesystemRoot.set(.type, for: URL(filePath: "/"))
            filesystemRoot.set(.type, for: URL(filePath: "/usr"))

            #expect(storedModes(defaults, root: "/") == ["": "type", "/usr": "type"])
        }
    }

    @Test
    func invalidStoredValuesAreDroppedWhenLoading() throws {
        try withDefaults { defaults, _ in
            let root = URL(filePath: "/tmp/dreamder-sort-invalid")
            let key = ProjectNavigatorSortModes.keyPrefix + "/tmp/dreamder-sort-invalid"
            defaults.set(["good": "type", "bad": "bogus", "plain": "name"], forKey: key)

            let modes = ProjectNavigatorSortModes(rootURL: root, defaults: defaults)

            #expect(modes.modes == ["good": .type, "plain": .name])

            defaults.set(["not", "a", "dictionary"], forKey: key)

            #expect(ProjectNavigatorSortModes(rootURL: root, defaults: defaults).modes.isEmpty)
        }
    }

    @Test
    func keyPrefixIsStable() {
        #expect(ProjectNavigatorSortModes.keyPrefix == "dreamder.projectNavigator.sortModes.")
    }

    @Test
    func sortItemsAreEnabledForFoldersOnlyAndReflectTheActiveMode() async throws {
        try await Harness.run(folders: ["Docs"], files: ["a.txt", "Docs/b.txt"]) { harness in
            let docs = try harness.file("Docs")
            let a = try harness.file("a.txt")

            let folderMenu = harness.buildMenu(clicking: docs)
            let byName = try #require(harness.menuItem(titled: "Sort by Name", in: folderMenu))
            let byType = try #require(harness.menuItem(titled: "Sort by Type", in: folderMenu))
            #expect(byName.isEnabled)
            #expect(byType.isEnabled)
            #expect(byName.state == .on)
            #expect(byType.state == .off)

            let fileMenu = harness.buildMenu(clicking: a)
            let fileByName = try #require(harness.menuItem(titled: "Sort by Name", in: fileMenu))
            let fileByType = try #require(harness.menuItem(titled: "Sort by Type", in: fileMenu))
            #expect(!fileByName.isEnabled)
            #expect(!fileByType.isEnabled)
            #expect(fileByName.state == .off)
            #expect(fileByType.state == .off)
        }
    }

    @Test
    func sortByTypeReordersTheFolderPersistsItForThatFolderOnlyAndSortByNameRestoresIt() async throws {
        try await Harness.run(
            folders: ["Docs", "Other"],
            files: ["Docs/b.txt", "Docs/a.md", "Docs/c.md", "Other/z.md", "Other/y.txt"],
            loadsTree: true
        ) { harness in
            let docs = try harness.file("Docs")
            let other = try harness.file("Other")
            #expect(harness.childNames(of: docs) == ["a.md", "b.txt", "c.md"])
            #expect(harness.childNames(of: other) == ["y.txt", "z.md"])

            let menu = harness.buildMenu(clicking: docs)
            try harness.perform("Sort by Type", in: menu)

            #expect(harness.childNames(of: docs) == ["a.md", "c.md", "b.txt"])
            #expect(harness.childNames(of: other) == ["y.txt", "z.md"])
            #expect(harness.controller.sortModes.mode(for: docs.url) == .type)
            #expect(harness.controller.sortModes.mode(for: other.url) == .name)
            let defaults = try #require(UserDefaults(suiteName: harness.sortDefaultsSuite))
            #expect(storedModes(defaults, root: rootKey(harness)) == ["Docs": "type"])
            let reloaded = ProjectNavigatorSortModes(rootURL: harness.root, defaults: defaults)
            #expect(reloaded.mode(for: docs.url) == .type)

            let updated = harness.buildMenu(clicking: docs)
            #expect(harness.menuItem(titled: "Sort by Type", in: updated)?.state == .on)
            #expect(harness.menuItem(titled: "Sort by Name", in: updated)?.state == .off)

            try harness.perform("Sort by Name", in: updated)

            #expect(harness.childNames(of: docs) == ["a.md", "b.txt", "c.md"])
            #expect(harness.controller.sortModes.mode(for: docs.url) == .name)
            #expect(storedModes(defaults, root: rootKey(harness)) == [:])
        }
    }

    @Test
    func sortActionsWithoutAFolderItemOrSenderDoNothing() async throws {
        try await Harness.run(folders: ["Docs"], files: ["a.txt", "Docs/b.txt"], loadsTree: true) { harness in
            let docs = try harness.file("Docs")
            let a = try harness.file("a.txt")

            let blank = ProjectNavigatorMenu(harness.controller)
            blank.sortByType()
            blank.sortByName()

            let onFile = ProjectNavigatorMenu(harness.controller)
            onFile.item = a
            onFile.sortByType()

            let orphan = ProjectNavigatorMenu(harness.controller)
            orphan.item = docs
            orphan.sender = nil
            orphan.sortByType()

            #expect(harness.controller.sortModes.modes.isEmpty)
            #expect(harness.childNames(of: docs) == ["b.txt"])
        }
    }

    @Test
    func rebuildWithoutAnItemLeavesTheMenuEmpty() async throws {
        try await Harness.run(files: ["a.txt"]) { harness in
            let a = try harness.file("a.txt")
            #expect(!harness.buildMenu(clicking: a).items.isEmpty)

            let menu = harness.buildMenu(clicking: nil)

            #expect(menu.item == nil)
            #expect(menu.items.isEmpty)
        }
    }

    @Test
    func exclusionResolvesDefaultExcludedFoldersTheirContentAndPlainItems() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles) { harness in
            let controller = harness.controller

            let src = try harness.file("src")
            let a = try harness.file("a.txt")
            let nodeModules = try harness.file("node_modules")
            let pkg = try harness.file("node_modules/pkg")
            let pkgFile = try harness.file("node_modules/pkg/i.js")
            let build = try harness.file("build")
            #expect(controller.exclusion(for: src) == .included)
            #expect(controller.exclusion(for: a) == .included)
            #expect(controller.exclusion(for: nodeModules) == .excludedRoot)
            #expect(controller.exclusion(for: pkg) == .excludedContent)
            #expect(controller.exclusion(for: pkgFile) == .excludedContent)
            #expect(controller.exclusion(for: build) == .excludedRoot)
            #expect(controller.exclusion(for: harness.rootFile) == .included)

            harness.workspace.tearDownFileScope()

            #expect(controller.exclusion(for: nodeModules) == .included)
        }
    }

    @Test
    func excludedFolderCellsAreDimmedWithTheExcludedRootIcon() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles, loadsTree: true) { harness in
            try harness.expand("node_modules")
            try harness.expand("node_modules/pkg")
            let modules = try #require(harness.cell(for: try harness.file("node_modules")))
            let pkg = try #require(harness.cell(for: try harness.file("node_modules/pkg")))
            let src = try #require(harness.cell(for: try harness.file("src")))
            let excludedColor = components(NSColor(Islands.secondaryForeground))

            #expect(modules.exclusion == .excludedRoot)
            #expect(modules.imageView?.image?.name() == "nodes/excludeRoot")
            #expect(modules.imageView?.alphaValue == FileSystemTableViewCell.excludedIconAlpha)
            #expect(nameColor(modules) == excludedColor)
            #expect(pkg.exclusion == .excludedContent)
            #expect(pkg.imageView?.image?.name() == "nodes/folder")
            #expect(pkg.imageView?.alphaValue == FileSystemTableViewCell.excludedIconAlpha)
            #expect(nameColor(pkg) == excludedColor)
            #expect(src.exclusion == .included)
            #expect(src.imageView?.image?.name() == "nodes/folder")
            #expect(src.imageView?.alphaValue == 1)
            #expect(nameColor(src) == components(NSColor(Islands.foreground)))
        }
    }

    @Test
    func filesInsideExcludedFoldersAndIgnoredFilesUseTheIgnoredColour() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles, loadsTree: true) { harness in
            try openIgnoreFile(harness, "*.log\n")
            harness.reload()
            try harness.expand("node_modules")
            try harness.expand("node_modules/pkg")
            let index = try #require(harness.cell(for: try harness.file("node_modules/pkg/i.js")))
            let log = try #require(harness.cell(for: try harness.file("debug.log")))
            let plain = try #require(harness.cell(for: try harness.file("a.txt")))

            #expect(index.exclusion == .excludedContent)
            #expect(components(index.nameColor(for: try harness.file("node_modules/pkg/i.js"))) == components(NSColor(Islands.fileIgnored)))
            #expect(index.imageView?.alphaValue == 1)
            #expect(log.exclusion == .excludedRoot)
            #expect(components(log.nameColor(for: try harness.file("debug.log"))) == components(NSColor(Islands.fileIgnored)))
            #expect(plain.exclusion == .included)
            #expect(components(plain.nameColor(for: try harness.file("a.txt"))) == components(NSColor(Islands.foreground)))
        }
    }

    @Test
    func markingAFolderExcludedFromTheMenuDimsItAndCancelExclusionRestoresIt() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles) { harness in
            let src = try harness.file("src")
            #expect(harness.controller.exclusion(for: src) == .included)

            let menu = harness.buildMenu(clicking: src)
            #expect(harness.menuItem(titled: "Cancel Exclusion", in: menu) == nil)
            try harness.perform("Excluded", in: menu)

            try await eventually { harness.controller.exclusion(for: src) == .excludedRoot }
            harness.reload()
            let excluded = try #require(harness.cell(for: src))
            #expect(excluded.exclusion == .excludedRoot)
            #expect(excluded.imageView?.image?.name() == "nodes/excludeRoot")
            #expect(excluded.imageView?.alphaValue == FileSystemTableViewCell.excludedIconAlpha)
            #expect(nameColor(excluded) == components(NSColor(Islands.secondaryForeground)))

            let excludedMenu = harness.buildMenu(clicking: src)
            #expect(harness.menuItem(titled: "Excluded", in: excludedMenu) == nil)
            try harness.perform("Cancel Exclusion", in: excludedMenu)

            try await eventually { harness.controller.exclusion(for: src) == .included }
            harness.reload()
            let restored = try #require(harness.cell(for: src))
            #expect(restored.exclusion == .included)
            #expect(restored.imageView?.image?.name() == "nodes/folder")
            #expect(restored.imageView?.alphaValue == 1)
        }
    }

    @Test
    func cancellingTheDefaultExclusionOfNodeModulesMakesItAnOrdinaryFolder() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles) { harness in
            let modules = try harness.file("node_modules")
            let menu = harness.buildMenu(clicking: modules)
            #expect(harness.menuItem(titled: "Excluded", in: menu) == nil)

            try harness.perform("Cancel Exclusion", in: menu)

            try await eventually { harness.controller.exclusion(for: modules) == .included }
            harness.reload()
            let cell = try #require(harness.cell(for: modules))
            #expect(cell.imageView?.image?.name() == "nodes/folder")
            #expect(cell.imageView?.alphaValue == 1)

            try harness.perform("Excluded", in: harness.buildMenu(clicking: modules))

            try await eventually { harness.controller.exclusion(for: modules) == .excludedRoot }
        }
    }

    @Test
    func expandAllSkipsExcludedAndIgnoredFolders() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles, loadsTree: true) { harness in
            try openIgnoreFile(harness, "gen/\n")
            harness.reload()
            let tracked = ["src", "src/deep", "lib"]
            let skipped = ["node_modules", "build", "gen"]
            for path in tracked + skipped {
                #expect(!harness.outlineView.isItemExpanded(try harness.file(path)))
            }

            harness.controller.expandAll(nil)

            #expect(harness.outlineView.isItemExpanded(harness.rootFile))
            for path in tracked {
                #expect(harness.outlineView.isItemExpanded(try harness.file(path)))
            }
            for path in skipped {
                #expect(!harness.outlineView.isItemExpanded(try harness.file(path)))
            }
            #expect(harness.row(of: try harness.file("node_modules/pkg")) == -1)
            #expect(harness.row(of: try harness.file("gen/inner")) == -1)
            #expect(harness.row(of: try harness.file("src/deep")) >= 0)
        }
    }

    @Test
    func expandIncludedFoldersIgnoresFilesAndExcludedFolders() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles, loadsTree: true) { harness in
            let a = try harness.file("a.txt")
            let modules = try harness.file("node_modules")
            let src = try harness.file("src")

            harness.controller.expandIncludedFolders(a)
            harness.controller.expandIncludedFolders(modules)
            #expect(!harness.outlineView.isItemExpanded(a))
            #expect(!harness.outlineView.isItemExpanded(modules))

            harness.controller.expandIncludedFolders(src)
            #expect(harness.outlineView.isItemExpanded(src))
            let deep = try harness.file("src/deep")
            #expect(harness.outlineView.isItemExpanded(deep))
        }
    }

    @Test
    func collapseAllCollapsesEveryExpandedFolder() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles, loadsTree: true) { harness in
            harness.controller.expandAll(nil)
            let deep = try harness.file("src/deep")
            #expect(harness.outlineView.isItemExpanded(deep))

            try await harness.settleOutline()

            harness.controller.collapseAll(nil)

            let srcAfter = try harness.file("src")
            let lib = try harness.file("lib")
            try await eventually(timeout: .seconds(30)) { !harness.outlineView.isItemExpanded(harness.rootFile) }
            #expect(!harness.outlineView.isItemExpanded(srcAfter))
            #expect(!harness.outlineView.isItemExpanded(deep))
            #expect(!harness.outlineView.isItemExpanded(lib))
        }
    }

    @Test
    func filterExpansionRevealsMatchesButLeavesExcludedFoldersCollapsed() async throws {
        try await Harness.run(folders: Self.treeFolders, files: Self.treeFiles, loadsTree: true) { harness in
            harness.workspace.navigatorFilter = ".js"

            harness.controller.handleFilterChange()

            let modules = try harness.file("node_modules")
            #expect(harness.outlineView.isItemExpanded(try harness.file("src")))
            #expect(harness.outlineView.isItemExpanded(try harness.file("src/deep")))
            #expect(harness.row(of: try harness.file("src/deep/y.js")) >= 0)
            #expect(!harness.outlineView.isItemExpanded(modules))
            #expect(harness.row(of: try harness.file("node_modules/pkg/i.js")) == -1)
        }
    }
}
