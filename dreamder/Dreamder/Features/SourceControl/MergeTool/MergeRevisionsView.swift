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
                help: "Apply non-conflicting changes from the left"
            ) {
                model.applyNonConflicting(.left)
            }
            .disabled(!model.canApplyNonConflicting(.left))
            .opacity(model.canApplyNonConflicting(.left) ? enabledOpacity : disabledOpacity)
            ToolWindowActionButton(
                icon: "diff/applyNotConflicts",
                help: "Apply all non-conflicting changes"
            ) {
                model.applyNonConflicting(.all)
            }
            .disabled(!model.canApplyNonConflicting(.all))
            .opacity(model.canApplyNonConflicting(.all) ? enabledOpacity : disabledOpacity)
            ToolWindowActionButton(
                icon: "diff/applyNotConflictsRight",
                help: "Apply non-conflicting changes from the right"
            ) {
                model.applyNonConflicting(.right)
            }
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
                onTextChange: { text in
                    model.userEditedResult(text)
                }
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
            Button("Accept Left") {
                Task {
                    if await model.requestAcceptSide(.yours, window: NSApp.keyWindow) {
                        onClose()
                    }
                }
            }
            .disabled(!model.canAcceptSide)
            Button("Accept Right") {
                Task {
                    if await model.requestAcceptSide(.theirs, window: NSApp.keyWindow) {
                        onClose()
                    }
                }
            }
            .disabled(!model.canAcceptSide)
            Button("Cancel") {
                Task {
                    if await model.requestCancel(window: NSApp.keyWindow) {
                        onClose()
                    }
                }
            }
            .keyboardShortcut(.cancelAction)
            Button("Apply") {
                Task {
                    if await model.requestApply(window: NSApp.keyWindow) {
                        onClose()
                    }
                }
            }
            .disabled(!model.canApply)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private func handle(_ chip: MergePaneChip) {
        switch chip.kind {
        case .acceptLeft:
            model.resolve(chip.blockID, with: .left)
        case .acceptRight:
            model.resolve(chip.blockID, with: .right)
        case .ignore:
            model.resolve(chip.blockID, with: .ignored)
        }
    }
}
