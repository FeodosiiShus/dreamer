import Foundation
import Testing
@testable import Dreamder

struct FileTemplatesTests {
    private func context(_ fileName: String = "Main.swift", directory: String = "my-app") -> FileTemplateContext {
        FileTemplateContext(fileName: fileName, directory: URL(filePath: "/work/" + directory))
    }

    private func writeOverride(_ root: URL, _ fileName: String, _ data: Data) throws {
        let directory = root.appending(path: FileTemplateStore.overrideDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appending(path: fileName))
    }

    private func text(_ data: Data?) -> String? {
        data.flatMap { String(data: $0, encoding: .utf8) }
    }

    @Test
    func contextStripsTheExtensionFromTheName() {
        #expect(context("Main.swift").name == "Main")
        #expect(context("archive.tar.gz").name == "archive.tar")
        #expect(context("Makefile").name == "Makefile")
    }

    @Test
    func packageNameReplacesInvalidCharacters() {
        #expect(FileTemplateContext.packageName(forDirectory: URL(filePath: "/a/my-app")) == "my_app")
        #expect(FileTemplateContext.packageName(forDirectory: URL(filePath: "/a/my app.v2")) == "my_app_v2")
        #expect(FileTemplateContext.packageName(forDirectory: URL(filePath: "/a/snake_case")) == "snake_case")
        #expect(FileTemplateContext.packageName(forDirectory: URL(filePath: "/a/café")) == "café")
    }

    @Test
    func packageNameGetsUnderscorePrefixForLeadingDigit() {
        #expect(FileTemplateContext.packageName(forDirectory: URL(filePath: "/a/123")) == "_123")
        #expect(FileTemplateContext.packageName(forDirectory: URL(filePath: "/a/1-x")) == "_1_x")
    }

