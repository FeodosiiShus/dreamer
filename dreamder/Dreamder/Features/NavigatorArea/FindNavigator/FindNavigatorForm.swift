//
//  SearchModeSelector.swift
//  Dreamder
//
//  Created by Ziyuan Zhao on 2022/3/21.
//

import SwiftUI

struct FindNavigatorForm: View {
    @ObservedObject private var state: WorkspaceDocument.SearchState

    @State private var selectedMode: [SearchModeModel] {
        didSet {
            // sync the variables, as selectedMode is an array
            // and cannot be synced directly with @ObservedObject
            state.selectedMode = selectedMode
        }
    }

    @State private var includesText: String = ""
    @State private var excludesText: String = ""
    @State private var scoped: Bool = false
    @State private var caseSensitive: Bool = false
    @State private var preserveCase: Bool = false
    @State private var scopedToOpenEditors: Bool = false
    @State private var excludeSettings: Bool = true
    @FocusState private var isSearchFieldFocused: Bool

    init(state: WorkspaceDocument.SearchState) {
        self.state = state
        selectedMode = state.selectedMode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    scoped.toggle()
                } label: {
                    Text("Scoped")
                        .font(Islands.smallFont)
                        .foregroundStyle(scoped ? Islands.accent : Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
                .help("Search only in the given folders")
            }

            HStack(spacing: 4) {
                IslandSearchField(
                    state.selectedMode[1].title,
                    text: $state.searchQuery,
                    focus: $isSearchFieldFocused,
                    onClear: {
                        state.clearResults()
                    },
                    onSubmit: {
                        if !state.searchQuery.isEmpty {
                            Task {
                                await state.search(state.searchQuery)
                            }
                        } else {
                            state.clearResults()
                        }
                    }
                )

                FindOptionToggle(
                    systemImage: "textformat",
                    isOn: $caseSensitive,
                    help: "Match Case"
                )
                .onChange(of: caseSensitive) { _, newValue in
                    state.caseSensitive = newValue
                }
            }

            if selectedMode[0] == SearchModeModel.Replace {
                HStack(spacing: 4) {
                    IslandSearchField("With", text: $state.replaceText)
                    FindOptionToggle(
                        systemImage: "textformat.abc",
                        isOn: $preserveCase,
                        help: "Preserve Case"
                    )
                }
            }

            if scoped {
                HStack(spacing: 4) {
                    IslandSearchField("Only in folders", text: $includesText)
                    FindOptionToggle(
                        systemImage: "doc.plaintext",
                        isOn: $scopedToOpenEditors,
                        help: "Search only in Open Editors"
                    )
                }
                HStack(spacing: 4) {
                    IslandSearchField("Excluding folders", text: $excludesText)
                    FindOptionToggle(
                        systemImage: "gearshape",
                        isOn: $excludeSettings,
                        help: "Use Exclude Settings and Ignore Files"
                    )
                }
            }

            if selectedMode[0] == SearchModeModel.Replace {
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
        }
        .onReceive(state.$shouldFocusSearchField) { shouldFocus in
            if shouldFocus {
                isSearchFieldFocused = true
                state.shouldFocusSearchField = false
            }
        }
        .lineLimit(1...5)
    }
}

private struct FindOptionToggle: View {
    let systemImage: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Islands.accent : Islands.secondaryForeground)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Islands.controlRadius)
                        .fill(isOn ? Islands.actionHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
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
