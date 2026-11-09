import CodeEditSourceEditor
import Foundation
import Observation

@MainActor
@Observable
final class RecentLocationsTracker {
    typealias PlaceOpener = @MainActor (WorkspaceDocument, EditorPlace) -> Void

    private(set) var history: EditorLocationHistory
    private(set) var isNavigatingNow = false

    @ObservationIgnored private weak var workspace: WorkspaceDocument?
    @ObservationIgnored private let openPlace: PlaceOpener
    @ObservationIgnored private(set) var currentPlace: EditorPlace?
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(
        workspace: WorkspaceDocument,
        history: EditorLocationHistory = EditorLocationHistory(),
        openPlace: @escaping PlaceOpener = RecentLocationsTracker.openInActiveEditor
    ) {
        self.workspace = workspace
        self.history = history
        self.openPlace = openPlace
        currentPlace = Self.livePlace(in: workspace)
        observation = Task { [weak self, weak workspace] in
            let places = Observations { [weak workspace] in Self.livePlace(in: workspace) }
            for await place in places {
                self?.apply(place)
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }

    static func livePlace(in workspace: WorkspaceDocument?) -> EditorPlace? {
        guard let tab = workspace?.editorManager?.activeEditor.selectedTab else { return nil }
        return EditorPlace(fileURL: tab.file.url, positions: tab.cursorPositions)
    }

    static func openInActiveEditor(_ workspace: WorkspaceDocument, _ place: EditorPlace) {
        LSPDefinitionNavigator.open(
            url: place.fileURL,
            position: CursorPosition(line: place.line, column: place.column),
            in: workspace
        )
    }

    var isBackAvailable: Bool { history.isBackAvailable }

    var isForwardAvailable: Bool { history.isForwardAvailable }

    func includeCurrentCommandAsNavigation() {
        guard !isNavigatingNow, let place = Self.livePlace(in: workspace) else { return }
        history.recordBackPlace(place)
        currentPlace = place
    }

    func recordNavigation(from place: EditorPlace) {
        guard !isNavigatingNow else { return }
        history.recordBackPlace(place)
    }

    func recordChange(_ place: EditorPlace) {
        guard !isNavigatingNow else { return }
        history.recordChangePlace(place)
    }

    func goBack() {
        guard let workspace, let target = history.back(from: Self.livePlace(in: workspace)) else { return }
        replay(target, in: workspace)
    }

    func goForward() {
        guard let workspace, let target = history.forward(from: Self.livePlace(in: workspace)) else { return }
        replay(target, in: workspace)
    }

    func navigate(to place: EditorPlace) {
        guard let workspace else { return }
        includeCurrentCommandAsNavigation()
        replay(place, in: workspace)
    }

    func removeInvalidPlaces() {
        history.removeInvalidPlaces()
    }

    func remove(_ place: EditorPlace, changed: Bool) {
        if changed {
            history.removeChangePlaces(sameAs: place)
        } else {
            history.removeBackPlaces(sameAs: place)
        }
    }

    private func replay(_ place: EditorPlace, in workspace: WorkspaceDocument) {
        isNavigatingNow = true
        openPlace(workspace, place)
        currentPlace = Self.livePlace(in: workspace)
        isNavigatingNow = false
    }

    private func apply(_ place: EditorPlace?) {
        guard place != currentPlace else { return }
        if let previous = currentPlace, previous.fileURL != place?.fileURL {
            history.recordBackPlace(previous)
        }
        currentPlace = place
    }
}

@MainActor
final class RecentLocationsStore {
    static let shared = RecentLocationsStore()

    private let trackers = NSMapTable<WorkspaceDocument, RecentLocationsTracker>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: .strongMemory
    )

    func history(for workspace: WorkspaceDocument) -> RecentLocationsTracker {
        if let existing = trackers.object(forKey: workspace) {
            return existing
        }
        let tracker = RecentLocationsTracker(workspace: workspace)
        trackers.setObject(tracker, forKey: workspace)
        return tracker
    }
}
