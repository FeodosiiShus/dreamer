import SwiftUI

struct GoToLinePopupView: View {
    @Bindable var model: GoToLinePopupModel
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(Islands.headerTitleFont)
                .foregroundStyle(Islands.foreground)
            TextField(model.placeholder, text: $model.input)
                .textFieldStyle(.plain)
                .font(Islands.codeFont)
                .foregroundStyle(Islands.editorForeground)
                .focused($fieldFocused)
                .onSubmit(model.submit)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Islands.glassFieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .strokeBorder(model.isValid ? Islands.componentBorder : Islands.errorForeground, lineWidth: 1)
                )
            hint
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .glassPopup(radius: Islands.popupRadius)
        .onAppear { fieldFocused = true }
        .onExitCommand(perform: model.cancel)
    }

    @ViewBuilder
    private var hint: some View {
        if model.isValid {
            Text("Current line \(model.currentLine) of \(model.lineCount)")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
        } else {
            Text("Enter a line number between 1 and \(model.lineCount)")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.errorForeground)
        }
    }
}
