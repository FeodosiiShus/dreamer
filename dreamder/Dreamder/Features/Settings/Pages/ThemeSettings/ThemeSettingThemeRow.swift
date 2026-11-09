//
//  ThemeSettingThemeRow.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/3/23.
//

import SwiftUI

struct ThemeSettingsThemeRow: View {
    @Binding var theme: Theme
    var active: Bool

    private let themeModel: ThemeModel

    @State private var isHovering = false

    @State private var isConfirmingDelete: Bool

    init(
        theme: Binding<Theme>,
        active: Bool,
        themeModel: ThemeModel = .shared,
        isConfirmingDelete: Bool = false,
        isHovering: Bool = false
    ) {
        _theme = theme
        self.active = active
        self.themeModel = themeModel
        _isConfirmingDelete = State(initialValue: isConfirmingDelete)
        _isHovering = State(initialValue: isHovering)
    }

    var body: some View {
        HStack {
            Image(systemName: "checkmark")
                .opacity(active ? 1 : 0)
                .font(.system(size: 10.5, weight: .bold))
            VStack(alignment: .leading) {
                Text(theme.displayName)
                Text(theme.author)
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !active {
                Button(action: choose) {
                    Text("Choose")
                }
                .buttonStyle(.bordered)
                .opacity(isHovering ? 1 : 0)
            }
            ThemeSettingsColorPreview(theme)
            Menu(content: { menuItems }, label: { menuLabel })
                .buttonStyle(.icon)
        }
        .padding(10)
        .onHover(perform: setHovering)
        .alert(deleteTitle, isPresented: $isConfirmingDelete, actions: { deleteActions }, message: { deleteMessage })
    }

    var menuLabel: some View {
        Image(systemName: "ellipsis.circle")
            .font(.system(size: 16))
    }

    var menuItems: some View {
        Group {
            Button("Details...", action: showDetails)
            Button("Duplicate...", action: duplicate)
            Button("Export...", action: export)
                .disabled(theme.isBundled)
            Divider()
            Button("Delete...", action: requestDelete)
                .disabled(theme.isBundled)
        }
    }

    var deleteTitle: Text {
        Text("Are you sure you want to delete the theme “\(theme.displayName)”?")
    }

    var deleteActions: some View {
        Group {
            Button("Delete Theme", action: confirmDelete)
            Button("Cancel", action: cancelDelete)
        }
    }

    var deleteMessage: some View {
        Text("This action cannot be undone.")
    }

    func choose() {
        themeModel.activateTheme(theme)
    }

    func showDetails() {
        themeModel.showDetails(of: theme)
    }

    func duplicate() {
        if let fileURL = theme.fileURL {
            themeModel.duplicate(fileURL)
        }
    }

    func export() {
        themeModel.exportTheme(theme)
    }

    func confirmDelete() {
        themeModel.delete(theme)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    func requestDelete() {
        isConfirmingDelete = true
    }

    func cancelDelete() {
        isConfirmingDelete = false
    }
}
