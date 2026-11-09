import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage private var density: String

    @AppStorage private var imagePath: String

    @AppStorage private var imageOpacity: Double

    @AppStorage private var fillMode: String

    private let panels: any FilePanelPresenting

    init(
        defaults: UserDefaults = .standard,
        panels: any FilePanelPresenting = SystemFilePanels()
    ) {
        self._density = AppStorage(
            wrappedValue: Islands.Density.compact.rawValue,
            Islands.densityKey,
            store: defaults
        )
        self._imagePath = AppStorage(wrappedValue: "", Islands.BackgroundImageKey.path, store: defaults)
        self._imageOpacity = AppStorage(
            wrappedValue: Islands.BackgroundImageKey.defaultOpacity,
            Islands.BackgroundImageKey.opacity,
            store: defaults
        )
        self._fillMode = AppStorage(
            wrappedValue: BackgroundImageFill.fill.rawValue,
            Islands.BackgroundImageKey.fill,
            store: defaults
        )
        self.panels = panels
    }

    static let searchKeys: [String] = [
        "Density",
        "Compact",
        "Default Density",
        "Background Image",
        "Choose Background Image",
        "Clear Background Image",
        "Background Image Opacity",
        "Background Image Fill"
    ].map { NSLocalizedString($0, comment: "") }

    var body: some View {
        SettingsForm {
            Section {
                densityRow
            } header: {
                Text("Interface")
            }
            Section {
                pathRow
                actionsRow
                preview
                opacityRow
                fillRow
            } header: {
                Text("Background Image")
            }
        }
    }

    private var densityRow: some View {
        Picker("Density", selection: $density) {
            ForEach(Islands.Density.allCases) { density in
                Text(density.title).tag(density.rawValue)
            }
        }
        .pickerStyle(.menu)
    }

    private var pathRow: some View {
        LabeledContent("Image") {
            Text(imagePath.isEmpty ? "None" : imagePath)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 8) {
            Button("Choose Image…", action: chooseImage)
            Button("Clear", action: clearImage)
                .disabled(imagePath.isEmpty)
        }
    }

    func chooseImage() {
        if let path = BackgroundImageSettings.chooseImage(panels: panels) {
            imagePath = path
        }
    }

    func clearImage() {
        imagePath = ""
    }

    private var preview: some View {
        ZStack {
            Islands.frame
            if let image = BackgroundImageSettings.image(at: imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: previewContentMode)
                    .opacity(imageOpacity)
            }
        }
        .frame(width: 200, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: Islands.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Islands.controlRadius, style: .continuous)
                .strokeBorder(Islands.componentBorder, lineWidth: 1)
        }
        .padding(.vertical, 2)
    }

    private var opacityRow: some View {
        LabeledContent("Opacity") {
            HStack(spacing: 8) {
                Slider(value: $imageOpacity, in: 0.05...0.9)
                Text("\(Int((imageOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .disabled(imagePath.isEmpty)
    }

    private var fillRow: some View {
        Picker("Fill", selection: $fillMode) {
            ForEach(BackgroundImageFill.allCases) { fill in
                Text(fill.title).tag(fill.rawValue)
            }
        }
        .pickerStyle(.menu)
        .disabled(imagePath.isEmpty)
    }

    private var previewContentMode: ContentMode {
        switch BackgroundImageFill(rawValue: fillMode) ?? .fill {
        case .fill, .tile:
            return .fill
        case .fit, .center:
            return .fit
        }
    }
}
