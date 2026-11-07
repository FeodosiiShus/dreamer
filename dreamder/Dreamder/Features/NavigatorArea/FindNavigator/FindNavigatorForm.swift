//
//  SearchModeSelector.swift
//  Dreamder
//
//  Created by Ziyuan Zhao on 2022/3/21.
//

import SwiftUI

struct FindNavigatorForm: View {
    @Bindable private var state: WorkspaceDocument.SearchState

    @State private var showsScopeOptions: Bool = false
    @FocusState private var isSearchFieldFocused: Bool

    init(state: WorkspaceDocument.SearchState) {
        self.state = state
    }

    private var selectedMode: [SearchModeModel] {
        get { state.selectedMode }
        nonmutating set { state.selectedMode = newValue }
    }

    private var hasScopeSettings: Bool {
        showsScopeOptions || !state.findModel.isProjectScope || !state.fileMask.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            modeRow
            queryRow
            optionRow

            if selectedMode.isReplaceMode {
                replaceRow
            }

            if showsScopeOptions {
                scopeSection
            }

            if selectedMode.isReplaceMode {
                replaceAllButton
            }
        }
        .onChange(of: state.shouldFocusSearchField, initial: true) { _, shouldFocus in
            if shouldFocus {
                isSearchFieldFocused = true
                state.shouldFocusSearchField = false
            }
        }
        .onChange(of: state.searchQuery) { _, query in
            if query.contains(where: \.isNewline) {
                state.findModel.isMultiline = true
            }
        }
        .lineLimit(1...5)
    }

    private var modeRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<selectedMode.count, id: \.self) { index in
                FindModePicker(
                    modes: getMenuList(index),
                    selection: Binding(
                        get: {
                            selectedMode[index]
                        },
                        set: { searchMode in
                            onSelectMenuItem(index, searchMode: searchMode)
                        }
                    ),
                    onSelect: { searchMode in
                        onSelectMenuItem(index, searchMode: searchMode)
                    },
                    isLastItem: index == selectedMode.count-1
                )
            }
            Spacer(minLength: 4)
            Button {
                showsScopeOptions.toggle()
            } label: {
                Text("Scoped")
                    .font(Islands.smallFont)
                    .foregroundStyle(hasScopeSettings ? Islands.accent : Islands.secondaryForeground)
            }
            .buttonStyle(.plain)
            .help("Limit the search to a directory or to file names matching a mask")
        }
    }

    @ViewBuilder private var queryRow: some View {
        let placeholder = selectedMode.second?.title ?? "Find"
        if state.findModel.isMultiline {
            FindMultilineField(
                placeholder: placeholder,
                text: $state.searchQuery,
                focus: $isSearchFieldFocused,
                onSubmit: submitSearch
            )
        } else {
            IslandSearchField(
                placeholder,
                text: $state.searchQuery,
                focus: $isSearchFieldFocused,
                onClear: {
                    state.clearResults()
                },
                onSubmit: submitSearch
            )
        }
    }

    private var optionRow: some View {
        HStack(spacing: 2) {
            FindOptionToggle(glyph: .text("Cc"), isOn: $state.caseSensitive, help: "Match Case")
            FindOptionToggle(glyph: .text("W"), isOn: $state.wholeWordsOnly, help: "Words")
                .disabled(state.isRegularExpression)
            FindOptionToggle(glyph: .text(".*"), isOn: $state.isRegularExpression, help: "Regular Expression")
            FindOptionToggle(
                glyph: .symbol("arrow.turn.down.left"),
                isOn: $state.findModel.isMultiline,
                help: "Multiline"
            )
            Spacer(minLength: 0)
        }
    }

    private var replaceRow: some View {
        HStack(spacing: 4) {
            IslandSearchField("With", text: $state.replaceText)
            FindOptionToggle(
                glyph: .symbol("textformat.abc"),
                isOn: $state.findModel.isPreserveCase,
                help: "Preserve Case"
            )
        }
    }

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Scope", selection: $state.findModel.isProjectScope) {
                Text("Project").tag(true)
                Text("Directory").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if !state.findModel.isProjectScope {
                HStack(spacing: 4) {
                    IslandSearchField("Directory", text: $state.directoryScopePath)
                    FindOptionToggle(
                        glyph: .symbol("folder"),
                        isOn: $state.findModel.isWithSubdirectories,
                        help: "Include Subdirectories"
                    )
                }
            }

            IslandSearchField("File mask: *.swift, !*Tests.swift", text: $state.fileMask)
        }
    }

    private var replaceAllButton: some View {
        Button {
            Task {
                try? await state.findAndReplace(
                    query: state.searchQuery,
                    replacingTerm: state.replaceText
                )
            }
        } label: {
            Text("Replace All")
                .font(Islands.uiFont)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(Islands.accent)
                )
        }
        .buttonStyle(.plain)
    }

    private func submitSearch() {
        if state.searchQuery.isEmpty {
            state.clearResults()
        } else {
            Task {
                await state.search(state.searchQuery)
            }
        }
    }
}

