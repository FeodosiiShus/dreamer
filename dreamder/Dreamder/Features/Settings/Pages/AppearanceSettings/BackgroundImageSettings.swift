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
    static func apply(_ path: String) {
        UserDefaults.standard.set(path, forKey: Islands.BackgroundImageKey.path)
    }

    static func chooseImage() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = false
        panel.prompt = NSLocalizedString("Choose", comment: "")
        panel.message = NSLocalizedString("Choose a background image", comment: "")
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return url.path
    }

    static func image(at path: String) -> NSImage? {
        guard !path.isEmpty else {
            return nil
        }
        return NSImage(contentsOfFile: path)
    }
}
