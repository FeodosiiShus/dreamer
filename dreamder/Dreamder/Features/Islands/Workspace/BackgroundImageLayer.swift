import AppKit
import SwiftUI

struct BackgroundImageLayer: View {
    let image: NSImage?

    @AppStorage(Islands.BackgroundImageKey.fill)
    private var fill = BackgroundImageFill.fill.rawValue

    init(image: NSImage?) {
        self.image = image
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                contents(for: image)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func contents(for image: NSImage) -> some View {
        switch BackgroundImageFill(rawValue: fill) ?? .fill {
        case .fill:
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        case .fit:
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        case .center:
            Image(nsImage: image)
        case .tile:
            Image(nsImage: image)
                .resizable(resizingMode: .tile)
        }
    }

    static func loadImage(at path: String) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let expandedPath = (path as NSString).expandingTildeInPath
        guard FileManager.default.isReadableFile(atPath: expandedPath) else { return nil }
        return NSImage(contentsOfFile: expandedPath)
    }
}
