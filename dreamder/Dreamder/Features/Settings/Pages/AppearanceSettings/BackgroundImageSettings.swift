import AppKit
import Foundation
import UniformTypeIdentifiers

enum BackgroundImageFill: String, CaseIterable, Identifiable {
    case fill
    case fit
    case center
    case tile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .center: return "Center"
        case .tile: return "Tile"
        }
    }
}

enum BackgroundImageSettings {
    static func apply(_ path: String, defaults: UserDefaults = .standard) {
        defaults.set(path, forKey: Islands.BackgroundImageKey.path)
    }

    static func chooseImage(panels: any FilePanelPresenting = SystemFilePanels()) -> String? {
        let request = OpenPanelRequest(
            prompt: NSLocalizedString("Choose", comment: ""),
            message: NSLocalizedString("Choose a background image", comment: ""),
            allowedContentTypes: [.image]
        )
        return panels.chooseFiles(request).first?.path
    }

    static func image(at path: String) -> NSImage? {
        guard !path.isEmpty else {
            return nil
        }
        return NSImage(contentsOfFile: path)
    }
}
