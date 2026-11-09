import SwiftUI

struct SettingsSearchField: View {
    private let placeholder: String
    @Binding private var text: String

    @FocusState private var isFocused: Bool

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        HStack(spacing: 6) {
            Image("general/search")
                .resizable()
                .frame(width: 12, height: 12)
                .opacity(0.7)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .focused($isFocused)
            if !text.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .fill(Islands.island)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Islands.rowRadius)
                .stroke(isFocused ? Islands.accent : Islands.popupBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
    }

    func clear() {
        text = ""
    }

    func focus() {
        isFocused = true
    }
}
