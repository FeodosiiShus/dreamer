import Foundation
import Observation

extension WorkspaceDocument {
    func configureFileScope(rootURL: URL, settings: Settings = .shared) {
        let scope = WorkspaceFileScope(rootURL: rootURL)
        scope.setIgnoreGlobs(settings.preferences.search.ignoreGlobPatterns.map(\.value))
        scope.startWatching()
        fileScope = scope
        symbolIndex = SearchEverywhereSymbolIndex(scope: scope)

        let observer = WorkspaceFileScopeObserver(scope: scope)
        fileScopeObserver = observer
        workspaceFileManager?.addObserver(observer)

        let globsTask = Task { [weak self] in
            for await globs in Observations({ Settings.shared.preferences.search.ignoreGlobPatterns.map(\.value) }) {
                self?.fileScope?.setIgnoreGlobs(globs)
            }
        }
        let exclusionsTask = Task { [weak self] in
            var isInitialValue = true
            for await _ in Observations({ [weak self] in self?.excludedDirectories?.rules }) {
                if isInitialValue {
                    isInitialValue = false
                    continue
                }
                self?.fileScope?.reload()
            }
        }
        fileScopeTasks = [globsTask, exclusionsTask]
    }

    func tearDownFileScope() {
        fileScopeTasks.forEach { $0.cancel() }
        fileScopeTasks = []
        symbolIndex = nil
        fileScopeObserver = nil
        fileScope?.cleanUp()
        fileScope = nil
    }
}
