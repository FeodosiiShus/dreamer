import AppKit
import SwiftUI

struct MergeRevisionsView: View {
    let model: MergeRevisionsViewModel
    let onClose: () -> Void

    @State private var scrollSync = MergeScrollCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            separator
            if let errorMessage = model.errorMessage {
                errorBanner(errorMessage)
                separator
            }
            if model.isLoading && model.merge == nil {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Islands.island)
            } else {
                panes
            }
            separator
            bottomBar
        }
        .background(Islands.frame)
        .frame(minWidth: 720, minHeight: 460)
    }

    private var enabledOpacity: Double { 1 }

    private var disabledOpacity: Double { 0.4 }

    private var separator: some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(height: 1)
    }

    private var verticalSeparator: some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(width: 1)
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Text("Apply non-conflicting changes:")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.leading, 4)

            ToolWindowActionButton(
                icon: "diff/applyNotConflictsLeft",
                help: "Apply non-conflicting changes from the left",
                action: applyLeft
            )
            .disabled(!model.canApplyNonConflicting(.left))
            .opacity(model.canApplyNonConflicting(.left) ? enabledOpacity : disabledOpacity)
            ToolWindowActionButton(
                icon: "diff/applyNotConflicts",
                help: "Apply all non-conflicting changes",
                action: applyAll
            )
            .disabled(!model.canApplyNonConflicting(.all))
            .opacity(model.canApplyNonConflicting(.all) ? enabledOpacity : disabledOpacity)
            ToolWindowActionButton(
                icon: "diff/applyNotConflictsRight",
                help: "Apply non-conflicting changes from the right",
                action: applyRight
            )
            .disabled(!model.canApplyNonConflicting(.right))
            .opacity(model.canApplyNonConflicting(.right) ? enabledOpacity : disabledOpacity)

            Spacer(minLength: 8)

            Text(model.summary)
                .font(Islands.smallFont)
                .foregroundStyle(model.merge?.isFullyResolved == true
                                 ? Islands.successForeground
                                 : Islands.secondaryForeground)
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.toolWindowHeaderHeight)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image("general/warningDialog")
                .resizable()
                .frame(width: 16, height: 16)
            Text(message)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.errorForeground)
                .lineLimit(2)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 28)
        .background(Islands.islandRaised)
    }

    private var panes: some View {
        HStack(spacing: 0) {
            pane(
                title: model.leftTitle,
                content: model.leftPane,
                paneID: "left",
                isEditable: false
            )
            verticalSeparator
            pane(
                title: model.path,
                content: model.resultPane,
                paneID: "result",
                isEditable: true
            )
            verticalSeparator
            pane(
                title: model.rightTitle,
                content: model.rightPane,
                paneID: "right",
                isEditable: false
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pane(
        title: String,
        content: MergePaneContent,
        paneID: String,
        isEditable: Bool
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 24)
                .background(Islands.islandRaised)
            MergeTextPane(
                content: content,
                revision: model.contentRevision,
                isEditable: isEditable,
                scrollSync: scrollSync,
                paneID: paneID,
                onChip: handle,
                onTextChange: model.userEditedResult
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer(minLength: 8)
            Button("Accept Left", action: acceptLeft)
                .disabled(!model.canAcceptSide)
            Button("Accept Right", action: acceptRight)
                .disabled(!model.canAcceptSide)
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Apply", action: apply)
                .disabled(!model.canApply)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    func handle(_ chip: MergePaneChip) {
        let resolution: ThreeWayMerge.Resolution
        switch chip.kind {
        case .acceptLeft:
            resolution = .left
        case .acceptRight:
            resolution = .right
        case .ignore:
            resolution = .ignored
        }
        Task { await model.requestResolve(chip.blockID, with: resolution, window: NSApp.keyWindow) }
    }

    func applyLeft() {
        applyNonConflicting(.left)
    }

    func applyAll() {
        applyNonConflicting(.all)
    }

    func applyRight() {
        applyNonConflicting(.right)
    }

    private func applyNonConflicting(_ mode: ThreeWayMerge.NonConflictingMode) {
        Task { await model.requestApplyNonConflicting(mode, window: NSApp.keyWindow) }
    }

    func acceptLeft() {
        finish { await model.requestAcceptSide(.yours, window: NSApp.keyWindow) }
    }

    func acceptRight() {
        finish { await model.requestAcceptSide(.theirs, window: NSApp.keyWindow) }
    }

    func cancel() {
        finish { await model.requestCancel(window: NSApp.keyWindow) }
    }

    func apply() {
        finish { await model.requestApply(window: NSApp.keyWindow) }
    }

    private func finish(_ request: @escaping @MainActor () async -> Bool) {
        let onClose = onClose
        Task {
            if await request() {
                onClose()
            }
        }
    }
}
