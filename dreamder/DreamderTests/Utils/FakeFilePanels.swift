import Foundation
@testable import Dreamder

@MainActor
final class FakeFilePanels: FilePanelPresenting {
    var chosenFiles: [URL] = []
    var chosenSaveLocation: URL?
    private(set) var openRequests: [OpenPanelRequest] = []
    private(set) var saveRequests: [SavePanelRequest] = []

    init(files: [URL] = [], saveLocation: URL? = nil) {
        chosenFiles = files
        chosenSaveLocation = saveLocation
    }

    func chooseFiles(_ request: OpenPanelRequest) -> [URL] {
        openRequests.append(request)
        return chosenFiles
    }

    func chooseSaveLocation(_ request: SavePanelRequest) -> URL? {
        saveRequests.append(request)
        return chosenSaveLocation
    }
}
