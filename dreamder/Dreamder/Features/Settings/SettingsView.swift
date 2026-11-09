//
//  SettingsView.swift
//  Dreamder
//
//  Created by Raymond Vleeshouwer on 26/03/23.
//

import SwiftUI

/// A struct for settings
struct SettingsView: View {
    @State private var model: SettingsViewModel

    init(model: SettingsViewModel = SettingsViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                SettingsSidebarView(
                    searchText: $model.searchText,
                    selectedPage: $model.selectedPage,
                    showsDeveloperPage: model.showsDeveloperPage
                )
                .frame(width: sidebarWidth(for: geometry.size.width))
                Rectangle()
                    .fill(Islands.separator)
                    .frame(width: 1)
                VStack(spacing: 0) {
                    SettingsHeaderView(page: model.selectedPage, onSelectCategoryPage: model.select)
                    Rectangle()
                        .fill(Islands.separator)
                        .frame(height: 1)
                    pageContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Islands.island)
            }
        }
        .background(Islands.frame)
        .background(SettingsWindowReader(onChange: { model.window = $0 }))
        .environment(model)
        .onAppear(perform: model.installKeyDownMonitor)
        .onDisappear(perform: model.removeKeyDownMonitor)
    }

    private func sidebarWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.2, 200), 300)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch model.selectedPage {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .navigation:
            NavigationSettingsView()
        case .theme:
            ThemeSettingsView()
        case .textEditing:
            TextEditingSettingsView()
        case .terminal:
            TerminalSettingsView()
        case .search:
            SearchSettingsView()
        case .keybindings:
            KeymapSettingsView()
        case .sourceControl:
            SourceControlSettingsView()
        case .location:
            LocationsSettingsView()
        case .languageServers:
            LanguageServersView()
        case .developer:
            DeveloperSettingsView()
        default:
            Text("Implementation Needed").frame(alignment: .center)
        }
    }
}

@Observable
final class SettingsViewModel {
    var backButtonVisible: Bool = false
    var selectedPage: SettingsPage.Name = SettingsNavigation.defaultPage
    var searchText: String = ""
    var showsDeveloperPage: Bool = false

    @ObservationIgnored private var keyDownEventMonitor: Any?
    @ObservationIgnored private let keymap: Keymap
    @ObservationIgnored weak var window: NSWindow?

    init(keymap: Keymap = .shared) {
        self.keymap = keymap
    }

    func select(_ page: SettingsPage.Name) {
        selectedPage = page
    }

    func handleKeyDown(keyCode: UInt16) -> Bool {
        guard !keymap.isRecording, keyCode == Self.developerToggleKeyCode else { return false }
        showsDeveloperPage.toggle()
        selectedPage = SettingsNavigation.pageSelection(
            afterDeveloperPageVisibility: showsDeveloperPage,
            selected: selectedPage
        )
        return true
    }

    func handleKeyDown(keyCode: UInt16, windowNumber: Int) -> Bool {
        guard let window, window.windowNumber == windowNumber else { return false }
        return handleKeyDown(keyCode: keyCode)
    }

    func installKeyDownMonitor() {
        setKeyDownMonitor { [weak self] event in
            let keyCode = event.keyCode
            let windowNumber = event.windowNumber
            let consumed = MainActor.assumeIsolated {
                self?.handleKeyDown(keyCode: keyCode, windowNumber: windowNumber)
            } == true
            return consumed ? nil : event
        }
    }

    func setKeyDownMonitor(monitor: @escaping (NSEvent) -> NSEvent?) {
        removeKeyDownMonitor()
        keyDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: monitor)
    }

    func removeKeyDownMonitor() {
        if let keyDownEventMonitor {
            NSEvent.removeMonitor(keyDownEventMonitor)
        }
        keyDownEventMonitor = nil
    }

    isolated deinit {
        removeKeyDownMonitor()
    }

    private static let developerToggleKeyCode: UInt16 = 111
}

struct SettingsWindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> SettingsWindowReaderView {
        let view = SettingsWindowReaderView(frame: .zero)
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: SettingsWindowReaderView, context: Context) {
        nsView.onChange = onChange
    }
}

final class SettingsWindowReaderView: NSView {
    var onChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onChange?(window)
    }
}
