import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
private final class TaskFormsDismissCounter {
    var count = 0
}

@MainActor
@Observable
private final class TaskFormsRowBox {
    var variable: CETask.EnvironmentVariable
    var selectedID: UUID?
    var deleted: [UUID] = []

    init(key: String, value: String, selectedID: UUID? = nil) {
        self.variable = CETask.EnvironmentVariable(key: key, value: value)
        self.selectedID = selectedID
    }
}

private struct TaskFormsRowHarness: View {
    @Bindable var box: TaskFormsRowBox

    var body: some View {
        EnvironmentVariableListItem(
            environmentVariable: $box.variable,
            selectedEnvID: $box.selectedID,
            deleteHandler: { box.deleted.append($0) }
        )
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct CETaskFormsCoverageTests {
    private static let hostSize = NSSize(width: 640, height: 720)

    private func makeItem(
        _ box: TaskFormsRowBox,
        isAppActive: (@MainActor () -> Bool)? = nil
    ) -> EnvironmentVariableListItem {
        let binding = Binding(get: { box.variable }, set: { box.variable = $0 })
        let selection = Binding(get: { box.selectedID }, set: { box.selectedID = $0 })
        let deleteHandler: (UUID) -> Void = { box.deleted.append($0) }
        guard let isAppActive else {
            return EnvironmentVariableListItem(
                environmentVariable: binding,
                selectedEnvID: selection,
                deleteHandler: deleteHandler
            )
        }
        return EnvironmentVariableListItem(
            environmentVariable: binding,
            selectedEnvID: selection,
            deleteHandler: deleteHandler,
            isAppActive: isAppActive
        )
    }

    private func makeUnwritableSettings(in directory: URL) throws -> CEWorkspaceSettings {
        let blocker = directory.appending(path: "blocker")
        try Data().write(to: blocker)
        return CEWorkspaceSettings(workspaceURL: blocker)
    }

    private func makeTaskManager() -> TaskManager {
        TaskManager(workspaceSettings: CEWorkspaceSettingsData(), workspaceURL: nil)
    }

    private func editableFields(_ hosted: HostedView) -> [NSTextField] {
        hosted.views(of: NSTextField.self).filter { $0.isEditable }
    }

    private func field(withValue value: String, in hosted: HostedView) throws -> NSTextField {
        try #require(editableFields(hosted).first { $0.stringValue == value })
    }

    private func append(_ text: String, to field: NSTextField, in hosted: HostedView) throws {
        try #require(hosted.window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText(text, replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
    }

    private func filledTask() -> CETask {
        CETask(
            name: "Build",
            target: "My Mac",
            workingDirectory: "/tmp/work",
            command: "make all",
            environmentVariables: [
                CETask.EnvironmentVariable(key: "FOO", value: "bar"),
                CETask.EnvironmentVariable(key: "BAZ", value: "qux")
            ]
        )
    }

    @Test
    func addContentRendersEmptyAndFilledStates() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let emptyHost = HostedViewFixture.host(size: Self.hostSize) {
                AddCETaskContent(task: CETask(target: "My Mac"), settings: settings, dismiss: {})
                    .environment(settings)
            }
            defer { emptyHost.close() }
            try await emptyHost.settle(.milliseconds(150))
            #expect(emptyHost.renders())
            let emptySnapshot = emptyHost.snapshot()

            let filledHost = HostedViewFixture.host(size: Self.hostSize) {
                AddCETaskContent(task: filledTask(), settings: settings, dismiss: {})
                    .environment(settings)
            }
            defer { filledHost.close() }
            try await filledHost.settle(.milliseconds(150))
            #expect(filledHost.renders())
            #expect(HostedView.pixelsDiffer(emptySnapshot, filledHost.snapshot()))
            #expect(editableFields(filledHost).contains { $0.stringValue == "Build" })
            #expect(editableFields(filledHost).contains { $0.stringValue == "make all" })
            #expect(editableFields(filledHost).contains { $0.stringValue == "/tmp/work" })
            #expect(editableFields(filledHost).contains { $0.stringValue == "FOO" })
            #expect(editableFields(filledHost).contains { $0.stringValue == "bar" })
        }
    }

