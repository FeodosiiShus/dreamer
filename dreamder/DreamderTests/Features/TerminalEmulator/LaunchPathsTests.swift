import Foundation
import Testing
@testable import Dreamder

struct LaunchPathsTests {
    private func makeFile(named name: String, permissions: Int, in directory: URL) throws -> String {
        let url = directory.appending(path: name)
        let path = url.path(percentEncoded: false)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        return path
    }

    @Test
    func anExecutableRegularFileIsAcceptedAsAShell() throws {
        try withTempDir { directory in
            let path = try makeFile(named: "shell", permissions: 0o755, in: directory)

            #expect(LaunchPaths.isExecutableFile(atPath: path))
        }
    }

    @Test
    func aFileWithoutTheExecuteBitIsRejected() throws {
        try withTempDir { directory in
            let path = try makeFile(named: "shell", permissions: 0o644, in: directory)

            #expect(!LaunchPaths.isExecutableFile(atPath: path))
        }
    }

    @Test
    func aDirectoryIsNeverAnExecutableFile() throws {
        try withTempDir { directory in
            #expect(!LaunchPaths.isExecutableFile(atPath: directory.path(percentEncoded: false)))
        }
    }

    @Test
    func aMissingPathIsNeitherAnExecutableFileNorADirectory() throws {
        try withTempDir { directory in
            let missing = directory.appending(path: "missing").path(percentEncoded: false)

            #expect(!LaunchPaths.isExecutableFile(atPath: missing))
            #expect(!LaunchPaths.isExistingDirectory(atPath: missing))
        }
    }

    @Test
    func onlyDirectoriesAreExistingDirectories() throws {
        try withTempDir { directory in
            let file = try makeFile(named: "file", permissions: 0o644, in: directory)

            #expect(LaunchPaths.isExistingDirectory(atPath: directory.path(percentEncoded: false)))
            #expect(!LaunchPaths.isExistingDirectory(atPath: file))
        }
    }

    @Test
    func theSystemShellsAreExecutableFiles() {
        #expect(LaunchPaths.isExecutableFile(atPath: Shell.zsh.defaultPath))
        #expect(LaunchPaths.isExecutableFile(atPath: Shell.bash.defaultPath))
    }
}
