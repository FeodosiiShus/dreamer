//
//  SettingsView.swift
//  Dreamder
//
//  Created by Raymond Vleeshouwer on 26/03/23.
//

import SwiftUI

/// A struct for settings
struct SettingsView: View {
    @StateObject private var model = SettingsViewModel()

    @State private var selectedPage: SettingsPage.Name = SettingsNavigation.defaultPage
    @State private var searchText: String = ""
    @State private var showsDeveloperPage: Bool = false

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                SettingsSidebarView(
                    searchText: $searchText,
                    selectedPage: $selectedPage,
                    showsDeveloperPage: showsDeveloperPage
                )
                .frame(width: sidebarWidth(for: geometry.size.width))
                Rectangle()
                    .fill(Islands.separator)
                    .frame(width: 1)
                VStack(spacing: 0) {
                    SettingsHeaderView(page: selectedPage) { page in
                        selectedPage = page
                    }
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
        .environmentObject(model)
        .onAppear {
            model.setKeyDownMonitor { event in
                if event.keyCode == 111 {
                    showsDeveloperPage.toggle()

                    if !showsDeveloperPage && selectedPage == .developer {
                        selectedPage = SettingsNavigation.defaultPage
                    }
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            model.removeKeyDownMonitor()
        }
    }

    private func sidebarWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.2, 200), 300)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .general:
            GeneralSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .accounts:
            AccountsSettingsView()
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

class SettingsViewModel: ObservableObject {
    @Published var backButtonVisible: Bool = false

    /// Holds a monitor closure for the `keyDown` event
    private var keyDownEventMonitor: Any?

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
}
