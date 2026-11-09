import Foundation
@testable import Dreamder

@MainActor
final class WelcomeRecorder {
    var opened: [URL] = []
    var completesOpens = true
    var newProjectCalls = 0
    var openFromDiskCalls = 0
    var confirmed: [RecentProject] = []
    var confirmationAnswer = true
    var copied: [String] = []
    var revealed: [[URL]] = []
    var dismissals = 0

    func services() -> WelcomeServices {
        WelcomeServices(
            open: { url, completion in
                self.opened.append(url)
                if self.completesOpens { completion() }
            },
            newProject: { completion in
                self.newProjectCalls += 1
                completion()
            },
            openFromDisk: { completion in
                self.openFromDiskCalls += 1
                completion()
            },
            confirmRemoval: { project in
                self.confirmed.append(project)
                return self.confirmationAnswer
            },
            copyToClipboard: { self.copied.append($0) },
            reveal: { self.revealed.append($0) },
            dismiss: { self.dismissals += 1 },
            makeCloneViewModel: {
                var services = GitCloneServices()
                services.clipboardText = { nil }
                services.filePanels = FakeFilePanels()
                return GitCloneViewModel(services: services)
            }
        )
    }
}

@MainActor
func makeWelcomeManager(
    _ defaults: UserDefaults,
    paths: [String],
    directories: Bool = true
) -> RecentProjectsManager {
    let manager = RecentProjectsManager(defaults: defaults)
    for path in paths.reversed() {
        manager.markRecent(at: URL(filePath: path), isDirectory: directories)
    }
    return manager
}
