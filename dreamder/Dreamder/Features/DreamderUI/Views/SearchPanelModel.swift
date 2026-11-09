import AppKit
import SwiftUI

@Observable
@MainActor
final class SearchPanelModel<Option: Identifiable & Hashable> {
    var selection: Option?
    var previewVisible = true

    @ObservationIgnored private(set) var options: [Option] = []
    @ObservationIgnored private let onRowClick: (Option) -> Void
    @ObservationIgnored private let beep: () -> Void

    init(onRowClick: @escaping (Option) -> Void, beep: @escaping () -> Void = { NSSound.beep() }) {
        self.onRowClick = onRowClick
        self.beep = beep
    }

    func update(options: [Option]) {
        self.options = options
        selection = options.first
    }

    func submit() {
        if let selection {
            onRowClick(selection)
        } else {
            beep()
        }
    }

    func togglePreview() {
        withAnimation {
            previewVisible.toggle()
        }
    }

    func moveUp() {
        guard selection != options.first else { return }
        if let selection, let index = options.firstIndex(of: selection) {
            self.selection = options[index - 1]
        } else {
            selection = options.first
        }
    }

    func moveDown() {
        guard selection != options.last else { return }
        if let selection, let index = options.firstIndex(of: selection) {
            self.selection = options[index + 1]
        } else {
            selection = options.first
        }
    }
}
