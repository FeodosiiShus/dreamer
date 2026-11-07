import SwiftUI

struct GitHunkPopoverView: View {
    let title: String
    let previousText: String?
    let onRollback: () -> Void
    let onShowDiff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
            previousContent
            HStack(spacing: 6) {
                actionButton("Rollback", action: onRollback)
                actionButton("Show Diff", action: onShowDiff)
            }
        }
        .padding(10)
        .frame(width: 360, alignment: .leading)
        .glassPopup(radius: Islands.popupRadius)
    }

    @ViewBuilder
    private var previousContent: some View {
        if let previousText, !previousText.isEmpty {
            ScrollView(.vertical) {
                Text(verbatim: previousText)
                    .font(Islands.codeFont)
                    .foregroundStyle(Islands.secondaryForeground)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(maxHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: Islands.rowRadius)
                    .fill(Islands.islandRaised.opacity(0.6))
            )
        } else {
            Text("No previous content")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Islands.smallFont)
                .foregroundStyle(Islands.foreground)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Islands.islandRaised.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .strokeBorder(Islands.popupBorder, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Islands.controlRadius))
        }
        .buttonStyle(.plain)
    }
}
