import AppKit
import SwiftUI

struct MergeConflictsView: View {
    @ObservedObject var model: MergeConflictsViewModel

    private let sideColumnWidth: CGFloat = 190

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
            Image("general/greenCheckmark")
                .resizable()
                .frame(width: 24, height: 24)
            Text("All conflicts have been resolved")
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
            entry: entry,
            yours: model.detail(for: entry, choice: .yours),
            theirs: model.detail(for: entry, choice: .theirs),
            isSelected: model.isSelected(entry.path),
            sideColumnWidth: sideColumnWidth
        )
        .onTapGesture(count: 2) {
            model.select(entry.path)
            model.openMergeWindow()
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            model.select(
                entry.path,
                extending: flags.contains(.shift),
                toggling: flags.contains(.command)
            )
        }
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
            Button("Accept Yours") {
                Task { await model.accept(.yours) }
            }
            .disabled(!model.canAccept)
            Button("Accept Theirs") {
                Task { await model.accept(.theirs) }
            }
            .disabled(!model.canAccept)
            Button("Merge…") {
                model.openMergeWindow()
            }
            .disabled(!model.canMerge)
            .keyboardShortcut(.defaultAction)
            Button("Close") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

private struct MergeConflictRowView: View {
    let entry: MergeConflictEntry
    let yours: String
    let theirs: String
    let isSelected: Bool
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

            Text(yours)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .frame(width: sideColumnWidth, alignment: .leading)

            Text(theirs)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .lineLimit(1)
                .frame(width: sideColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: Islands.listRowHeight)
        .background(background)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(entry.path)
    }

    private var background: Color {
        if isSelected {
            return Islands.selection
        }
        return isHovering ? Islands.hover : Color.clear
    }
}
