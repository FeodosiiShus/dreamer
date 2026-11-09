import AppKit
import Observation
import CodeEditSourceEditor
import Foundation

@Observable
@MainActor
final class SearchEverywhereViewModel {
    private(set) var tab: SearchEverywhereTab
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }
    var sections: [SearchEverywhereSection] = []
    var selection: Int = 0
    var preview: SearchEverywherePreview?
    var showsPreview: Bool {
        didSet {
            defaults.set(showsPreview, forKey: Self.previewDefaultsKey)
        }
    }

    var symbolIndex: SearchEverywhereSymbolIndex? { workspace?.symbolIndex }
    let mode: SearchEverywhereMode
    @ObservationIgnored weak var workspace: WorkspaceDocument?
    let defaults: UserDefaults
    let recentFiles: SearchEverywhereRecentFilesStore
    let actionsProvider: @MainActor () -> [SearchEverywhereAction]
    @ObservationIgnored var dismiss: (() -> Void)?

    private static let previewDefaultsKey = "dreamder.searchEverywhere.showPreview"

    @ObservationIgnored var pools: [SearchEverywhereSectionKind: [SearchEverywhereItem]] = [:]
    @ObservationIgnored var indexTask: Task<Void, Never>?
    @ObservationIgnored var changesObservation: Task<Void, Never>?
    @ObservationIgnored var debounceTask: Task<Void, Never>?
    @ObservationIgnored var textTask: Task<Void, Never>?
    @ObservationIgnored var previewTask: Task<Void, Never>?
    @ObservationIgnored var symbolsObservation: Task<Void, Never>?
    @ObservationIgnored var currentText = ""

    init(
        workspace: WorkspaceDocument?,
        mode: SearchEverywhereMode = .everywhere,
        defaults: UserDefaults = .standard,
        recentFiles: SearchEverywhereRecentFilesStore = .shared,
        actions: @escaping @MainActor () -> [SearchEverywhereAction] = SearchEverywhereActionProvider.actions
    ) {
        self.workspace = workspace
        self.mode = mode
        self.defaults = defaults
        self.recentFiles = recentFiles
        self.actionsProvider = actions
        self.tab = .all
        self.showsPreview = (defaults.object(forKey: Self.previewDefaultsKey) as? Bool ?? true)
            && mode == .everywhere

        let symbolIndex = workspace?.symbolIndex
        symbolsObservation = Task { [weak self] in
            var isInitialValue = true
            for await _ in Observations({ symbolIndex?.symbols }) {
                if isInitialValue {
                    isInitialValue = false
                    continue
                }
                self?.scheduleSearch()
            }
        }

        if let changes = workspace?.fileScope?.changes() {
            changesObservation = Task { [weak self] in
                for await _ in changes {
                    guard let self else { return }
                    if !self.query.isEmpty {
                        self.scheduleSearch()
                    }
                }
            }
        }
    }

    isolated deinit {
        symbolsObservation?.cancel()
        changesObservation?.cancel()
        indexTask?.cancel()
    }

    var flatItems: [SearchEverywhereItem] {
        sections.flatMap(\.items)
    }

    var selectedItem: SearchEverywhereItem? {
        let items = flatItems
        guard items.indices.contains(selection) else { return nil }
        return items[selection]
    }

    var isIndexing: Bool {
        symbolIndex?.isBuilding ?? false
    }

    var panelWidth: CGFloat {
        mode == .recentFiles ? 560 : 670
    }

    var panelHeight: CGFloat {
        mode == .recentFiles ? 400 : 520
    }

    func start(on tab: SearchEverywhereTab) {
        self.tab = mode == .recentFiles ? .files : tab
        query = ""
        pools = [:]
        selection = 0
        if let workspace {
            recentFiles.startTracking(for: workspace)
        }
        performSearch()
    }

    func selectTab(_ tab: SearchEverywhereTab) {
        guard mode == .everywhere else {
            performSearch()
            return
        }
        guard tab != self.tab else {
            performSearch()
            return
        }
        self.tab = tab
        selection = 0
        performSearch()
    }

    func select(_ item: SearchEverywhereItem) {
        guard let index = flatItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard index != selection else { return }
        selection = index
        updatePreview()
    }

    func moveSelection(by delta: Int) {
        let count = flatItems.count
        guard count > 0 else { return }
        let next = min(max(selection + delta, 0), count - 1)
        guard next != selection else { return }
        selection = next
        updatePreview()
    }

    func cycleTab(by delta: Int) {
        selectTab(tab.cycled(by: delta))
    }

    func togglePreview() {
        showsPreview.toggle()
        updatePreview()
    }

    func openSelected() {
        let items = flatItems
        guard items.indices.contains(selection) else { return }
        let item = items[selection]

        switch item.kind {
        case .action:
            item.action?.perform()
        default:
            if let url = item.url {
                openFile(url, line: item.line, column: item.column)
            }
        }

        dismiss?()
    }

    func handle(event: NSEvent) -> Bool {
        let flags = event.modifierFlags

        switch event.keyCode {
        case 53:
            dismiss?()
            return true
        case 36, 76:
            openSelected()
            return true
        case 48:
            cycleTab(by: flags.contains(.shift) ? -1 : 1)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        case 125:
            moveSelection(by: 1)
            return true
        case 116:
            moveSelection(by: -10)
            return true
        case 121:
            moveSelection(by: 10)
            return true
        case 115:
            moveSelection(by: -flatItems.count)
            return true
        case 119:
            moveSelection(by: flatItems.count)
            return true
        case 35 where flags.contains(.option):
            togglePreview()
            return true
        default:
            return false
        }
    }
}
