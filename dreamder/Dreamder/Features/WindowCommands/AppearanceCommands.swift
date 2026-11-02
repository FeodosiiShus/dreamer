import SwiftUI

struct AppearanceCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Background Image") {
                Button("Choose Background Image…") {
                    if let path = BackgroundImageSettings.chooseImage() {
                        BackgroundImageSettings.apply(path)
                    }
                }

                Button("Clear Background Image") {
                    BackgroundImageSettings.apply("")
                }
            }
        }
    }
}
