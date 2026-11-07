//
//  StatusBarIndentSelector.swift
//  DreamderModules/StatusBar
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI

struct StatusBarIndentSelector: View {
    @AppSettings(\.textEditing.defaultTabWidth)
    private var defaultTabWidth
    @AppSettings(\.textEditing.indentOption)
    private var indentOption

    @State private var isHovering = false

    private var label: String {
        indentOption.indentType == .tab ? "Tabs (\(defaultTabWidth))" : "\(defaultTabWidth) spaces"
    }

    var body: some View {
        Menu {
            Button("Use Tabs") {
                indentOption.indentType = .tab
            }
            Button("Use Spaces") {
                indentOption.indentType = .spaces
            }

            Divider()

            Picker("Tab Width", selection: $defaultTabWidth) {
                ForEach(2..<9) { width in
                    Text("\(width) Spaces")
                        .tag(width)
                }
            }
        } label: {
            Text(label)
                .font(Islands.smallFont)
                .foregroundColor(Islands.secondaryForeground)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background {
                    RoundedRectangle(cornerRadius: Islands.rowRadius)
                        .fill(isHovering ? Islands.islandRaised.opacity(0.8) : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .menuStyle(StatusBarMenuStyle())
        .fixedSize()
        .onHover { isHovering = $0 }
        .help("Indentation")
    }
}