private struct FindOptionToggle: View {
    enum Glyph {
        case symbol(String)
        case text(String)
    }

    let glyph: Glyph
    @Binding var isOn: Bool
    let help: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            glyphView
                .foregroundStyle(isOn ? Islands.accent : Islands.secondaryForeground)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(isOn ? Islands.actionHover : Color.clear)
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var glyphView: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
        case .text(let label):
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }
}

private struct FindMultilineField: View {
    let placeholder: String
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image("general/search")
                .resizable()
                .frame(width: 12, height: 12)
                .opacity(0.7)
                .padding(.top, 7)
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .lineLimit(2...6)
                .focused(focus)
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    onSubmit()
                    return .handled
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                .help("Clear")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(minHeight: 26)
        .background {
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(Islands.islandRaised)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .stroke(focus.wrappedValue ? Islands.accent : Islands.popupBorder, lineWidth: 1)
        }
    }
}

extension FindNavigatorForm {
    private func getMenuList(_ index: Int) -> [SearchModeModel] {
        index == 0 ? SearchModeModel.SearchModes : selectedMode[index - 1].children
    }

    private func onSelectMenuItem(_ index: Int, searchMode: SearchModeModel) {
        var newSelectedMode: [SearchModeModel] = []

        switch index {
        case 0:
                newSelectedMode.append(searchMode)
                self.updateSelectedMode(searchMode, searchModel: &newSelectedMode)
                self.selectedMode = newSelectedMode
        case 1:
            if let firstMode = selectedMode.first {
                newSelectedMode.append(contentsOf: [firstMode, searchMode])
                if let thirdMode = searchMode.children.first {
                    if let selectedThirdMode = selectedMode.third, searchMode.children.contains(selectedThirdMode) {
                        newSelectedMode.append(selectedThirdMode)
                    } else {
                        newSelectedMode.append(thirdMode)
                    }
                }
            }
            self.selectedMode = newSelectedMode
        case 2:
            if let firstMode = selectedMode.first, let secondMode = selectedMode.second {
                newSelectedMode.append(contentsOf: [firstMode, secondMode, searchMode])
            }
            self.selectedMode = newSelectedMode
        default:
            return
        }
    }

    private func updateSelectedMode(_ searchMode: SearchModeModel, searchModel: inout [SearchModeModel]) {
        if let secondMode = searchMode.children.first {
            if let selectedSecondMode = selectedMode.second, searchMode.children.contains(selectedSecondMode) {
                searchModel.append(contentsOf: selectedMode.dropFirst())
            } else {
                searchModel.append(secondMode)
                if let thirdMode = secondMode.children.first, let selectedThirdMode = selectedMode.third {
                    if secondMode.children.contains(selectedThirdMode) {
                        searchModel.append(selectedThirdMode)
                    } else {
                        searchModel.append(thirdMode)
                    }
                }
            }
        }
    }
}
