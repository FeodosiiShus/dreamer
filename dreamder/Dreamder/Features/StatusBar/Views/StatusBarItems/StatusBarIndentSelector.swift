//
//  StatusBarIndentSelector.swift
//  DreamderModules/StatusBar
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI

struct StatusBarIndentSelector: View {
    static let indentSizes = Array(1...8)
    static let tabWidths = Array(2...8)

    let document: CodeFileDocument?

    @State private var isHovering: Bool

    init(document: CodeFileDocument? = nil, isHovering: Bool = false) {
        self.document = document
        _isHovering = State(initialValue: isHovering)
    }

    var resolved: ResolvedIndent {
        document?.resolvedIndent ?? Self.globalResolved()
    }

    var label: String {
        Self.label(for: resolved)
    }

    static func label(for resolved: ResolvedIndent) -> String {
        switch resolved.style {
        case .tab:
            return "Tabs (\(resolved.tabWidth))"
        case .spaces:
            return "\(resolved.spaceCount) spaces"
        }
    }

    static func globalResolved() -> ResolvedIndent {
        let global = CodeFileDocument.currentGlobalIndent()
        return ResolvedIndent(
            style: global.style,
            spaceCount: global.spaceCount,
            tabWidth: global.tabWidth,
            styleSource: .global
        )
    }

    func useTabs() {
        setOverride(style: .tab)
    }

    func useSpaces() {
        setOverride(style: .spaces)
    }

    func setIndentSize(_ size: Int) {
        guard let document else { return }
        let current = resolved
        document.indentOption = SettingsData.TextEditingSettings.IndentOption(
            indentType: current.style == .tab ? .tab : .spaces,
            spaceCount: size
        )
    }

    func setTabWidth(_ width: Int) {
        document?.defaultTabWidth = width
    }

    private func setOverride(style: IndentStyle) {
        guard let document else { return }
        document.indentOption = SettingsData.TextEditingSettings.IndentOption(
            indentType: style == .tab ? .tab : .spaces,
            spaceCount: resolved.spaceCount
        )
    }

    var indentSizeBinding: Binding<Int> {
        Binding(get: { resolved.spaceCount }, set: { setIndentSize($0) })
    }

    var tabWidthBinding: Binding<Int> {
        Binding(get: { resolved.tabWidth }, set: { setTabWidth($0) })
    }

    func spacesOption(_ count: Int) -> some View {
        Text("\(count) Spaces")
            .tag(count)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering
    }

    var labelContent: some View {
        StatusBarWidgetText(text: label, isHovering: isHovering)
            .statusBarWidgetChrome(isHovering: isHovering)
    }

    var body: some View {
        Menu {
            Button("Use Tabs", action: useTabs)
            Button("Use Spaces", action: useSpaces)

            Divider()

            Picker("Indent Size", selection: indentSizeBinding) {
                ForEach(Self.indentSizes, id: \.self, content: spacesOption)
            }
            Picker("Tab Width", selection: tabWidthBinding) {
                ForEach(Self.tabWidths, id: \.self, content: spacesOption)
            }
        } label: {
            labelContent
        }
        .menuStyle(StatusBarMenuStyle())
        .disabled(document == nil)
        .fixedSize()
        .onHover(perform: setHovering)
        .help("Indentation")
    }
}
