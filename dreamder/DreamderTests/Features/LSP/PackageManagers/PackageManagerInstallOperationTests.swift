import Foundation
import Testing
@testable import Dreamder

private struct StepFailure: Error {}

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
private func makeStep(
    _ name: String,
    confirmation: InstallStepConfirmation = .none,
    handler: @escaping @MainActor (PackageManagerProgressModel) async throws -> Void = { _ in }
) -> PackageManagerInstallStep {
    PackageManagerInstallStep(name: name, confirmation: confirmation, handler: handler)
}

@MainActor
@Suite(.uiGate)
struct PackageManagerInstallOperationTests {
    private func makeOperation(
        steps: [PackageManagerInstallStep],
        shell: ScriptedProcesses = ScriptedProcesses()
    ) throws -> PackageManagerInstallOperation {
        PackageManagerInstallOperation(
            package: try PackageManagerFixtures.registryItem(name: "operation-ls"),
            steps: steps,
            runner: shell.runner,
            shellEnvironment: shell.shellEnvironment
        )
    }

    @Test
    func stepIdentityIsItsName() {
        #expect(makeStep("Install").id == "Install")
    }

    @Test
    func identityIsThePackageName() throws {
        let operation = try makeOperation(steps: [])
        #expect(operation.id == "operation-ls")
        #expect(operation.package.name == "operation-ls")
    }

    @Test
    func anOperationWithoutStepsHasNoProgressFraction() throws {
        let operation = try makeOperation(steps: [])
        #expect(operation.fractionCompleted == nil)
        #expect(operation.totalSteps == 0)
        #expect(operation.currentStep == nil)
        #expect(operation.runningState == .complete)
    }

    @Test
    func aFreshOperationWaitsAtItsFirstStep() throws {
        let operation = try makeOperation(steps: [makeStep("A"), makeStep("B")])
        #expect(operation.runningState == .none)
        #expect(operation.currentStep?.name == "A")
        #expect(operation.totalSteps == 2)
        #expect(operation.completedSteps == 0)
        #expect(operation.fractionCompleted == 0)
        #expect(operation.waitingForConfirmation == nil)
        #expect(operation.error == nil)
    }

    @Test
    func stepsRunInOrderAndTheirOutputIsCollected() async throws {
        let shell = ScriptedProcesses { _ in FakeProcessRunner.output("hi\n") }
        let steps = [
            makeStep("A") { model in
                model.status("a-status")
                try await model.run(["npm", "--version"])
            },
            makeStep("B") { model in
                model.status("b-status")
            }
        ]
        let operation = try makeOperation(steps: steps, shell: shell)

        try await operation.run()

        #expect(operation.accumulatedOutput.map(\.contents) == [
            "Step 1: A", "a-status", "npm --version", "hi", "Step 2: B", "b-status"
        ])
        #expect(operation.accumulatedOutput.map(\.isStepDivider) == [true, false, false, false, true, false])
        #expect(operation.accumulatedOutput.map(\.outputIdx) == [nil, 1, 2, nil, nil, 3])
        #expect(shell.commands == ["npm --version"])
        #expect(shell.arguments == [["npm", "--version"]])
        #expect(operation.runningState == .complete)
        #expect(operation.currentStepIdx == 2)
        #expect(operation.completedSteps == 2)
        #expect(operation.fractionCompleted == 1)
        #expect(operation.currentStep == nil)
        #expect(operation.error == nil)
    }

    @Test
    func aFailingStepStopsTheOperationAndReportsTheError() async throws {
        let ranLast = Counter()
        let steps = [
            makeStep("A"),
            makeStep("B") { _ in throw StepFailure() },
            makeStep("C") { _ in ranLast.value += 1 }
        ]
        let operation = try makeOperation(steps: steps)

        await #expect(throws: StepFailure.self) {
            try await operation.run()
        }

        #expect(operation.error is StepFailure)
        #expect(ranLast.value == 0)
        #expect(operation.currentStepIdx == 2)
        #expect(operation.completedSteps == 1)
        #expect(operation.fractionCompleted == 1.0 / 3.0)
        #expect(operation.runningState == .complete)
        #expect(operation.accumulatedOutput.map(\.contents) == ["Step 1: A", "Step 2: B"])
    }

    @Test
    func runningAgainAfterAFailureDoesNothing() async throws {
        let attempts = Counter()
        let operation = try makeOperation(steps: [makeStep("A") { _ in
            attempts.value += 1
            throw StepFailure()
        }])

        await #expect(throws: StepFailure.self) { try await operation.run() }
        try await operation.run()

        #expect(attempts.value == 1)
    }

    @Test
    func confirmationHaltsTheOperationUntilTheUserConfirms() async throws {
        let ran = Counter()
        let operation = try makeOperation(steps: [
            makeStep("Confirm", confirmation: .required(message: "Proceed?")) { _ in ran.value += 1 }
        ])

        let run = Task { try await operation.run() }
        try await eventually(timeout: .seconds(30)) { operation.waitingForConfirmation == "Proceed?" }
        #expect(operation.runningState == .running)
        #expect(ran.value == 0)

        try await operation.run()
        #expect(operation.waitingForConfirmation == "Proceed?")

        operation.confirmCurrentStep()
        try await run.value

        #expect(ran.value == 1)
        #expect(operation.waitingForConfirmation == nil)
        #expect(operation.runningState == .complete)
    }

    @Test
    func cancellingWhileWaitingForConfirmationSkipsTheStep() async throws {
        let ran = Counter()
        let operation = try makeOperation(steps: [
            makeStep("Confirm", confirmation: .required(message: "Proceed?")) { _ in ran.value += 1 }
        ])

        let run = Task { try await operation.run() }
        try await eventually(timeout: .seconds(30)) { operation.waitingForConfirmation != nil }

        operation.cancel()

        await #expect(throws: CancellationError.self) {
            try await run.value
        }
        #expect(ran.value == 0)
        #expect(operation.waitingForConfirmation == nil)
        #expect(operation.currentStepIdx == 0)
    }

    @Test
    func cancellingAnIdleOperationIsHarmless() throws {
        let operation = try makeOperation(steps: [makeStep("A")])
        operation.cancel()
        #expect(operation.runningState == .none)
        #expect(operation.waitingForConfirmation == nil)
    }
}
