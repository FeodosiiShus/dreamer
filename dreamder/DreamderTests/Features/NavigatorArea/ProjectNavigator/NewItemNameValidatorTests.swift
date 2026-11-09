import Foundation
import Testing
@testable import Dreamder

struct NewItemNameValidatorTests {
    private func makeValidator(
        root: URL,
        parent: URL? = nil,
        kind: NewItemKind = .file,
        home: URL? = nil
    ) -> NewItemNameValidator {
        NewItemNameValidator(
            rootURL: root,
            parentURL: parent ?? root,
            kind: kind,
            homeURL: home ?? root.appending(path: "home-default")
        )
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeFile(_ url: URL) throws {
        try makeDirectory(url.deletingLastPathComponent())
        try "x".write(to: url, atomically: true, encoding: .utf8)
    }

    @Test
    func kindNouns() {
        #expect(NewItemKind.file.noun == "file")
        #expect(NewItemKind.directory.noun == "directory")
    }

    @Test
    func errorMessagesForBothKinds() {
        #expect(NewItemNameError.empty.message(for: .file) == "Specify a file name")
        #expect(NewItemNameError.empty.message(for: .directory) == "Specify a directory name")
        #expect(NewItemNameError.invalidName("x").message(for: .file) == "'x' is an invalid file name")
        #expect(NewItemNameError.invalidName("x").message(for: .directory) == "'x' is an invalid directory name")
        #expect(NewItemNameError.fileExists("x").message(for: .file) == "A file with the name 'x' already exists")
        #expect(
            NewItemNameError.directoryExists("x").message(for: .directory)
                == "A directory with the name 'x' already exists"
        )
        #expect(NewItemNameError.outsideProject.message(for: .file) == "The file must be created inside the project")
        #expect(
            NewItemNameError.outsideProject.message(for: .directory)
                == "The directory must be created inside the project"
        )
    }

    @Test
    func planAnchorAndContainingDirectory() {
        let target = URL(filePath: "/p/a/b/c.txt")
        let withDirectories = NewItemPlan(
            kind: .file,
            target: target,
            directoriesToCreate: [URL(filePath: "/p/a"), URL(filePath: "/p/a/b")]
        )
        #expect(withDirectories.anchor.path == "/p")
        #expect(withDirectories.containingDirectory.path == "/p/a/b")
        let plain = NewItemPlan(kind: .file, target: URL(filePath: "/p/c.txt"), directoriesToCreate: [])
        #expect(plain.anchor.path == "/p")
        #expect(plain.containingDirectory.path == "/p")
    }

    @Test
    func simpleFileNamePlansInsideParent() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root).plan(for: "a.txt").get()
            #expect(plan.kind == .file)
            #expect(plan.target.path == root.appending(path: "a.txt").path)
            #expect(plan.directoriesToCreate.isEmpty)
        }
    }

    @Test
    func directoryKindIsCarriedIntoThePlan() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root, kind: .directory).plan(for: "dir").get()
            #expect(plan.kind == .directory)
            #expect(plan.target.path == root.appending(path: "dir").path)
        }
    }

    @Test
    func inputIsTrimmed() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root).plan(for: "  \n a.txt \t ").get()
            #expect(plan.target.path == root.appending(path: "a.txt").path)
        }
    }

    @Test
    func emptyAndBlankInputIsRejected() throws {
        try withTempDir { root in
            let validator = makeValidator(root: root)
            #expect(validator.plan(for: "") == .failure(.empty))
            #expect(validator.plan(for: "   ") == .failure(.empty))
            #expect(validator.plan(for: "///") == .failure(.empty))
            #expect(validator.errorMessage(for: "") == "Specify a file name")
            #expect(makeValidator(root: root, kind: .directory).errorMessage(for: " ") == "Specify a directory name")
        }
    }

    @Test
    func dotAndDotDotAsLastTokenAreInvalid() throws {
        try withTempDir { root in
            let validator = makeValidator(root: root)
            #expect(validator.plan(for: ".") == .failure(.invalidName(".")))
            #expect(validator.plan(for: "..") == .failure(.invalidName("..")))
            #expect(validator.plan(for: "a/..") == .failure(.invalidName("..")))
            #expect(validator.plan(for: "a/.") == .failure(.invalidName(".")))
            #expect(validator.errorMessage(for: "..") == "'..' is an invalid file name")
        }
    }

    @Test
    func colonIsInvalid() throws {
        try withTempDir { root in
            let validator = makeValidator(root: root)
            #expect(validator.plan(for: "bad:name") == .failure(.invalidName("bad:name")))
            #expect(validator.plan(for: "ok/bad:name") == .failure(.invalidName("bad:name")))
            #expect(validator.errorMessage(for: "bad:name") == "'bad:name' is an invalid file name")
            #expect(
                makeValidator(root: root, kind: .directory).errorMessage(for: "bad:name")
                    == "'bad:name' is an invalid directory name"
            )
        }
    }

    @Test
    func tooLongNameIsInvalid() throws {
        try withTempDir { root in
            let name = String(repeating: "a", count: 256)
            #expect(makeValidator(root: root).plan(for: name) == .failure(.invalidName(name)))
            let allowed = String(repeating: "a", count: 255)
            let plan = try makeValidator(root: root).plan(for: allowed).get()
            #expect(plan.target.lastPathComponent == allowed)
        }
    }

    @Test
    func whitespaceOnlyTokenIsInvalid() throws {
        try withTempDir { root in
            #expect(makeValidator(root: root).plan(for: "a/ /b") == .failure(.invalidName(" ")))
        }
    }

    @Test
    func existingFileIsRejectedAsLastToken() throws {
        try withTempDir { root in
            try makeFile(root.appending(path: "a.txt"))
            let validator = makeValidator(root: root)
            #expect(validator.plan(for: "a.txt") == .failure(.fileExists("a.txt")))
            #expect(validator.errorMessage(for: "a.txt") == "A file with the name 'a.txt' already exists")
            #expect(
                makeValidator(root: root, kind: .directory).plan(for: "a.txt") == .failure(.fileExists("a.txt"))
            )
        }
    }

    @Test
    func existingFileIsRejectedAsIntermediateToken() throws {
        try withTempDir { root in
            try makeFile(root.appending(path: "a.txt"))
            #expect(makeValidator(root: root).plan(for: "a.txt/b.txt") == .failure(.fileExists("a.txt")))
        }
    }

    @Test
    func existingDirectoryIsRejectedAsLastToken() throws {
        try withTempDir { root in
            try makeDirectory(root.appending(path: "dir"))
            let fileValidator = makeValidator(root: root)
            let directoryValidator = makeValidator(root: root, kind: .directory)
            #expect(fileValidator.plan(for: "dir") == .failure(.directoryExists("dir")))
            #expect(directoryValidator.plan(for: "dir") == .failure(.directoryExists("dir")))
            #expect(directoryValidator.errorMessage(for: "dir") == "A directory with the name 'dir' already exists")
        }
    }

    @Test
    func existingDirectoryAsIntermediateTokenNeedsNoCreation() throws {
        try withTempDir { root in
            try makeDirectory(root.appending(path: "dir"))
            let plan = try makeValidator(root: root).plan(for: "dir/new.txt").get()
            #expect(plan.target.path == root.appending(path: "dir/new.txt").path)
            #expect(plan.directoriesToCreate.isEmpty)
            #expect(plan.anchor.path == root.appending(path: "dir").path)
        }
    }

    @Test
    func nestedPathCollectsMissingDirectories() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root).plan(for: "a/b/c.swift").get()
            #expect(plan.target.path == root.appending(path: "a/b/c.swift").path)
            #expect(plan.directoriesToCreate.map(\.path) == [
                root.appending(path: "a").path,
                root.appending(path: "a/b").path
            ])
            #expect(plan.anchor.path == root.path)
            #expect(plan.containingDirectory.path == root.appending(path: "a/b").path)
        }
    }

    @Test
    func nestedDirectoryKindCollectsMissingDirectories() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root, kind: .directory).plan(for: "x/y/z").get()
            #expect(plan.kind == .directory)
            #expect(plan.target.path == root.appending(path: "x/y/z").path)
            #expect(plan.directoriesToCreate.map(\.path) == [
                root.appending(path: "x").path,
                root.appending(path: "x/y").path
            ])
        }
    }

    @Test
    func missingDirectoriesBelowAnExistingOneStartAfterIt() throws {
        try withTempDir { root in
            try makeDirectory(root.appending(path: "dir"))
            let plan = try makeValidator(root: root).plan(for: "dir/a/b.txt").get()
            #expect(plan.directoriesToCreate.map(\.path) == [root.appending(path: "dir/a").path])
            #expect(plan.anchor.path == root.appending(path: "dir").path)
        }
    }

    @Test
    func leadingAndTrailingSlashesAreIgnored() throws {
        try withTempDir { root in
            let leading = try makeValidator(root: root).plan(for: "/a.txt").get()
            #expect(leading.target.path == root.appending(path: "a.txt").path)
            #expect(leading.directoriesToCreate.isEmpty)
            let doubled = try makeValidator(root: root).plan(for: "a//b.txt").get()
            #expect(doubled.target.path == root.appending(path: "a/b.txt").path)
            let trailing = try makeValidator(root: root, kind: .directory).plan(for: "dir/").get()
            #expect(trailing.target.path == root.appending(path: "dir").path)
        }
    }

    @Test
    func dotTokensAreSkipped() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root).plan(for: "./a/./b.txt").get()
            #expect(plan.target.path == root.appending(path: "a/b.txt").path)
            #expect(plan.directoriesToCreate.map(\.path) == [root.appending(path: "a").path])
        }
    }

    @Test
    func dotDotGoesUpInsideTheProject() throws {
        try withTempDir { root in
            let sub = root.appending(path: "sub")
            try makeDirectory(sub)
            let plan = try makeValidator(root: root, parent: sub).plan(for: "../up.txt").get()
            #expect(plan.target.path == root.appending(path: "up.txt").path)
            #expect(plan.directoriesToCreate.isEmpty)
        }
    }

    @Test
    func dotDotCancelsAMissingDirectory() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root).plan(for: "a/b/../c.txt").get()
            #expect(plan.target.path == root.appending(path: "a/c.txt").path)
            #expect(plan.directoriesToCreate.map(\.path) == [root.appending(path: "a").path])
        }
    }

    @Test
    func dotDotOutOfTheProjectIsRejected() throws {
        try withTempDir { root in
            let validator = makeValidator(root: root)
            #expect(validator.plan(for: "../outside.txt") == .failure(.outsideProject))
            #expect(validator.plan(for: "../../outside.txt") == .failure(.outsideProject))
            #expect(validator.errorMessage(for: "../outside.txt") == "The file must be created inside the project")
            #expect(
                makeValidator(root: root, kind: .directory).errorMessage(for: "../outside")
                    == "The directory must be created inside the project"
            )
        }
    }

    @Test
    func siblingWithSharedPrefixIsOutsideTheProject() throws {
        try withTempDir { base in
            let root = base.appending(path: "proj")
            try makeDirectory(root)
            #expect(makeValidator(root: root).plan(for: "../proj2/x.txt") == .failure(.outsideProject))
        }
    }

    @Test
    func tildeResolvesToTheHomeDirectory() throws {
        try withTempDir { root in
            let home = root.appending(path: "home")
            try makeDirectory(home)
            let plan = try makeValidator(root: root, home: home).plan(for: "~/x.txt").get()
            #expect(plan.target.path == home.appending(path: "x.txt").path)
            #expect(plan.directoriesToCreate.isEmpty)
        }
    }

    @Test
    func tildeOutsideTheProjectIsRejected() throws {
        try withTempDir { base in
            let root = base.appending(path: "proj")
            let home = base.appending(path: "home")
            try makeDirectory(root)
            try makeDirectory(home)
            let validator = makeValidator(root: root, home: home)
            #expect(validator.plan(for: "~/x.txt") == .failure(.outsideProject))
            #expect(validator.errorMessage(for: "~/x.txt") == "The file must be created inside the project")
        }
    }

    @Test
    func tildeInTheMiddleIsAnOrdinaryName() throws {
        try withTempDir { root in
            let plan = try makeValidator(root: root).plan(for: "a/~/b.txt").get()
            #expect(plan.target.path == root.appending(path: "a/~/b.txt").path)
        }
    }

    @Test
    func tildeAloneAsLastTokenIsTheHomeDirectory() throws {
        try withTempDir { root in
            let home = root.appending(path: "home")
            try makeDirectory(home)
            #expect(makeValidator(root: root, home: home).plan(for: "~") == .success(
                NewItemPlan(kind: .file, target: home, directoriesToCreate: [])
            ))
        }
    }

    @Test
    func rootWithTrailingSlashesIsHandled() throws {
        try withTempDir { root in
            let slashed = URL(filePath: root.path + "//")
            let validator = NewItemNameValidator(rootURL: slashed, parentURL: root, kind: .file)
            let plan = try validator.plan(for: "a.txt").get()
            #expect(plan.target.path == root.appending(path: "a.txt").path)
            #expect(validator.plan(for: "../a.txt") == .failure(.outsideProject))
        }
    }

    @Test
    func filesystemRootAcceptsEveryAbsolutePath() throws {
        try withTempDir { dir in
            let validator = NewItemNameValidator(
                rootURL: URL(filePath: "/"),
                parentURL: dir,
                kind: .file,
                homeURL: dir
            )
            let plan = try validator.plan(for: "a.txt").get()
            #expect(plan.target.path == dir.appending(path: "a.txt").path)
        }
    }

    @Test
    func defaultHomeDirectoryIsTheCurrentUsers() throws {
        try withTempDir { root in
            let validator = NewItemNameValidator(rootURL: root, parentURL: root, kind: .file)
            #expect(validator.homeURL == FileManager.default.homeDirectoryForCurrentUser)
        }
    }

    @Test
    func errorMessageIsNilForAValidName() throws {
        try withTempDir { root in
            #expect(makeValidator(root: root).errorMessage(for: "fine.txt") == nil)
        }
    }
}
