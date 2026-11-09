//
//  SearchModeSelector.swift
//  Dreamder
//
//  Created by Ziyuan Zhao on 2022/3/21.
//

import SwiftUI

struct FindNavigatorForm: View {
    @Bindable private var state: WorkspaceDocument.SearchState

    @State private var showsScopeOptions: Bool
    @FocusState private var isSearchFieldFocused: Bool

    init(state: WorkspaceDocument.SearchState, showsScopeOptions: Bool = false) {
        self.state = state
        self._showsScopeOptions = State(initialValue: showsScopeOptions)
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
        .onKeyPress(.downArrow, action: focusResults)
        .lineLimit(1...5)
    }

    private var modeRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<selectedMode.count, id: \.self) { index in
                FindModePicker(
                    modes: getMenuList(index),
                    selection: modeSelectionBinding(index),
                    onSelect: { searchMode in
                        onSelectMenuItem(index, searchMode: searchMode)
                    },
                    isLastItem: index == selectedMode.count-1
                )
            }
            Spacer(minLength: 4)
            Button(action: toggleScopeOptions) {
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
                onClear: clearSearch,
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                IslandSearchField("With", text: $state.replaceText)
                FindOptionToggle(
                    glyph: .symbol("textformat.abc"),
                    isOn: $state.findModel.isPreserveCase,
                    help: "Preserve Case"
                )
            }
            if let error = state.replacementError {
                Text(error)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.errorForeground)
            }
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
        Button(action: replaceAll) {
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

    func submitSearch() {
        if state.searchQuery.isEmpty {
            state.clearResults()
        } else {
            Task {
                await state.search(state.searchQuery)
            }
        }
    }

    func clearSearch() {
        state.clearResults()
    }

    func toggleScopeOptions() {
        showsScopeOptions.toggle()
    }

    func replaceAll() {
        Task { await state.replaceAll() }
    }

    func focusResults() -> KeyPress.Result {
        guard !state.searchResult.isEmpty else { return .ignored }
        state.shouldFocusResults = true
        return .handled
    }

    func modeSelectionBinding(_ index: Int) -> Binding<SearchModeModel> {
        Binding(
            get: {
                selectedMode.indices.contains(index) ? selectedMode[index] : .Find
            },
            set: { searchMode in
                onSelectMenuItem(index, searchMode: searchMode)
            }
        )
    }
}

struct FindOptionToggle: View {
    enum Glyph {
        case symbol(String)
        case text(String)
    }

    let glyph: Glyph
    @Binding var isOn: Bool
    let help: String

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: toggle) {
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

    func toggle() {
        isOn.toggle()
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

struct FindMultilineField: View {
    let placeholder: String
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let currentModifiers: @MainActor () -> NSEvent.ModifierFlags

    init(
        placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void,
        currentModifiers: @escaping @MainActor () -> NSEvent.ModifierFlags = { FindMultilineField.activeModifiers() }
    ) {
        self.placeholder = placeholder
        self._text = text
        self.focus = focus
        self.onSubmit = onSubmit
        self.currentModifiers = currentModifiers
    }

    static func activeModifiers() -> NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? []
    }

    func submitOnReturn() -> KeyPress.Result {
        guard !currentModifiers().contains(.shift) else { return .ignored }
        onSubmit()
        return .handled
    }

    func clear() {
        text = ""
    }

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
                .onKeyPress(.return, action: submitOnReturn)
            if !text.isEmpty {
                Button(action: clear) {
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
    func getMenuList(_ index: Int) -> [SearchModeModel] {
        guard index > 0 else { return SearchModeModel.SearchModes }
        return selectedMode.indices.contains(index - 1) ? selectedMode[index - 1].children : []
    }

    func onSelectMenuItem(_ index: Int, searchMode: SearchModeModel) {
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