    @Test
    func packageNameFallsBackToMainForAnEmptyDirectoryName() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(url.lastPathComponent.isEmpty)
        #expect(FileTemplateContext.packageName(forDirectory: url) == "main")
    }

    @Test
    func contextUsesPackageNameOfTheDirectory() {
        #expect(context("server.go", directory: "my-app").packageName == "my_app")
    }

    @Test
    func rendererSubstitutesAllVariables() {
        let rendered = FileTemplateRenderer.render(
            "// ${NAME} in ${PACKAGE_NAME}\n// ${NAME}",
            context: context("Main.swift", directory: "my-app")
        )
        #expect(rendered == "// Main in my_app\n// Main")
    }

    @Test
    func rendererKeepsUnknownVariables() {
        #expect(FileTemplateRenderer.render("a ${UNKNOWN} b ${NAME}", context: context()) == "a ${UNKNOWN} b Main")
    }

    @Test
    func rendererKeepsAnUnterminatedOpening() {
        #expect(FileTemplateRenderer.render("a ${NAME} b ${NAME", context: context()) == "a Main b ${NAME")
    }

    @Test
    func rendererLeavesTextWithoutVariablesAlone() {
        #expect(FileTemplateRenderer.render("plain $ { text }\n", context: context()) == "plain $ { text }\n")
        #expect(FileTemplateRenderer.render("", context: context()) == "")
    }

    @Test
    func builtInTemplatesMatchTheSpecification() {
        #expect(FileTemplateStore.builtIn["swift"] == "import Foundation\n")
        #expect(FileTemplateStore.builtIn["md"] == "# ${NAME}\n")
        #expect(FileTemplateStore.builtIn["go"] == "package ${PACKAGE_NAME}\n")
        for emptyExtension in ["ts", "js", "py", "rs"] {
            #expect(FileTemplateStore.builtIn[emptyExtension] == "")
        }
    }

    @Test
    func templateForExtensionUsesBuiltIns() throws {
        try withTempDir { root in
            let store = FileTemplateStore(rootURL: root)
            #expect(store.template(forExtension: "swift") == "import Foundation\n")
            #expect(store.template(forExtension: "SWIFT") == "import Foundation\n")
            #expect(store.template(forExtension: "ts") == "")
        }
    }

    @Test
    func templateForEmptyOrUnknownExtensionIsNil() throws {
        try withTempDir { root in
            let store = FileTemplateStore(rootURL: root)
            #expect(store.template(forExtension: "") == nil)
            #expect(store.template(forExtension: "xyz") == nil)
        }
    }

    @Test
    func overrideBeatsBuiltIn() throws {
        try withTempDir { root in
            try writeOverride(root, "swift.txt", Data("// override\n".utf8))
            let store = FileTemplateStore(rootURL: root)
            #expect(store.template(forExtension: "swift") == "// override\n")
            #expect(store.template(forExtension: "Swift") == "// override\n")
        }
    }

    @Test
    func overrideWorksForExtensionsWithoutBuiltIn() throws {
        try withTempDir { root in
            try writeOverride(root, "xyz.txt", Data("custom".utf8))
            #expect(FileTemplateStore(rootURL: root).template(forExtension: "xyz") == "custom")
        }
    }

    @Test
    func emptyOverrideIsValid() throws {
        try withTempDir { root in
            try writeOverride(root, "swift.txt", Data())
            #expect(FileTemplateStore(rootURL: root).template(forExtension: "swift") == "")
        }
    }

    @Test
    func nonUTF8OverrideFallsBackToBuiltIn() throws {
        try withTempDir { root in
            try writeOverride(root, "swift.txt", Data([0xFF, 0xFE, 0xFD]))
            #expect(FileTemplateStore(rootURL: root).template(forExtension: "swift") == "import Foundation\n")
        }
    }

    @Test
    func unreadableOverrideFallsBackToBuiltIn() throws {
        try withTempDir { root in
            let directory = root.appending(path: FileTemplateStore.overrideDirectory)
            try FileManager.default.createDirectory(
                at: directory.appending(path: "swift.txt"),
                withIntermediateDirectories: true
            )
            #expect(FileTemplateStore(rootURL: root).template(forExtension: "swift") == "import Foundation\n")
        }
    }

    @Test
    func contentsRendersBuiltInTemplates() throws {
        try withTempDir { root in
            let store = FileTemplateStore(rootURL: root)
            let directory = URL(filePath: "/work/my-app")
            #expect(text(store.contents(forFileNamed: "Main.swift", in: directory)) == "import Foundation\n")
            #expect(text(store.contents(forFileNamed: "notes.md", in: directory)) == "# notes\n")
            #expect(text(store.contents(forFileNamed: "server.go", in: directory)) == "package my_app\n")
        }
    }

    @Test
    func contentsIsNilWithoutATemplate() throws {
        try withTempDir { root in
            let store = FileTemplateStore(rootURL: root)
            let directory = URL(filePath: "/work/app")
            #expect(store.contents(forFileNamed: "data.xyz", in: directory) == nil)
            #expect(store.contents(forFileNamed: "Makefile", in: directory) == nil)
            #expect(store.contents(forFileNamed: "a.ts", in: directory) == nil)
            #expect(store.contents(forFileNamed: "a.rs", in: directory) == nil)
        }
    }

    @Test
    func contentsRendersOverrideVariables() throws {
        try withTempDir { root in
            try writeOverride(root, "swift.txt", Data("// ${NAME} in ${PACKAGE_NAME}\n".utf8))
            let data = FileTemplateStore(rootURL: root).contents(
                forFileNamed: "Main.swift",
                in: URL(filePath: "/work/my-app")
            )
            #expect(text(data) == "// Main in my_app\n")
        }
    }

    @Test
    func contentsIsNilForAnEmptyOverride() throws {
        try withTempDir { root in
            try writeOverride(root, "swift.txt", Data())
            #expect(FileTemplateStore(rootURL: root).contents(
                forFileNamed: "Main.swift",
                in: URL(filePath: "/work/app")
            ) == nil)
        }
    }
}
