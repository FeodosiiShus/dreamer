import SwiftUI

struct WelcomeProjectsList: View {
    let model: WelcomeViewModel

    @FocusState private var listFocused: Bool

    var queryBinding: Binding<String> {
        Binding(get: { model.query }, set: { model.updateQuery($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                IslandSearchField("Search projects", text: queryBinding, onSubmit: model.submitSearchAction)
                    .onKeyPress(.upArrow, action: moveUp)
                    .onKeyPress(.downArrow, action: moveDown)
                WelcomeActionButton(
                    title: "New Project",
                    icon: "general/add",
                    style: .toolbar,
                    action: model.newProject
                )
                WelcomeActionButton(title: "Open", icon: "general/open", style: .toolbar, action: model.openFromDisk)
                WelcomeActionButton(
                    title: "Clone Repository",
                    icon: "general/download",
                    style: .toolbar,
                    action: model.showCloneSheet
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 13)
            .padding(.bottom, 12)
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
            list
        }
    }

    @ViewBuilder private var list: some View {
        if model.projects.isEmpty {
            Text("Nothing found")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.projects) { project in
                            WelcomeProjectRow(
                                project: project,
                                isSelected: model.selection == project.path,
                                model: model
                            )
                            .id(project.path)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: model.selection) { _, selection in
                    if let selection {
                        proxy.scrollTo(selection)
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(.upArrow, action: moveUp)
            .onKeyPress(.downArrow, action: moveDown)
            .onKeyPress(.return, action: openSelection)
            .onKeyPress(.delete, action: removeSelection)
            .onKeyPress(.deleteForward, action: removeSelection)
            .onAppear { listFocused = true }
        }
    }

    func moveUp() -> KeyPress.Result {
        perform(.moveUp)
    }

    func moveDown() -> KeyPress.Result {
        perform(.moveDown)
    }

    func openSelection() -> KeyPress.Result {
        perform(.open)
    }

    func removeSelection() -> KeyPress.Result {
        perform(.remove)
    }

    private func perform(_ command: WelcomeKeyCommand) -> KeyPress.Result {
        model.perform(command)
        return .handled
    }
}
