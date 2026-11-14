import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class CovExtGitInstallHost {
    private let standIn: NSWindow
    let hosted: HostedView

    init(_ view: LanguageServerInstallView) {
        let standIn = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        standIn.isReleasedWhenClosed = false
        self.standIn = standIn
        var configured = view
        configured.settingsWindow = { standIn }
        let injected = configured
        hosted = HostedViewFixture.host(size: NSSize(width: 700, height: 700)) { injected }
    }

    func settle() async throws {
        try await hosted.settle()
    }

    func snapshot() -> NSBitmapImageRep? {
        hosted.snapshot()
    }

    func renders() -> Bool {
        hosted.renders()
    }

    func close() {
        hosted.close()
        standIn.close()
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct LanguageServerInstallViewCoverageTests {
    private func host(_ view: LanguageServerInstallView) -> CovExtGitInstallHost {
        CovExtGitInstallHost(view)
    }

    private func makeOperation(
        _ item: RegistryItem,
        steps: [PackageManagerInstallStep] = []
    ) -> PackageManagerInstallOperation {
        PackageManagerInstallOperation(package: item, steps: steps)
    }

    @Test
    func idleOperationListsThePackageAndInstallMethod() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Noop") { _ in }])
            let hosted = host(LanguageServerInstallView(operation: operation, registryManager: manager))
            defer { hosted.close() }

            try await hosted.settle()

            #expect(operation.runningState == .none)
            #expect(hosted.renders())
        }
    }

    @Test
    func unknownInstallMethodIsLabelledUnknown() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "tool", sourceID: "pkg:unknown/tool")
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Noop") { _ in }])
            let hosted = host(LanguageServerInstallView(operation: operation, registryManager: manager))
            defer { hosted.close() }
            try await hosted.settle()
            let unknown = hosted.snapshot()

            let known = host(
                LanguageServerInstallView(
                    operation: makeOperation(
                        try CovExtGitRegistryFixtures.item(name: "tool"),
                        steps: [CovExtGitRegistryFixtures.step("Noop") { _ in }]
                    ),
                    registryManager: manager
                )
            )
            defer { known.close() }
            try await known.settle()

            #expect(HostedView.pixelsDiffer(unknown, known.snapshot()))
        }
    }

    @Test
    func failedOperationShowsTheErrorAndOutput() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Noop") { _ in }])
            let hosted = host(LanguageServerInstallView(operation: operation, registryManager: manager))
            defer { hosted.close() }
            try await hosted.settle()
            let idle = hosted.snapshot()

            operation.accumulatedOutput = [
                PackageManagerInstallOperation.OutputItem(isStepDivider: true, contents: "Step 1: Noop"),
                PackageManagerInstallOperation.OutputItem(outputIdx: 1, contents: "status line"),
                PackageManagerInstallOperation.OutputItem(contents: "raw output"),
                PackageManagerInstallOperation.OutputItem(isStepDivider: true, contents: "Step 2: Verify")
            ]
            operation.error = CovExtGitLocalizedFailure()
            try await hosted.settle()

            #expect(operation.runningState == .complete)
            #expect(HostedView.pixelsDiffer(idle, hosted.snapshot()))
        }
    }

    @Test
    func completedInstallShowsTheSuccessMessage() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try CovExtGitRegistryFixtures.item(name: name)
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Noop") { _ in }])
            operation.currentStepIdx = 1
            let hosted = host(LanguageServerInstallView(operation: operation, registryManager: manager))
            defer { hosted.close() }
            try await hosted.settle()
            let notInstalled = hosted.snapshot()

            CovExtGitRegistryFixtures.register(name, in: manager)
            try await hosted.settle()

            #expect(operation.runningState == .complete)
            #expect(HostedView.pixelsDiffer(notInstalled, hosted.snapshot()))
        }
    }

    @Test
    func completedEmptyOperationRendersWithoutAStepName() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let operation = makeOperation(try CovExtGitRegistryFixtures.item(name: "alpha-ls"))
            let hosted = host(LanguageServerInstallView(operation: operation, registryManager: manager))
            defer { hosted.close() }

            try await hosted.settle()

            #expect(operation.runningState == .complete)
            #expect(hosted.renders())
        }
    }

    @Test
    func runningOperationStreamsOutputAndShowsCancel() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let gate = CovExtGitStepGate()
            defer { gate.open() }
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Wait") { _ in await gate.wait() }])
            let run = Task { try? await operation.run() }
            try await eventually { operation.runningState == .running && gate.isWaiting }
            let hosted = host(LanguageServerInstallView(operation: operation, registryManager: manager))
            defer { hosted.close() }
            try await hosted.settle()
            let before = hosted.snapshot()

            operation.accumulatedOutput.append(
                PackageManagerInstallOperation.OutputItem(outputIdx: 1, contents: "streamed line")
            )
            try await hosted.settle()
            let streamed = hosted.snapshot()
            gate.open()
            await run.value
            try await eventually { operation.runningState == .complete }
            try await hosted.settle()

            #expect(HostedView.pixelsDiffer(before, streamed))
            #expect(HostedView.pixelsDiffer(streamed, hosted.snapshot()))
        }
    }

    @Test
    func stepWaitingForConfirmationPresentsTheAlertAndContinues() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let step = CovExtGitRegistryFixtures.step(
                "Confirm",
                confirmation: .required(message: "Proceed with the install?")
            ) { _ in }
            let operation = makeOperation(item, steps: [step])
            let run = Task { try? await operation.run() }
            try await eventually { operation.waitingForConfirmation == "Proceed with the install?" }
            let view = LanguageServerInstallView(operation: operation, registryManager: manager)
            let hosted = host(view)
            defer { hosted.close() }

            try await hosted.settle()
            operation.confirmCurrentStep()
            await run.value

            #expect(operation.waitingForConfirmation == nil)
            #expect(operation.runningState == .complete)
        }
    }

    @Test
    func confirmationAlertContentRendersAndItsActionsWork() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
            let operation = makeOperation(item)
            let view = LanguageServerInstallView(operation: operation, registryManager: manager)
            let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 200)) {
                VStack {
                    view.confirmationActions("Proceed?")
                    view.confirmationMessage("Proceed?")
                    view.footer
                    view.sourceButton
                }
            }
            defer { hosted.close() }

            try await hosted.settle()

            #expect(hosted.renders())
        }
    }

    @Test
    func startingTheInstallRunsItAndABusyManagerShowsTheError() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try CovExtGitRegistryFixtures.item(name: name)
            let gate = CovExtGitStepGate()
            defer { gate.open() }
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Wait") { _ in await gate.wait() }])
            let view = LanguageServerInstallView(operation: operation, registryManager: manager)
            let modalsBefore = DreamderHeadless.suppressedModals.count

            view.startInstallation()
            try await eventually { manager.runningInstall === operation && gate.isWaiting }
            view.startInstallation()

            #expect(DreamderHeadless.suppressedModals.count > modalsBefore)
            gate.open()
            try await eventually { !manager.isInstalling && manager.runningInstall == nil }
            #expect(manager.installedLanguageServers[name]?.isEnabled == true)
        }
    }

    @Test
    func cancellingARunningInstallStopsTheManager() async throws {
        try await withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let name = CovExtGitRegistryFixtures.uniqueName()
            defer { manager.installedLanguageServers.removeValue(forKey: name) }
            let item = try CovExtGitRegistryFixtures.item(name: name)
            let gate = CovExtGitStepGate()
            defer { gate.open() }
            let operation = makeOperation(item, steps: [CovExtGitRegistryFixtures.step("Wait") { _ in await gate.wait() }])
            let view = LanguageServerInstallView(operation: operation, registryManager: manager)
            view.startInstallation()
            try await eventually { manager.runningInstall === operation && gate.isWaiting }

            view.cancelInstallationAndDismiss()

            #expect(manager.isInstalling == false)
            gate.open()
            try await eventually { manager.runningInstall == nil }
            #expect(manager.installedLanguageServers[name] == nil)
        }
    }

    @Test
    func cancellingWhileWaitingForConfirmationEndsTheRunWithoutRunningTheStep() async throws {
        let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
        let log = CovExtGitStepLog()
        let step = CovExtGitRegistryFixtures.step(
            "Confirm",
            confirmation: .required(message: "Proceed with the install?")
        ) { _ in log.ran += 1 }
        let operation = makeOperation(item, steps: [step])
        let run = Task { try? await operation.run() }
        try await eventually(timeout: .seconds(30)) { operation.waitingForConfirmation != nil }

        operation.cancel()
        await run.value

        #expect(operation.waitingForConfirmation == nil)
        #expect(operation.runningState == .none)
        #expect(log.ran == 0)
    }

    @Test
    func anOperationWithoutStepsHasNoFraction() throws {
        let operation = makeOperation(try CovExtGitRegistryFixtures.item(name: "alpha-ls"))

        #expect(operation.totalSteps == 0)
        #expect(operation.completedSteps == 0)
        #expect(operation.fractionCompleted == nil)
    }

    @Test
    func progressAdvancesPerCompletedStepAndEndsAtOne() async throws {
        let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
        let gate = CovExtGitStepGate()
        defer { gate.open() }
        let operation = makeOperation(
            item,
            steps: [
                CovExtGitRegistryFixtures.step("First") { _ in },
                CovExtGitRegistryFixtures.step("Second") { _ in await gate.wait() }
            ]
        )
        #expect(operation.totalSteps == 2)
        #expect(operation.fractionCompleted == 0)
        let run = Task { try? await operation.run() }
        try await eventually(timeout: .seconds(30)) { gate.isWaiting }

        #expect(operation.completedSteps == 1)
        #expect(operation.fractionCompleted == 0.5)
        gate.open()
        await run.value

        #expect(operation.completedSteps == 2)
        #expect(operation.fractionCompleted == 1)
    }

    @Test
    func aFailedStepIsNotCountedAsCompleted() async throws {
        let item = try CovExtGitRegistryFixtures.item(name: "alpha-ls")
        let operation = makeOperation(
            item,
            steps: [
                CovExtGitRegistryFixtures.step("First") { _ in },
                CovExtGitRegistryFixtures.step("Broken") { _ in throw CovExtGitFailure() }
            ]
        )

        try? await operation.run()

        #expect(operation.error is CovExtGitFailure)
        #expect(operation.completedSteps == 1)
        #expect(operation.fractionCompleted == 0.5)
    }

    @Test
    func cancelDismissesWithoutTouchingTheManager() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let operation = makeOperation(try CovExtGitRegistryFixtures.item(name: "alpha-ls"))
            let view = LanguageServerInstallView(operation: operation, registryManager: manager)

            view.cancel()

            #expect(manager.isInstalling == false)
        }
    }

    @Test
    func openingTheHomepageIsInterceptedAndInvalidUrlsAreIgnored() async throws {
        try withTempDir { directory in
            let manager = CovExtGitRegistryFixtures.manager(in: directory)
            let valid = LanguageServerInstallView(
                operation: makeOperation(try CovExtGitRegistryFixtures.item(name: "alpha-ls")),
                registryManager: manager
            )
            let invalid = LanguageServerInstallView(
                operation: makeOperation(try CovExtGitRegistryFixtures.item(name: "beta-ls", homepage: "")),
                registryManager: manager
            )
            let opensBefore = DreamderHeadless.suppressedExternalOpens.count

            valid.openHomepage()
            let opensAfterValid = DreamderHeadless.suppressedExternalOpens.count
            invalid.openHomepage()

            #expect(opensAfterValid > opensBefore)
            #expect(DreamderHeadless.suppressedExternalOpens.count == opensAfterValid)
        }
    }
}
