import SwiftUI

typealias SceneOpenerInstall = @MainActor (@escaping @MainActor (SceneID) -> Void) -> Void

struct SceneOpenerInstaller: ViewModifier {
    @Environment(\.openWindow)
    private var openWindow

    let install: SceneOpenerInstall?

    func body(content: Content) -> some View {
        content.onAppear {
            guard let install else { return }
            let action = openWindow
            install { action(sceneID: $0) }
        }
    }
}

extension View {
    func installsSceneOpener(_ install: SceneOpenerInstall?) -> some View {
        modifier(SceneOpenerInstaller(install: install))
    }
}
