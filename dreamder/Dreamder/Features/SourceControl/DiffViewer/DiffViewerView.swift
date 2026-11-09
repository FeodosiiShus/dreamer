import AppKit
import SwiftUI

struct DiffViewerView: View {
    let model: DiffViewerViewModel

    private var enabledOpacity: Double { 1 }
    private var disabledOpacity: Double { 0.4 }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
            HStack(spacing: 0) {
                if model.showsFileList {
                    DiffFileListView(model: model)
                    Rectangle()
                        .fill(Islands.separator)
                        .frame(width: 1)
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Islands.frame)
        .frame(minWidth: 640, minHeight: 360)
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ToolWindowActionButton(icon: "general/up", help: "Previous Difference", action: model.previousDifference)
                .disabled(!model.canNavigatePrevious)
                .opacity(model.canNavigatePrevious ? enabledOpacity : disabledOpacity)

            ToolWindowActionButton(icon: "general/down", help: "Next Difference", action: model.nextDifference)
                .disabled(!model.canNavigateNext)
                .opacity(model.canNavigateNext ? enabledOpacity : disabledOpacity)

            Text(model.differenceSummary)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.leading, 4)

            Spacer(minLength: 8)

            if let file = model.selectedFile {
                Text(file.path)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.disabledForeground)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.toolWindowHeaderHeight)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.diff == nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Islands.island)
        } else if let message = model.message {
            placeholder(message, color: Islands.secondaryForeground)
        } else if let diff = model.diff {
            DiffCodeView(model: model, diff: diff)
        } else {
            placeholder("Nothing to compare", color: Islands.secondaryForeground)
        }
    }

    private func placeholder(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Islands.uiFont)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Islands.island)
    }
}

private struct DiffCodeView: View {
    let model: DiffViewerViewModel
    let diff: TextDiff

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.rows.indices, id: \.self) { index in
                        row(at: index)
                    }
                }
            }
            .background(Islands.island)
            .onChange(of: model.scrollRequest) { _, request in
                if let request {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        proxy.scrollTo(request.row, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(at index: Int) -> some View {
        let row = diff.rows[index]
        let metrics = model.metrics
        return HStack(spacing: 0) {
            lineNumber(row.leftLine, width: metrics.leftLineNumberWidth, background: lineBackground(row, side: .left))
            codeCell(
                lines: diff.leftLines,
                line: row.leftLine,
                width: metrics.leftCodeWidth,
                background: lineBackground(row, side: .left)
            )
            Rectangle()
                .fill(Islands.separator)
                .frame(width: 1, height: metrics.rowHeight)
            lineNumber(row.rightLine, width: metrics.rightLineNumberWidth, background: lineBackground(row, side: .right))
            codeCell(
                lines: diff.rightLines,
                line: row.rightLine,
                width: metrics.rightCodeWidth,
                background: lineBackground(row, side: .right)
            )
        }
        .frame(height: metrics.rowHeight)
    }

    private func lineNumber(_ line: Int?, width: CGFloat, background: Color) -> some View {
        Text(line.map { String($0 + 1) } ?? "")
            .font(Islands.codeFont)
            .foregroundStyle(Islands.lineNumber)
            .lineLimit(1)
            .frame(width: max(width - 12, 8), alignment: .trailing)
            .padding(.horizontal, 6)
            .frame(height: model.metrics.rowHeight)
            .background(background)
    }

    private func codeCell(lines: [String], line: Int?, width: CGFloat, background: Color) -> some View {
        let text: String
        if let line, lines.indices.contains(line) {
            text = DiffCodeStyle.display(lines[line])
        } else {
            text = ""
        }
        return Text(text)
            .font(Islands.codeFont)
            .foregroundStyle(Islands.editorForeground)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: max(width - 16, 8), alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: model.metrics.rowHeight)
            .background(background)
    }

    private func lineBackground(_ row: DiffRow, side: DiffSide) -> Color {
        switch row.kind {
        case .context:
            return Islands.island
        case .modified:
            return DiffColors.modified
        case .deleted:
            return side == .left ? DiffColors.deleted : Islands.island
        case .inserted:
            return side == .right ? DiffColors.inserted : Islands.island
        }
    }

    private enum DiffSide {
        case left
        case right
    }
}

struct DiffFileListView: View {
    let model: DiffViewerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.files) { file in
                    DiffFileListRow(file: file, isSelected: file.id == model.selectedID, onSelect: select)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 240)
        .background(Islands.island)
    }

    func select(_ file: DiffFileRequest) {
        Task {
            await model.select(file.id)
        }
    }
}

struct DiffFileListRow: View {
    let file: DiffFileRequest
    let isSelected: Bool
    let onSelect: (DiffFileRequest) -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(IntelliJIcon.fileIcon(for: file.fileName))
                .resizable()
                .frame(width: 16, height: 16)

            Text(file.fileName)
                .font(Islands.uiFont)
                .foregroundStyle(file.status.fileStatusColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Text(file.directory)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.disabledForeground)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Islands.listRowHeight)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover(perform: hoverChanged)
        .onTapGesture(perform: tapped)
        .help(file.path)
    }

    func tapped() {
        onSelect(file)
    }

    func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
    }

    private var rowBackground: Color {
        Self.background(isSelected: isSelected, isHovering: isHovering)
    }

    static func background(isSelected: Bool, isHovering: Bool) -> Color {
        isSelected ? Islands.selection : (isHovering ? Islands.hover : Color.clear)
    }
}