    @Test
    func addViewBuildsContentFromTheWorkspaceSettingsEnvironment() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                AddCETaskView().environment(settings)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))

            #expect(hosted.renders())
            #expect(editableFields(hosted).count >= 3)
            #expect(settings.settings.tasks.isEmpty)
        }
    }

    @Test
    func addContentSaveAppendsTheTaskPersistsAndDismisses() async throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let counter = TaskFormsDismissCounter()
            let task = filledTask()
            let content = AddCETaskContent(task: task, settings: settings, dismiss: { counter.count += 1 })

            content.save()

            #expect(settings.settings.tasks.map(\.id) == [task.id])
            #expect(counter.count == 1)
            let saved = try String(contentsOf: settings.settingsURL, encoding: .utf8)
            #expect(saved.contains("Build"))
            #expect(saved.contains("make all"))
        }
    }

    @Test
    func addContentSaveStillDismissesWhenPersistingFails() async throws {
        try withTempDir { directory in
            let settings = try makeUnwritableSettings(in: directory)
            defer { settings.cleanUp() }
            let counter = TaskFormsDismissCounter()
            let task = filledTask()
            let content = AddCETaskContent(task: task, settings: settings, dismiss: { counter.count += 1 })

            content.save()

            #expect(settings.settings.tasks.map(\.id) == [task.id])
            #expect(counter.count == 1)
            #expect(FileManager.default.fileExists(atPath: settings.settingsURL.path) == false)
        }
    }

    @Test
    func formRendersEveryTargetVariant() async throws {
        var snapshots: [NSBitmapImageRep?] = []
        for target in ["My Mac", "SSH", "Docker", "Docker Compose"] {
            let task = CETask(name: "Run", target: target, workingDirectory: "", command: "echo")
            try await withTempDir { directory in
                let settings = CEWorkspaceSettings(workspaceURL: directory)
                defer { settings.cleanUp() }
                let hosted = HostedViewFixture.host(size: Self.hostSize) {
                    CETaskFormView(task: task).environment(settings)
                }
                defer { hosted.close() }
                try await hosted.settle(.milliseconds(100))

                #expect(hosted.renders())
                #expect(task.target == target)
                snapshots.append(hosted.snapshot())
            }
        }
        #expect(snapshots.count == 4)
        for (previous, next) in zip(snapshots, snapshots.dropFirst()) {
            #expect(HostedView.pixelsDiffer(previous, next))
        }
    }

    @Test
    func formShowsEnvironmentVariableRowsAndTheEmptyPlaceholderVariant() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let task = CETask(name: "Run", target: "My Mac", command: "echo")
            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                CETaskFormView(task: task).environment(settings)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))
            let emptySnapshot = hosted.snapshot()
            let emptyFieldCount = editableFields(hosted).count

            task.environmentVariables = [
                CETask.EnvironmentVariable(key: "FOO", value: "bar"),
                CETask.EnvironmentVariable(key: "BAZ", value: "qux")
            ]
            try await hosted.settle(.milliseconds(150))

            #expect(editableFields(hosted).count >= emptyFieldCount + 2)
            #expect(editableFields(hosted).contains { $0.stringValue == "FOO" })
            #expect(editableFields(hosted).contains { $0.stringValue == "bar" })
            #expect(HostedView.pixelsDiffer(emptySnapshot, hosted.snapshot()))
        }
    }

    @Test
    func formShowsANewEmptyRowAfterAddingAnEnvironmentVariable() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let task = CETask(name: "Run", target: "My Mac", command: "echo")
            let form = CETaskFormView(task: task)
            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                form.environment(settings)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))
            let before = editableFields(hosted).count

            form.addEnvironmentVariable()
            let added = try #require(task.environmentVariables.first)
            #expect(task.environmentVariables.count == 1)
            #expect(added.key.isEmpty)
            #expect(added.value.isEmpty)
            try await eventually(timeout: .seconds(30)) {
                hosted.layout()
                return editableFields(hosted).count == before + 2
            }
        }
    }

    @Test
    func formRemovesTheSelectedEnvironmentVariableOnly() throws {
        let task = filledTask()
        let form = CETaskFormView(task: task)
        let first = try #require(task.environmentVariables.first).id
        let second = try #require(task.environmentVariables.dropFirst().first).id

        form.deleteSelected(nil)
        #expect(task.environmentVariables.map(\.id) == [first, second])

        form.removeSelectedEnv()
        #expect(task.environmentVariables.map(\.id) == [first, second])

        form.deleteSelected(first)
        #expect(task.environmentVariables.map(\.id) == [second])

        form.removeEnv(id: UUID())
        #expect(task.environmentVariables.map(\.id) == [second])

        form.removeEnv(id: second)
        #expect(task.environmentVariables.isEmpty)
    }

    @Test
    func typingIntoTheFormTextFieldsUpdatesTheTask() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let task = filledTask()
            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                CETaskFormView(task: task).environment(settings)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))

            try append("X", to: field(withValue: "Build", in: hosted), in: hosted)
            try await eventually(timeout: .seconds(1)) { task.name == "BuildX" }

            try append("Y", to: field(withValue: "make all", in: hosted), in: hosted)
            try await eventually(timeout: .seconds(1)) { task.command == "make allY" }

            try append("Z", to: field(withValue: "/tmp/work", in: hosted), in: hosted)
            try await eventually(timeout: .seconds(1)) { task.workingDirectory == "/tmp/workZ" }
        }
    }

    @Test
    func typingIntoAnEnvironmentVariableRowWritesBackToTheTask() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let task = filledTask()
            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                CETaskFormView(task: task).environment(settings)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))

            try append("1", to: field(withValue: "FOO", in: hosted), in: hosted)
            try await eventually(timeout: .seconds(1)) { task.environmentVariables.first?.key == "FOO1" }

            try append("2", to: field(withValue: "bar", in: hosted), in: hosted)
            try await eventually(timeout: .seconds(1)) { task.environmentVariables.first?.value == "bar2" }
        }
    }

    @Test
    func rowRendersWithAnEmptyAndAFilledKey() async throws {
        let emptyBox = TaskFormsRowBox(key: "", value: "")
        let emptyHost = HostedViewFixture.host(size: NSSize(width: 400, height: 80)) {
            TaskFormsRowHarness(box: emptyBox)
        }
        defer { emptyHost.close() }
        try await emptyHost.settle(.milliseconds(150))
        #expect(editableFields(emptyHost).count == 2)
        #expect(emptyHost.renders())

        let filledBox = TaskFormsRowBox(key: "FOO", value: "bar")
        let filledHost = HostedViewFixture.host(size: NSSize(width: 400, height: 80)) {
            TaskFormsRowHarness(box: filledBox)
        }
        defer { filledHost.close() }
        try await filledHost.settle(.milliseconds(150))
        #expect(editableFields(filledHost).map(\.stringValue).sorted() == ["FOO", "bar"])
        #expect(filledBox.deleted.isEmpty)
    }

    @Test
    func typingIntoARowUpdatesTheBoundEnvironmentVariable() async throws {
        let box = TaskFormsRowBox(key: "FOO", value: "bar")
        let hosted = HostedViewFixture.host(size: NSSize(width: 400, height: 80)) {
            TaskFormsRowHarness(box: box)
        }
        defer { hosted.close() }
        try await hosted.settle(.milliseconds(150))

        try append("X", to: field(withValue: "FOO", in: hosted), in: hosted)
        try await eventually(timeout: .seconds(1)) { box.variable.key == "FOOX" }

        try append("Y", to: field(withValue: "bar", in: hosted), in: hosted)
        try await eventually(timeout: .seconds(1)) { box.variable.value == "barY" }
    }

    @Test
    func rowKeyAndValueChangesWriteThroughTheBinding() {
        let box = TaskFormsRowBox(key: "FOO", value: "bar")
        let item = makeItem(box)

        item.keyChanged("FOO", "RENAMED")
        item.valueChanged("bar", "changed")

        #expect(box.variable.key == "RENAMED")
        #expect(box.variable.value == "changed")
    }

    @Test
    func gainingKeyFocusSelectsTheRow() {
        let box = TaskFormsRowBox(key: "FOO", value: "bar")
        let item = makeItem(box)

        item.keyFocusChanged(false, true)
        #expect(box.selectedID == box.variable.id)

        item.keyFocusChanged(false, true)
        #expect(box.selectedID == box.variable.id)
        #expect(box.deleted.isEmpty)
    }

    @Test
    func losingKeyFocusKeepsARowThatHasAKey() {
        let box = TaskFormsRowBox(key: "FOO", value: "bar")
        box.selectedID = box.variable.id
        let item = makeItem(box)

        item.keyFocusChanged(true, false)

        #expect(box.selectedID == box.variable.id)
        #expect(box.deleted.isEmpty)
    }

    @Test
    func losingKeyFocusDeletesARowWithAnEmptyKeyAndClearsTheSelection() {
        let box = TaskFormsRowBox(key: "", value: "orphan")
        box.selectedID = box.variable.id
        let item = makeItem(box, isAppActive: { true })

        item.keyFocusChanged(true, false)

        #expect(box.selectedID == nil)
        #expect(box.deleted == [box.variable.id])
    }

    @Test
    func losingKeyFocusKeepsAnEmptyRowWhileTheAppIsInactive() {
        let box = TaskFormsRowBox(key: "", value: "draft")
        box.selectedID = box.variable.id
        let item = makeItem(box, isAppActive: { false })

        item.keyFocusChanged(true, false)

        #expect(box.selectedID == box.variable.id)
        #expect(box.deleted.isEmpty)
    }

    @Test
    func losingKeyFocusFollowsTheApplicationActivationByDefault() {
        let box = TaskFormsRowBox(key: "", value: "draft")
        let item = makeItem(box)

        item.keyFocusChanged(true, false)

        #expect((box.deleted == [box.variable.id]) == NSApp.isActive)
    }

    @Test
    func editContentRendersValidAndInvalidTasks() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let taskManager = makeTaskManager()
            let validHost = HostedViewFixture.host(size: Self.hostSize) {
                EditCETaskContent(task: filledTask(), settings: settings, taskManager: taskManager, dismiss: {})
                    .environment(settings)
            }
            defer { validHost.close() }
            try await validHost.settle(.milliseconds(150))
            #expect(validHost.renders())

            let invalidHost = HostedViewFixture.host(size: Self.hostSize) {
                EditCETaskContent(
                    task: CETask(target: "My Mac"),
                    settings: settings,
                    taskManager: taskManager,
                    dismiss: {}
                )
                .environment(settings)
            }
            defer { invalidHost.close() }
            try await invalidHost.settle(.milliseconds(150))
            #expect(invalidHost.renders())
            #expect(HostedView.pixelsDiffer(validHost.snapshot(), invalidHost.snapshot()))
        }
    }

    @Test
    func editViewBuildsContentFromTheEnvironment() async throws {
        try await withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let taskManager = makeTaskManager()
            let task = filledTask()
            settings.settings.tasks = [task]
            let hosted = HostedViewFixture.host(size: Self.hostSize) {
                EditCETaskView(task: task, selectedTaskIndex: 0)
                    .environment(settings)
                    .environment(taskManager)
            }
            defer { hosted.close() }
            try await hosted.settle(.milliseconds(150))

            #expect(hosted.renders())
            #expect(editableFields(hosted).contains { $0.stringValue == "Build" })
        }
    }

    @Test
    func doneSavesThePreferencesAndDismisses() async throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let counter = TaskFormsDismissCounter()
            let task = filledTask()
            settings.settings.tasks = [task]
            task.name = "Renamed"
            let content = EditCETaskContent(
                task: task,
                settings: settings,
                taskManager: makeTaskManager(),
                dismiss: { counter.count += 1 }
            )

            content.done()

            #expect(counter.count == 1)
            let saved = try String(contentsOf: settings.settingsURL, encoding: .utf8)
            #expect(saved.contains("Renamed"))
        }
    }

    @Test
    func doneReportsASaveFailureAndKeepsTheSheetOpen() async throws {
        try withTempDir { directory in
            let settings = try makeUnwritableSettings(in: directory)
            defer { settings.cleanUp() }
            let counter = TaskFormsDismissCounter()
            let task = filledTask()
            settings.settings.tasks = [task]
            let content = EditCETaskContent(
                task: task,
                settings: settings,
                taskManager: makeTaskManager(),
                dismiss: { counter.count += 1 }
            )
            let modalsBefore = DreamderHeadless.suppressedModals.count

            content.done()

            #expect(counter.count == 0)
            #expect(DreamderHeadless.suppressedModals.count == modalsBefore + 1)
        }
    }

    @Test
    func deleteRemovesTheTaskPersistsStopsItsRunAndDismisses() async throws {
        try withTempDir { directory in
            let settings = CEWorkspaceSettings(workspaceURL: directory)
            defer { settings.cleanUp() }
            let taskManager = makeTaskManager()
            let counter = TaskFormsDismissCounter()
            let task = filledTask()
            let survivor = CETask(name: "Survivor", target: "My Mac", command: "ls")
            settings.settings.tasks = [task, survivor]
            taskManager.activeTasks[task.id] = CEActiveTask(task: task)
            let content = EditCETaskContent(
                task: task,
                settings: settings,
                taskManager: taskManager,
                dismiss: { counter.count += 1 }
            )

            content.delete()

            #expect(settings.settings.tasks.map(\.id) == [survivor.id])
            #expect(taskManager.activeTasks[task.id] == nil)
            #expect(counter.count == 1)
            let saved = try String(contentsOf: settings.settingsURL, encoding: .utf8)
            #expect(saved.contains("Survivor"))
            #expect(saved.contains("Build") == false)
        }
    }

    @Test
    func deleteReportsASaveFailureAndKeepsTheActiveTask() async throws {
        try withTempDir { directory in
            let settings = try makeUnwritableSettings(in: directory)
            defer { settings.cleanUp() }
            let taskManager = makeTaskManager()
            let counter = TaskFormsDismissCounter()
            let task = filledTask()
            let survivor = CETask(name: "Survivor", target: "My Mac", command: "ls")
            settings.settings.tasks = [task, survivor]
            taskManager.activeTasks[task.id] = CEActiveTask(task: task)
            let content = EditCETaskContent(
                task: task,
                settings: settings,
                taskManager: taskManager,
                dismiss: { counter.count += 1 }
            )
            let modalsBefore = DreamderHeadless.suppressedModals.count

            content.delete()

            #expect(counter.count == 0)
            #expect(taskManager.activeTasks[task.id] != nil)
            #expect(DreamderHeadless.suppressedModals.count == modalsBefore + 1)
        }
    }
}
