import SwiftUI

enum WelcomeMetrics {
    static let windowWidth: CGFloat = 800
    static let windowHeight: CGFloat = 650
    static let sidebarWidth: CGFloat = 224
    static let tabHeight: CGFloat = 28
    static let rowHeight: CGFloat = 52
    static let rowIconSize: CGFloat = 36
    static let largeButtonHeight: CGFloat = 36
}

struct WelcomeView: View {
    @Bindable var model: WelcomeViewModel

    var body: some View {
        HStack(spacing: 0) {
            WelcomeSidebar(model: model)
                .frame(width: WelcomeMetrics.sidebarWidth)
            Rectangle()
                .fill(Islands.separator)
                .frame(width: 1)
            Group {
                switch model.selectedTab {
                case .projects:
                    if model.isEmptyState {
                        WelcomeEmptyState(model: model)
                    } else {
                        WelcomeProjectsList(model: model)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Islands.island)
        }
        .frame(width: WelcomeMetrics.windowWidth, height: WelcomeMetrics.windowHeight)
        .background(WelcomeWindowAccessor())
        .dropDestination(for: URL.self, action: dropURLs)
        .task { await model.refresh() }
        .sheet(isPresented: $model.isCloneSheetPresented) {
            GitCloneView(
                viewModel: model.services.makeCloneViewModel(),
                openBranchView: model.showCheckoutBranchAction,
                openDocument: model.openDocumentAction
            )
        }
        .sheet(item: $model.checkoutBranchURL) { url in
            GitCheckoutBranchView(repoLocalPath: url, openDocument: model.openDocumentAction)
        }
    }

    func dropURLs(_ urls: [URL], at location: CGPoint) -> Bool {
        model.open(urls: urls)
    }
}

struct WelcomeScene: Scene {
    @State private var model = WelcomeViewModel()

    var body: some Scene {
        Window("Welcome to \(Bundle.displayName)", id: SceneID.welcome.rawValue) {
            WelcomeView(model: model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
