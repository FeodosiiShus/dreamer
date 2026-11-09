//
//  GlobPatternList.swift
//  Dreamder
//
//  Created by Austin Condiff on 11/2/24.
//

import SwiftUI

struct GlobPatternList: View {
    @Binding var patterns: [GlobPattern]
    @Binding var selection: Set<UUID>
    let addPattern: () -> Void
    let removePatterns: (_ selection: Set<UUID>?) -> Void
    let emptyMessage: String

    @FocusState private var focusedField: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(patterns.enumerated()), id: \.element.id) { index, pattern in
                GlobPatternListItem(
                    pattern: $patterns[index],
                    selection: $selection,
                    addPattern: addPattern,
                    removePatterns: removePatterns,
                    focusedField: $focusedField,
                    isLast: patterns.count == index + 1
                )
                .onAppear { focusIfEmpty(pattern) }
            }
            .onMove(perform: movePatterns)
            .onDelete(perform: deletePatterns)
        }
        .frame(minHeight: 96)
        .contextMenu(forSelectionType: UUID.self, menu: menuContent(for:), primaryAction: focus)
        .overlay {
            if patterns.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(Color(.secondaryLabelColor))
            }
        }
        .actionBar {
            Button(action: addPattern) {
                Image(systemName: "plus")
            }
            Divider()
            Button(action: removeSelected) {
                Image(systemName: "minus")
                    .opacity(selection.isEmpty ? 0.5 : 1)
            }
            .disabled(selection.isEmpty)
        }
        .onDeleteCommand(perform: removeSelected)
    }

    func focusIfEmpty(_ pattern: GlobPattern) {
        if pattern.value.isEmpty {
            focusedField = pattern.id.uuidString
        }
    }

    func movePatterns(from offsets: IndexSet, to destination: Int) {
        patterns.move(fromOffsets: offsets, toOffset: destination)
    }

    func deletePatterns(at offsets: IndexSet) {
        removePatterns(Set(offsets.map { patterns[$0].id }))
    }

    func focus(_ selection: Set<UUID>) {
        if let patternID = selection.first, let pattern = patterns.first(where: { $0.id == patternID }) {
            focusedField = pattern.id.uuidString
        }
    }

    func removeSelected() {
        removePatterns(selection)
    }

    @ViewBuilder
    func menuContent(for selection: Set<UUID>) -> some View {
        if let patternID = selection.first, patterns.contains(where: { $0.id == patternID }) {
            Button("Edit") { focus(selection) }
            Button("Add", action: addPattern)
            Divider()
            Button("Remove") { removePatterns(selection) }
        }
    }
}
