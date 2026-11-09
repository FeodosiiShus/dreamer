import AppKit
import Testing
@testable import Dreamder

@MainActor
@Suite(.uiGate)
struct BranchesPopupPromptCoverageTests {
    private func accessoryField(of alert: NSAlert) -> NSTextField? {
        alert.accessoryView as? NSTextField
    }

    private func dialogParts(
        of alert: NSAlert
    ) -> (field: NSTextField?, checkout: NSButton?, overwrite: NSButton?, unset: NSButton?, error: NSTextField?) {
        guard let stack = alert.accessoryView as? NSStackView else { return (nil, nil, nil, nil, nil) }
        let textFields = stack.arrangedSubviews.compactMap { $0 as? NSTextField }
        let buttons = stack.arrangedSubviews.compactMap { $0 as? NSButton }
        return (
            textFields.first { $0.isEditable },
            buttons.first { $0.title == "Checkout branch" },
            buttons.first { $0.title == "Overwrite existing branch" },
            buttons.first { $0.title == "Unset upstream" },
            textFields.first { !$0.isEditable }
        )
    }

    private func click(_ button: NSButton) {
        button.state = button.state == .on ? .off : .on
        guard let action = button.action else { return }
        _ = button.sendAction(action, to: button.target)
    }

    private func notifyChange(_ field: NSTextField) {
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    private func request(
        initialName: String = "",
        existingNames: Set<String> = [],
        showsCheckout: Bool = true,
        showsUnsetUpstream: Bool = false
    ) -> BranchesPopupBranchDialogRequest {
        BranchesPopupBranchDialogRequest(
            title: "New Branch",
            message: "Create a branch",
            initialName: initialName,
            existingNames: existingNames,
            showsCheckout: showsCheckout,
            showsUnsetUpstream: showsUnsetUpstream,
            confirmTitle: "Create"
        )
    }

    @Test
    func defaultRunnerIsSuppressedByTheHeadlessHost() {
        let before = DreamderHeadless.suppressedModals.count

        let name = BranchesPopupPrompt.name(title: "Prompt Name", message: "m", placeholder: "p")
        let confirmed = BranchesPopupPrompt.confirm(title: "Prompt Confirm", message: "m", confirmTitle: "Go")
        BranchesPopupPrompt.error(title: "Prompt Error", message: "m")
        let dialog = BranchesPopupPrompt.branchDialog(request())
        let delete = BranchesPopupPrompt.unmergedDelete(name: "topic", commits: ["abc one"])
        let decision = BranchesPopupPrompt.localCommitsDecision(local: "topic", remote: "origin/topic", count: 2)

        #expect(name == nil)
        #expect(confirmed == false)
        #expect(dialog == nil)
        #expect(delete == .cancel)
        #expect(decision == .cancel)
        let added = DreamderHeadless.suppressedModals.dropFirst(before)
        #expect(added.contains("Prompt Name"))
        #expect(added.contains("Prompt Confirm"))
        #expect(added.contains("Prompt Error"))
        #expect(added.contains("New Branch"))
        #expect(added.contains("Branch 'topic' is not fully merged"))
        #expect(added.contains("Local branch 'topic' has commits that do not exist in 'origin/topic'"))
    }

    @Test
    func namePromptReturnsTheTrimmedValueOnOK() throws {
        var captured: NSAlert?

        let value = BranchesPopupPrompt.name(
            title: "Checkout origin/x",
            message: "Enter a name",
            placeholder: "Branch name",
            initialValue: "suggested"
        ) { alert in
            captured = alert
            let field = accessoryField(of: alert)
            #expect(field?.stringValue == "suggested")
            field?.stringValue = "  topic  "
            return .alertFirstButtonReturn
        }

        #expect(value == "topic")
        #expect(captured?.messageText == "Checkout origin/x")
        #expect(captured?.informativeText == "Enter a name")
        #expect(captured?.buttons.map(\.title) == ["OK", "Cancel"])
        let alert = try #require(captured)
        #expect(accessoryField(of: alert)?.placeholderString == "Branch name")
    }

    @Test
    func namePromptReturnsNilForBlankValueAndCancel() {
        let blank = BranchesPopupPrompt.name(title: "t", message: "m", placeholder: "p") { alert in
            accessoryField(of: alert)?.stringValue = "   "
            return .alertFirstButtonReturn
        }
        let cancelled = BranchesPopupPrompt.name(title: "t", message: "m", placeholder: "p", initialValue: "kept") { _ in
            .alertSecondButtonReturn
        }

        #expect(blank == nil)
        #expect(cancelled == nil)
    }

    @Test
    func confirmReflectsTheChosenButton() {
        var titles: [String] = []

        let accepted = BranchesPopupPrompt.confirm(title: "Delete?", message: "Sure?", confirmTitle: "Delete") { alert in
            titles = alert.buttons.map(\.title)
            return .alertFirstButtonReturn
        }
        let declined = BranchesPopupPrompt.confirm(title: "Delete?", message: "Sure?", confirmTitle: "Delete") { _ in
            .alertSecondButtonReturn
        }

        #expect(accepted)
        #expect(declined == false)
        #expect(titles == ["Delete", "Cancel"])
    }

    @Test
    func errorShowsAWarningWithOK() {
        var captured: NSAlert?

        BranchesPopupPrompt.error(title: "Failed", message: "Because") { alert in
            captured = alert
            return .alertFirstButtonReturn
        }

        #expect(captured?.messageText == "Failed")
        #expect(captured?.informativeText == "Because")
        #expect(captured?.alertStyle == .warning)
        #expect(captured?.buttons.map(\.title) == ["OK"])
    }

    @Test
    func unmergedDeleteListsAtMostFifteenCommits() {
        var shortMessage = ""
        var longMessage = ""
        let few = (1...3).map { "c\($0) subject" }
        let many = (1...20).map { "c\($0) subject" }

        let force = BranchesPopupPrompt.unmergedDelete(name: "topic", commits: few) { alert in
            shortMessage = alert.informativeText
            return .alertFirstButtonReturn
        }
        let cancel = BranchesPopupPrompt.unmergedDelete(name: "topic", commits: many) { alert in
            longMessage = alert.informativeText
            return .alertSecondButtonReturn
        }

        #expect(force == .force)
        #expect(cancel == .cancel)
        #expect(shortMessage.contains("c3 subject"))
        #expect(shortMessage.contains("…") == false)
        #expect(shortMessage.hasSuffix("Delete the branch anyway?"))
        #expect(longMessage.contains("c15 subject"))
        #expect(longMessage.contains("c16 subject") == false)
        #expect(longMessage.contains("…"))
    }

    @Test
    func localCommitsDecisionMapsEveryButton() {
        var captured: NSAlert?
        let rebase = BranchesPopupPrompt.localCommitsDecision(local: "topic", remote: "origin/topic", count: 3) { alert in
            captured = alert
            return .alertFirstButtonReturn
        }
        let drop = BranchesPopupPrompt.localCommitsDecision(local: "topic", remote: "origin/topic", count: 3) { _ in
            .alertSecondButtonReturn
        }
        let cancel = BranchesPopupPrompt.localCommitsDecision(local: "topic", remote: "origin/topic", count: 3) { _ in
            .alertThirdButtonReturn
        }
        let abort = BranchesPopupPrompt.localCommitsDecision(local: "topic", remote: "origin/topic", count: 3) { _ in
            .abort
        }

        #expect(rebase == .rebase)
        #expect(drop == .drop)
        #expect(cancel == .cancel)
        #expect(abort == .cancel)
        #expect(captured?.buttons.map(\.title) == ["Rebase", "Drop Local Commits", "Cancel"])
        #expect(captured?.informativeText.contains("topic has 3 commit(s) not present in origin/topic") == true)
    }

    @Test
    func branchDialogValidatesTheNameWhileTyping() {
        var snapshots: [String] = []
        var buttonStates: [Bool] = []
        var overwriteStates: [Bool] = []

        let result = BranchesPopupPrompt.branchDialog(
            request(initialName: "main", existingNames: ["main"], showsCheckout: true, showsUnsetUpstream: true)
        ) { alert in
            let parts = dialogParts(of: alert)
            guard let field = parts.field, let overwrite = parts.overwrite, let checkout = parts.checkout,
                  let unset = parts.unset, let errorLabel = parts.error else { return .abort }
            @MainActor func record() {
                snapshots.append(errorLabel.stringValue)
                buttonStates.append(alert.buttons.first?.isEnabled ?? false)
                overwriteStates.append(overwrite.isEnabled)
            }
            record()
            click(overwrite)
            record()
            field.stringValue = "bad name"
            notifyChange(field)
            record()
            field.stringValue = "   "
            notifyChange(field)
            record()
            field.stringValue = "  fresh-topic  "
            notifyChange(field)
            record()
            click(checkout)
            unset.state = .on
            return .alertFirstButtonReturn
        }

        #expect(snapshots == [
            "Branch 'main' already exists",
            "",
            "Branch name is not valid",
            "Branch name cannot be empty",
            ""
        ])
        #expect(buttonStates == [false, true, false, false, true])
        #expect(overwriteStates == [true, true, false, false, false])
        #expect(result?.name == "fresh-topic")
        #expect(result?.checkout == false)
        #expect(result?.overwrite == false)
        #expect(result?.unsetUpstream == true)
    }

    @Test
    func branchDialogReportsOverwriteOfAnExistingBranch() {
        let result = BranchesPopupPrompt.branchDialog(
            request(initialName: "main", existingNames: ["main"], showsCheckout: true, showsUnsetUpstream: false)
        ) { alert in
            let parts = dialogParts(of: alert)
            if let overwrite = parts.overwrite { click(overwrite) }
            return .alertFirstButtonReturn
        }

        #expect(result?.name == "main")
        #expect(result?.overwrite == true)
        #expect(result?.checkout == true)
        #expect(result?.unsetUpstream == false)
    }

    @Test
    func branchDialogWithoutOptionalControlsReportsFalseFlags() {
        var checkoutPresent = true
        var unsetPresent = true

        let result = BranchesPopupPrompt.branchDialog(
            request(initialName: "topic", showsCheckout: false, showsUnsetUpstream: false)
        ) { alert in
            let parts = dialogParts(of: alert)
            checkoutPresent = parts.checkout != nil
            unsetPresent = parts.unset != nil
            return .alertFirstButtonReturn
        }

        #expect(checkoutPresent == false)
        #expect(unsetPresent == false)
        #expect(result?.name == "topic")
        #expect(result?.checkout == false)
        #expect(result?.overwrite == false)
        #expect(result?.unsetUpstream == false)
    }

    @Test
    func branchDialogReturnsNilWhenCancelled() {
        let result = BranchesPopupPrompt.branchDialog(request(initialName: "topic")) { _ in
            .alertSecondButtonReturn
        }

        #expect(result == nil)
    }
}
