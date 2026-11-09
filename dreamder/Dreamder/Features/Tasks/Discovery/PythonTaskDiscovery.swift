import Foundation

nonisolated enum PythonTaskDiscovery {
    private static let testsDirectoryName = "tests"
    private static let mainScriptName = "main.py"
    private static let configurationNames = ["pyproject.toml", "pytest.ini"]
    private static let virtualEnvironmentInterpreter = ".venv/bin/python"

    static func group(in directory: ScannedDirectory) -> DiscoveredTaskGroup? {
        let hasVirtualEnvironment = FileManager.default.fileExists(
            atPath: directory.fileURL(virtualEnvironmentInterpreter).path(percentEncoded: false)
        )
        let hasTests = containsPythonFile(in: directory)
        let hasMainScript = directory.fileNames.contains(mainScriptName)

        var entries: [TaskEntry] = []
        if hasTests {
            entries.append(TaskEntry(
                name: "pytest",
                command: hasVirtualEnvironment ? "\(virtualEnvironmentInterpreter) -m pytest" : "pytest",
                manifestName: testsDirectoryName
            ))
        }
        if hasMainScript {
            entries.append(TaskEntry(
                name: "python \(mainScriptName)",
                command: "\(hasVirtualEnvironment ? virtualEnvironmentInterpreter : "python3") \(mainScriptName)",
                manifestName: mainScriptName
            ))
        }

        var manifestNames = configurationNames.filter { directory.fileNames.contains($0) }
        if hasTests {
            manifestNames.append(testsDirectoryName)
        }
        if hasMainScript {
            manifestNames.append(mainScriptName)
        }
        guard let manifestName = manifestNames.first else { return nil }
        return directory.group(kind: .python, manifestName: manifestName, entries: entries)
    }

    private static func containsPythonFile(in directory: ScannedDirectory) -> Bool {
        guard directory.subdirectoryNames.contains(testsDirectoryName) else { return false }
        let path = directory.fileURL(testsDirectoryName).path(percentEncoded: false)
        return (try? FileManager.default.contentsOfDirectory(atPath: path))?.contains { $0.hasSuffix(".py") } ?? false
    }
}
