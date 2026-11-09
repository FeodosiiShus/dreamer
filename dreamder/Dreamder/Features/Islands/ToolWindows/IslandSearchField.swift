import SwiftUI

struct IslandSearchField: View {
    private let placeholder: String
    @Binding private var text: String
    private let focus: FocusState<Bool>.Binding?
    private let onClear: (() -> Void)?
    private let onSubmit: (() -> Void)?

    @FocusState private var internalFocus: Bool

    init(
        _ placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding? = nil,
        onClear: (() -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.focus = focus
        self.onClear = onClear
        self.onSubmit = onSubmit
    }

    private var isFocused: Bool {
        focus?.wrappedValue ?? internalFocus
    }

    private var baseField: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Islands.uiFont)
            .foregroundStyle(Islands.foreground)
            .lineLimit(1)
            .onSubmit(submit)
    }

    @ViewBuilder private var field: some View {
        if let focus {
            baseField.focused(focus)
        } else {
            baseField.focused($internalFocus)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image("general/search")
                .resizable()
                .frame(width: 12, height: 12)
                .opacity(0.7)
            field
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
        .frame(minHeight: 26)
        .background {
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(Islands.glassFieldFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .stroke(isFocused ? Islands.accent : Islands.popupBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: requestFocus)
    }

    func submit() {
        onSubmit?()
    }

    func clear() {
        text = ""
        onClear?()
    }

    func requestFocus() {
        if let focus {
            focus.wrappedValue = true
        } else {
            internalFocus = true
        }
    }
}
