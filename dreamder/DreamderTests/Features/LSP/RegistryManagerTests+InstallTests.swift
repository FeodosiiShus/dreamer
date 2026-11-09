import Foundation
import Synchronization
import Testing
@testable import Dreamder

@MainActor
private final class StepGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    private(set) var isWaiting = false

    func wait() async {
        if opened { return }
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func markWaiting() {
        isWaiting = true
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private final class TaskTitleLog: Sendable {
    let titles = Mutex<[String]>([])
}

@MainActor
private final class InstallTitleRecorder {
    private let log = TaskTitleLog()
    private var observer: NSObjectProtocol?

    init(id: String) {
        let log = log
        observer = NotificationCenter.default.addObserver(
            forName: .taskNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.userInfo?["id"] as? String == id,
                  let title = notification.userInfo?["title"] as? String else { return }
            log.titles.withLock { $0.append(title) }
        }
    }

    var titles: [String] {
        log.titles.withLock { $0 }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}

private struct StepFailure: Error {}

extension RegistryManagerTests {
    @Test
    func installOperationForANpmServerListsTheNpmSteps() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: "alpha-ls", sourceID: "pkg:npm/alpha-ls@1.0.0")

            let operation = try manager.installOperation(package: item)

            #expect(operation.package.name == "alpha-ls")
            #expect(operation.steps.map(\.name) == [
                "Initialize Directory Structure",
                "Install Package Using npm",
                "Verify Installation"
            ])
        }
    }

    @Test(arguments: ["pkg:nuget/Tool@1.0.0", "pkg:gem/tool@1.0.0", "pkg:unknown/tool"])
    func installOperationRejectsServersWithoutAUsableInstaller(sourceID: String) throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: "tool", sourceID: sourceID)

            #expect(isInvalidConfiguration(caught { try manager.installOperation(package: item) }))
        }
    }

    @Test
    func startingAnOperationWithoutAnInstallMethodIsRejected() throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: "tool", sourceID: "pkg:nuget/Tool@1.0.0")
            let operation = PackageManagerInstallOperation(package: item, steps: [])

            #expect(isInvalidConfiguration(caught { try manager.startInstallation(operation: operation) }))
            #expect(manager.isInstalling == false)
            #expect(manager.runningInstall == nil)
        }
    }

    @Test(arguments: ["../../x", "a;rm -rf ~", "-rf"], RegistryHostileSource.allCases)
    func installOperationRejectsAHostilePackageNameForEverySource(name: String, source: RegistryHostileSource) throws {
        try withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let item = try makeItem(name: name, sourceID: source.sourceID, sourceExtras: source.sourceExtras)
            let before = try snapshot(of: directory)

            let failure = caught { try manager.installOperation(package: item) }
            #expect(errorKind(failure) == "PackageManagerError.unsafeValue")
            #expect(try snapshot(of: directory) == before)
        }
    }

    @Test(arguments: ["../../x", "a;rm -rf ~", "-rf"])
    func installingFromHostileRegistryDataNeverStartsAProcess(name: String) async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let processes = ScriptedProcesses()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let before = try snapshot(of: directory)

            for source in RegistryHostileSource.allCases {
                let item = try makeItem(name: name, sourceID: source.sourceID, sourceExtras: source.sourceExtras)
                let steps = (try? manager.installOperation(package: item))?.steps ?? []
                #expect(steps.isEmpty)
                let operation = PackageManagerInstallOperation(
                    package: item,
                    steps: steps,
                    runner: processes.runner,
                    shellEnvironment: processes.shellEnvironment
                )

                try manager.startInstallation(operation: operation)
                try await eventually { !manager.isInstalling && manager.runningInstall == nil }
            }

            #expect(processes.invocations.isEmpty)
            #expect(try snapshot(of: directory) == before)
        }
    }

    @Test
    func successfulInstallRegistersTheServerEnabledAtTheInstalledVersion() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/\(name)@4.3.4")
            let gate = StepGate()
            let step = PackageManagerInstallStep(name: "Wait", confirmation: .none) { _ in
                await gate.wait()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)

            #expect(manager.isInstalling)
            try await eventually { manager.runningInstall === operation && gate.isWaiting }
            #expect(manager.installedLanguageServers[name] == nil)
            #expect(isInstallationRunning(caught { try manager.startInstallation(operation: operation) }))
            #expect(isInstallationRunning(caught { try manager.installOperation(package: item) }))

            gate.open()
            try await eventually { !manager.isInstalling && manager.runningInstall == nil }

            let installed = SettingsData.InstalledLanguageServer(packageName: name, isEnabled: true, version: "4.3.4")
            #expect(manager.installedLanguageServers[name] == installed)
            #expect(operation.error == nil)
        }
    }

    @Test
    func failedInstallLeavesTheServerUnregisteredAndNotifiesTheUser() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/\(name)@2.0.0")
            let step = PackageManagerInstallStep(name: "Fail", confirmation: .none) { _ in
                throw StepFailure()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)
            try await eventually { !manager.isInstalling && manager.runningInstall == nil }

            #expect(manager.installedLanguageServers[name] == nil)
            #expect(operation.error is StepFailure)
            try await eventually {
                NotificationManager.shared.notifications.contains { $0.title == "Could not install \(name)@2.0.0" }
            }
        }
    }

    @Test
    func cancellingAnInstallStopsItWithoutRegisteringTheServer() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/\(name)@1.0.0")
            let gate = StepGate()
            let step = PackageManagerInstallStep(name: "Sleep", confirmation: .none) { _ in
                gate.markWaiting()
                try await Task.sleep(for: .seconds(600))
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)
            try await eventually { gate.isWaiting }
            manager.cancelInstallation()

            #expect(manager.isInstalling == false)
            try await eventually { manager.runningInstall == nil }
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func installingAnUnrecognisedSourceRegistersTheServerWithoutAVersion() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/")
            let recorder = InstallTitleRecorder(id: name)
            defer { recorder.stop() }
            let gate = StepGate()
            let step = PackageManagerInstallStep(name: "Run", confirmation: .none) { _ in
                gate.markWaiting()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)
            try await eventually { !manager.isInstalling && manager.runningInstall == nil }

            let installed = SettingsData.InstalledLanguageServer(packageName: name, isEnabled: true, version: "")
            #expect(manager.installedLanguageServers[name] == installed)
            #expect(gate.isWaiting)
            #expect(recorder.titles == ["Installing \(name)@latest", "Successfully installed \(name)@latest"])
        }
    }

    @Test
    func cancellingAnInstallBeforeItStartsRunningSkipsEveryStep() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try makeItem(name: name, sourceID: "pkg:npm/")
            let recorder = InstallTitleRecorder(id: name)
            defer { recorder.stop() }
            let gate = StepGate()
            let step = PackageManagerInstallStep(name: "Run", confirmation: .none) { _ in
                gate.markWaiting()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])

            try manager.startInstallation(operation: operation)
            manager.cancelInstallation()
            try await eventually { !recorder.titles.isEmpty }

            #expect(recorder.titles == ["Installing \(name)@latest"])
            #expect(gate.isWaiting == false)
            #expect(manager.isInstalling == false)
            #expect(manager.runningInstall == nil)
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func theFailureNotificationOffersADoneActionThatChangesNothing() async throws {
        try await withTempDir { directory in
            let manager = makeOfflineManager(installPath: installPath(in: directory))
            let name = uniqueName()
            let item = try makeItem(name: name, sourceID: "pkg:npm/")
            let step = PackageManagerInstallStep(name: "Fail", confirmation: .none) { _ in
                throw StepFailure()
            }
            let operation = PackageManagerInstallOperation(package: item, steps: [step])
            let title = "Could not install \(name)@latest"

            try manager.startInstallation(operation: operation)
            try await eventually { NotificationManager.shared.notifications.contains { $0.title == title } }

            let notification = try #require(NotificationManager.shared.notifications.first { $0.title == title })
            let countBefore = NotificationManager.shared.notifications.count
            notification.action()

            #expect(notification.actionButtonTitle == "Done")
            #expect(NotificationManager.shared.notifications.count == countBefore)
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }
}
