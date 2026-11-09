import Foundation
import Testing
@testable import Dreamder

@MainActor
@Suite(.serialized, .uiGate)
struct WorkspaceFileScopeConfigurationTests {
    @Test
    func theIgnoreGlobsOfTheInjectedSettingsExcludeFilesFromTheScope() throws {
        try withTempDir { directory in
            let settings = Dreamder.Settings(baseURL: directory.appending(path: "settings"))
            settings.preferences.search.ignoreGlobPatterns = [GlobPattern(value: "*.zzlog")]
            let root = directory.appending(path: "project", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let workspace = WorkspaceDocument()
            workspace.configureFileScope(rootURL: root, settings: settings)
            defer { workspace.tearDownFileScope() }

            let scope = try #require(workspace.fileScope)

            #expect(scope.isExcluded(root.appending(path: "build.zzlog"), isDirectory: false))
            #expect(!scope.isExcluded(root.appending(path: "main.swift"), isDirectory: false))
        }
    }
}
