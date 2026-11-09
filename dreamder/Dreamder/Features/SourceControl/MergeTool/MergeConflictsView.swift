import AppKit
import SwiftUI

struct MergeConflictsView: View {
    let model: MergeConflictsViewModel

    private var sideColumnWidth: CGFloat { 190 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            divider
            if model.isEmpty {
                emptyState
            } else {
                table
            }
            divider
            footer
        }
        .background(Islands.frame)
        .frame(minWidth: 640, minHeight: 300)
    }

    private var divider: some View {
        Rectangle()
            .fill(Islands.separator)
            .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("vcs/merge")
                .resizable()
                .frame(width: 16, height: 16)
            Text(model.summary)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(2)
            Spacer(minLength: 8)
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(model.emptyStateIcon)
                .resizable()
                .frame(width: 24, height: 24)
            Text(model.emptyStateMessage)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Islands.island)
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.yoursHeader)
                    .frame(width: sideColumnWidth, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.theirsHeader)
                    .frame(width: sideColumnWidth, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(Islands.smallFont)
            .foregroundStyle(Islands.secondaryForeground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Islands.island)
            divider
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.entries) { entry in
                        row(entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Islands.island)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: MergeConflictEntry) -> some View {
        MergeConflictRowView(
            model: model,
            entry: entry,
            sideColumnWidth: sideColumnWidth
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.errorForeground)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button("Accept Yours", action: acceptYours)
                .disabled(!model.canAccept)
            Button("Accept Theirs", action: acceptTheirs)
                .disabled(!model.canAccept)
            Button("Merge…", action: model.openMergeWindow)
                .disabled(!model.canMerge)
                .keyboardShortcut(.defaultAction)
            Button("Close", action: closeWindow)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    func acceptYours() {
        Task { await model.accept(.yours) }
    }

    func acceptTheirs() {
        Task { await model.accept(.theirs) }
    }

    func closeWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}

struct MergeConflictRowView: View {
    let model: MergeConflictsViewModel
    let entry: MergeConflictEntry
    let sideColumnWidth: CGFloat

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(IntelliJIcon.fileIcon(for: entry.fileName))
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(entry.fileName)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                    .lineLimit(1)
                if !entry.directory.isEmpty {
                    Text(entry.directory)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.disabledForeground)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(model.detail(for: entry, choice: .yours))
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .frame(width: sideColumnWidth, alignment: .leading)

            Text(model.detail(for: entry, choice: .theirs))
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .frame(width: sideColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.listRowHeight)
        .background(background)
        .contentShape(Rectangle())
        .onHover(perform: setHovering)
        .help(entry.path)
        .onTapGesture(count: 2, perform: openMerge)
        .onTapGesture(perform: click)
    }

    var isSelected: Bool {
        model.isSelected(entry.path)
    }

    var background: Color {
        Self.background(isSelected: isSelected, isHovering: isHovering)
    }

    static func background(isSelected: Bool, isHovering: Bool) -> Color {
        if isSelected {
            return Islands.selection
        }
        return isHovering ? Islands.hover : Color.clear
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func openMerge() {
        model.select(entry.path)
        model.openMergeWindow()
    }

    func click() {
        select(modifiers: NSEvent.modifierFlags)
    }

    func select(modifiers: NSEvent.ModifierFlags) {
        model.select(
            entry.path,
            extending: modifiers.contains(.shift),
            toggling: modifiers.contains(.command)
        )
    }
}
