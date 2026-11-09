//
//  MonospacedFontPicker.swift
//  Dreamder
//
//  Created by Austin Condiff on 4/22/23.
//

import SwiftUI

struct MonospacedFontPicker: View {
    var title: String
    @Binding var selectedFontName: String
    @State private var recentFonts: [String]
    @State private var monospacedFontFamilyNames: [String] = []
    @State private var otherFontFamilyNames: [String] = []

    private let defaults: UserDefaults

    init(title: String, selectedFontName: Binding<String>, defaults: UserDefaults = .standard) {
        self.title = title
        self._selectedFontName = selectedFontName
        self.defaults = defaults
        self.recentFonts = defaults.stringArray(forKey: "recentFonts") ?? []
    }

    var body: some View {
        Picker(selection: $selectedFontName, label: Text(title)) {
            Text("System Font")
                .font(Font(NSFont.monospacedSystemFont(ofSize: 13.5, weight: .medium)))
                .tag("SF Mono")

            if !recentFonts.isEmpty {
                Divider()
                ForEach(recentFonts, id: \.self, content: fontRow)
            }

            if !monospacedFontFamilyNames.isEmpty {
                Divider()
                ForEach(monospacedFontFamilyNames, id: \.self, content: fontRow)
            }

            if !otherFontFamilyNames.isEmpty {
                Divider()
                Menu {
                    ForEach(otherFontFamilyNames, id: \.self, content: otherFontButton)
                } label: {
                    Text("Other fonts...")
                }
            }
        }
        .onChange(of: selectedFontName) { _, _ in
            if selectedFontName != "SF Mono" {
                pushIntoRecentFonts(selectedFontName)

                // remove the font to prevent ForEach conflict
                monospacedFontFamilyNames.removeAll { $0 == selectedFontName }
                otherFontFamilyNames.removeAll { $0 == selectedFontName }
            }
        }
        .task {
            await getFonts()
        }
    }
}

extension MonospacedFontPicker {
    private func pushIntoRecentFonts(_ newItem: String) {
        recentFonts = Self.pushed(newItem, onto: recentFonts)
        defaults.set(recentFonts, forKey: "recentFonts")
    }

    func fontRow(_ fontFamilyName: String) -> some View {
        Text(fontFamilyName)
            .font(.custom(fontFamilyName, size: 13.5))
            .tag(fontFamilyName)
    }

    static func pushed(_ newItem: String, onto recentFonts: [String]) -> [String] {
        var result = recentFonts
        result.removeAll(where: { $0 == newItem })
        result.insert(newItem, at: 0)
        if result.count > 3 {
            result.removeLast()
        }
        return result
    }

    func selectOtherFont(_ fontFamilyName: String) {
        pushIntoRecentFonts(fontFamilyName)
        selectedFontName = fontFamilyName
    }

    func otherFontButton(_ fontFamilyName: String) -> some View {
        Button(action: { selectOtherFont(fontFamilyName) }) {
            Text(fontFamilyName)
                .font(.custom(fontFamilyName, size: 13.5))
        }
        .tag(fontFamilyName)
    }

    private func getFonts() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let monospacedFontFamilyNames = await getMonospacedFamilyNames()
                await MainActor.run {
                    self.monospacedFontFamilyNames = monospacedFontFamilyNames
                }
            }

            group.addTask {
                let otherFontFamilyNames = await getOtherFontFamilyNames()
                await MainActor.run {
                    self.otherFontFamilyNames = otherFontFamilyNames
                }
            }
        }
    }

    private func getMonospacedFamilyNames() -> [String] {
        Self.monospacedFamilyNames(
            among: NSFontManager.shared.availableFontFamilies,
            excluding: recentFonts,
            resolve: Self.resolveFont
        )
    }

    private func getOtherFontFamilyNames() -> [String] {
        Self.otherFamilyNames(
            among: NSFontManager.shared.availableFontFamilies,
            excluding: recentFonts,
            resolve: Self.resolveFont
        )
    }

    static func resolveFont(_ familyName: String) -> NSFont? {
        NSFont(name: familyName, size: 14)
    }

    static func monospacedFamilyNames(
        among families: [String],
        excluding recentFonts: [String],
        resolve: (String) -> NSFont?
    ) -> [String] {
        families.filter { fontFamilyName in
            if recentFonts.contains(fontFamilyName) {
                return false
            }
            if fontFamilyName == "SF Mono" {
                return false
            }
            if let font = resolve(fontFamilyName) {
                return font.isFixedPitch && font.numberOfGlyphs > 26
            } else {
                return false
            }
        }
    }

    static func otherFamilyNames(
        among families: [String],
        excluding recentFonts: [String],
        resolve: (String) -> NSFont?
    ) -> [String] {
        families.filter { fontFamilyName in
            if recentFonts.contains(fontFamilyName) {
                return false
            }
            if let font = resolve(fontFamilyName) {
                return !font.isFixedPitch && font.numberOfGlyphs > 26
            } else {
                return false
            }
        }
    }
}
