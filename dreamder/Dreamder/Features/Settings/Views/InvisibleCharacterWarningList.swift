//
//  InvisibleCharacterWarningList.swift
//  Dreamder
//
//  Created by Khan Winter on 6/13/25.
//

import SwiftUI

struct InvisibleCharacterWarningList: View {
    @Binding var items: [UInt16: String]

    @State private var selection: String?

    var body: some View {
        KeyValueTable(
            items: displayBinding,
            keyColumnName: "Unicode Character Code",
            valueColumnName: "Notes",
            newItemInstruction: "Add A Character As A Hexidecimal Unicode Value",
            actionBarTrailing: {
                Button(action: restoreDefaults) {
                    Text("Restore Defaults")
                }
                .buttonStyle(PlainButtonStyle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.trailing, 4)
            }
        )
        .frame(minHeight: 96, maxHeight: .infinity)
        .overlay {
            if items.isEmpty {
                Text("No warning characters")
                    .foregroundStyle(Color(.secondaryLabelColor))
            }
        }
    }

    var displayBinding: Binding<[String: String]> {
        Binding(get: { Self.displayItems(items) }, set: { items = Self.parseItems($0) })
    }

    static func displayItems(_ items: [UInt16: String]) -> [String: String] {
        items.reduce(into: [String: String]()) { dict, keyVal in
            let hex = String(keyVal.key, radix: 16).uppercased()
            let padding = String(repeating: "0", count: 4 - hex.count)
            dict["U+" + padding + hex] = keyVal.value
        }
    }

    static func parseItems(_ dict: [String: String]) -> [UInt16: String] {
        dict.reduce(into: [UInt16: String]()) { dict, keyVal in
            guard let intFromHex = UInt(hexString: String(keyVal.key.trimmingPrefix("U+"))),
                  intFromHex < UInt16.max else {
                return
            }
            let charCode = UInt16(intFromHex)
            dict[charCode] = keyVal.value
        }
    }

    func restoreDefaults() {
        items = items.merging(
            SettingsData.TextEditingSettings.WarningCharacters.default.characters,
            uniquingKeysWith: { _, defaults in
                defaults
            }
        )
    }
}
