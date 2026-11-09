//
//  TerminalEmulatorView.swift
//  DreamderModules/TerminalEmulator
//
//  Created by Lukas Pistrol on 22.03.22.
//

import SwiftUI
import SwiftTerm

/// # TerminalEmulatorView
///
/// A terminal emulator view.
///
/// Wraps a `LocalProcessTerminalView` from `SwiftTerm` inside a `NSViewRepresentable`
/// for use in SwiftUI.
///
/// Caches the view in the ``TerminalCache`` to keep terminal state when the view is removed from the hierarchy.
///
struct TerminalEmulatorView: NSViewRepresentable {
    enum TerminalMode {
        case shell(shellType: Shell?)
        case task(activeTask: CEActiveTask)
    }

    @AppSettings(\.terminal)
    var terminalSettings
    @AppSettings(\.textEditing.font)
    var fontSettings

    private let themeModel: ThemeModel

    private var store: Settings {
        _terminalSettings.store
    }

    private var font: NSFont {
        if terminalSettings.useTextEditorFont {
            return fontSettings.current
        } else {
            return terminalSettings.font.current
        }
    }

    private let terminalID: UUID
    private var url: URL

    public var mode: TerminalMode
    public var onTitleChange: ((_ title: String) -> Void)?

    /// Create an emulator view
    /// - Parameters:
    ///   - url: The URL the emulator should start at.
    ///   - terminalID: The ID of the terminal. Used to restore state when switching away from the view.
    ///   - shellType: The type of shell to use. Overrides any settings or auto-detection.
    ///   - onTitleChange: A callback used when the terminal updates it's title.
    init(
        url: URL,
        terminalID: UUID,
        shellType: Shell? = nil,
        themeModel: ThemeModel = .shared,
        onTitleChange: @escaping (_ title: String) -> Void
    ) {
        self.url = url
        self.terminalID = terminalID
        self.mode = .shell(shellType: shellType)
        self.themeModel = themeModel
        self.onTitleChange = onTitleChange
    }

    init(url: URL, task: CEActiveTask, themeModel: ThemeModel = .shared) {
        terminalID = task.task.id
        self.url = url
        self.mode = .task(activeTask: task)
        self.themeModel = themeModel
        self.onTitleChange = nil
    }

    // MARK: - Settings

    private func getTerminalCursor() -> CursorStyle {
        let blink = terminalSettings.cursorBlink
        switch terminalSettings.cursorStyle {
        case .block:
            return blink ? .blinkBlock : .steadyBlock
        case .underline:
            return blink ? .blinkUnderline : .steadyUnderline
        case .bar:
            return blink ? .blinkBar : .steadyBar
        }
    }

    /// Returns true if the `option` key should be treated as the `meta` key.
    private var optionAsMeta: Bool {
        terminalSettings.optionAsMeta
    }

    private var activeTheme: Theme? {
        store.preferences.theme.matchAppearance && store.preferences.terminal.darkAppearance
            ? themeModel.selectedDarkTheme
            : themeModel.selectedTheme
    }

    private var activeTerminalColors: Theme.TerminalColors? {
        guard let theme = activeTheme else { return nil }
        return themeModel.themes.first { $0.id == theme.id }?.terminal
    }

    private var appearance: TerminalAppearance {
        TerminalAppearance(
            colors: activeTerminalColors,
            cursorStyle: getTerminalCursor(),
            optionAsMeta: optionAsMeta,
            darkAppearance: terminalSettings.darkAppearance
        )
    }

    // MARK: - NSViewRepresentable

    /// Inherited from NSViewRepresentable.makeNSView(context:).
    func makeNSView(context: Context) -> TerminalContainerView {
        let view: CELocalShellTerminalView

        switch mode {
        case .shell(let shellType):
            let isCached = TerminalCache.shared.getTerminalView(terminalID) != nil
            view = TerminalCache.shared.getTerminalView(terminalID) ?? CELocalShellTerminalView(frame: .zero)
            if !isCached {
                view.settings = store
                view.startProcess(workspaceURL: url, shell: shellType)
                context.coordinator.appliedAppearance = configureView(view)
            }
        case .task(let activeTask):
            if let output = activeTask.output {
                view = output
            } else {
                let newView = CEActiveTaskTerminalView(activeTask: activeTask)
                activeTask.output = newView
                view = newView
            }
            if !activeTask.hasOutputBeenConfigured {
                context.coordinator.appliedAppearance = configureView(view)
                activeTask.hasOutputBeenConfigured = true
            }
        }

        view.processDelegate = context.coordinator

        TerminalCache.shared.cacheTerminalView(for: terminalID, view: view)
        return TerminalContainerView(terminal: view)
    }

    @discardableResult
    func configureView(_ terminal: CELocalShellTerminalView) -> TerminalAppearance {
        terminal.getTerminal().silentLog = true
        scroller(terminal)?.isHidden = true
        terminal.font = font
        let current = self.appearance
        current.apply(to: terminal)
        return current
    }

    private func scroller(_ terminal: CELocalShellTerminalView) -> NSScroller? {
        for subView in terminal.subviews {
            if let scroller = subView as? NSScroller {
                return scroller
            }
        }
        return nil
    }

    func updateNSView(_ view: TerminalContainerView, context: Context) {
        refreshAppearance(of: view.terminal, coordinator: context.coordinator)
    }

    func refreshAppearance(of terminal: CELocalShellTerminalView, coordinator: Coordinator) {
        let current = self.appearance
        guard coordinator.appliedAppearance != current else { return }
        current.apply(to: terminal)
        coordinator.appliedAppearance = current
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(terminalID: terminalID, mode: mode, onTitleChange: onTitleChange)
    }
}
