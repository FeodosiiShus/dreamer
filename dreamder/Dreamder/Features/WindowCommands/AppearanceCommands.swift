import SwiftUI

struct AppearanceCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Background Image") {
                BackgroundImageButtons()
            }
        }
    }
}

extension AppearanceCommands {
    struct BackgroundImageButtons: View {
        var chooseImage: @MainActor () -> String? = { BackgroundImageSettings.chooseImage() }

        var body: some View {
            Button("Choose Background Image…") {
                if let path = chooseImage() {
                    BackgroundImageSettings.apply(path)
                }
            }
            .keymapShortcut(.chooseBackgroundImage)

            Button("Clear Background Image") {
                BackgroundImageSettings.apply("")
            }
            .keymapShortcut(.clearBackgroundImage)
        }
    }
}
