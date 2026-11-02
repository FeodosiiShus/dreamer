import SwiftUI

struct GitLogFilterField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Islands.secondaryForeground)
            TextField(
                "",
                text: $text,
                prompt: Text("Text or hash").foregroundStyle(Islands.disabledForeground)
            )
            .textFieldStyle(.plain)
            .font(Islands.uiFont)
            .foregroundStyle(Islands.foreground)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(Islands.islandRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .strokeBorder(Islands.componentBorder, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
