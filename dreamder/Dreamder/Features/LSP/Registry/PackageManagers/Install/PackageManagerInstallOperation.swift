//
//  PackageManagerInstallOperation.swift
//  Dreamder
//
//  Created by Khan Winter on 8/8/25.
//

import Foundation
import Observation

/// An executable install operation for installing a ``RegistryItem``.
///
/// Has a single entry point, ``run()``, which kicks off the operation. UI can observe properties like the ``error``,
/// ``runningState-swift.property``, or ``currentStep`` to monitor progress.
///
/// If a step requires confirmation, the ``waitingForConfirmation`` value will be filled.
@MainActor
@Observable
final class PackageManagerInstallOperation: Identifiable {
    enum RunningState {
        case none
        case running
        case complete
    }

    struct OutputItem: Identifiable, Equatable {
        let id: UUID = UUID()
        let isStepDivider: Bool
        let outputIdx: Int?
        let contents: String

        init(outputIdx: Int? = nil, isStepDivider: Bool = false, contents: String) {
            self.isStepDivider = isStepDivider
            self.outputIdx = outputIdx
            self.contents = contents
        }
    }

    nonisolated var id: String { package.name }

    let package: RegistryItem
    let steps: [PackageManagerInstallStep]

    /// The step the operation is currently executing or stopped at.
    var currentStep: PackageManagerInstallStep? {
        steps[safe: currentStepIdx]
    }

    /// The current state of the operation.
    var runningState: RunningState {
        if operationTask != nil {
            return .running
        } else if error != nil || currentStepIdx == steps.count {
            return .complete
        } else {
            return .none
        }
    }

    var accumulatedOutput: [OutputItem] = []
    var currentStepIdx: Int = 0
    var error: Error?

    var totalSteps: Int { steps.count }

    var completedSteps: Int {
        let failedStep = error == nil ? 0 : 1
        return max(0, min(currentStepIdx - failedStep, steps.count))
    }

    var fractionCompleted: Double? {
        guard !steps.isEmpty else { return nil }
        return Double(completedSteps) / Double(steps.count)
    }

    /// If non-nil, indicates that this operation has halted and requires confirmation.
    public private(set) var waitingForConfirmation: String?

    private let runner: any ProcessRunning
    private let shellEnvironment: ShellEnvironment
    @ObservationIgnored
    private var operationTask: Task<Void, Error>?
    @ObservationIgnored
    private var confirmationContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored
    private var outputIdx = 0

    /// Create a new operation using a list of steps and a package description.
    /// See ``PackageManagerProtocol`` for 
    /// - Parameters:
    ///   - package: The package to install.
    ///   - steps: The steps that make up the operation.
    init(
        package: RegistryItem,
        steps: [PackageManagerInstallStep],
        runner: any ProcessRunning = ProcessRunner(),
        shellEnvironment: ShellEnvironment = .shared
    ) {
        self.package = package
        self.steps = steps
        self.runner = runner
        self.shellEnvironment = shellEnvironment
    }

    func run() async throws {
        guard operationTask == nil else { return }
        operationTask = Task {
            defer { operationTask = nil }
            try await runNext()
        }
        try await operationTask?.value
    }

    func cancel() {
        operationTask?.cancel()
        operationTask = nil
        confirmCurrentStep()
    }

    /// Called by UI to confirm continuing to the next step
    func confirmCurrentStep() {
        waitingForConfirmation = nil
        confirmationContinuation?.resume()
        confirmationContinuation = nil
    }

    private func waitForConfirmation(message: String) async {
        waitingForConfirmation = message
        await withCheckedContinuation { [weak self] (continuation: CheckedContinuation<Void, Never>) in
            self?.confirmationContinuation = continuation
        }
    }

    private func runNext() async throws {
        guard currentStepIdx < steps.count, error == nil else {
            return
        }

        let task = steps[currentStepIdx]

        switch task.confirmation {
        case .required(let message):
            await waitForConfirmation(message: message)
        case .none:
            break
        }

        let model = PackageManagerProgressModel(runner: runner, shellEnvironment: shellEnvironment)

        try Task.checkCancellation()
        accumulatedOutput.append(OutputItem(isStepDivider: true, contents: "Step \(currentStepIdx + 1): \(task.name)"))

        let handler = task.handler
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await outputItem in model.outputStream {
                    await MainActor.run {
                        switch outputItem {
                        case .status(let string):
                            self.outputIdx += 1
                            self.accumulatedOutput.append(OutputItem(outputIdx: self.outputIdx, contents: string))
                        case .output(let string):
                            self.accumulatedOutput.append(OutputItem(contents: string))
                        }
                    }
                }
            }
            group.addTask {
                do {
                    try await handler(model)
                } catch {
                    await MainActor.run {
                        self.error = error
                    }
                }
                await MainActor.run {
                    model.finish()
                }
            }
        }

        self.currentStepIdx += 1

        try Task.checkCancellation()
        if let error {
            throw error
        }
        try await runNext()
    }
}
