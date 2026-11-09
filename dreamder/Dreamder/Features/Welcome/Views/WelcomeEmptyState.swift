import SwiftUI

struct WelcomeEmptyState: View {
    let model: WelcomeViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.appName)
                .font(.system(size: Islands.uiFontSize + 13, weight: .bold))
                .foregroundStyle(Islands.foreground)
                .padding(.top, 105)
                .padding(.bottom, 21)
            Text("Create a new project to start from scratch.")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
                .padding(.bottom, 7)
            Text("Open existing project from disk or version control.")
                .font(Islands.uiFont)
                .foregroundStyle(Islands.secondaryForeground)
            HStack(spacing: 12) {
                WelcomeActionButton(title: "New Project", icon: "general/add", style: .large, action: model.newProject)
                WelcomeActionButton(title: "Open", icon: "general/open", style: .large, action: model.openFromDisk)
                WelcomeActionButton(
                    title: "Clone Repository",
                    icon: "general/download",
                    style: .large,
                    action: model.showCloneSheet
                )
            }
            .padding(.top, 27)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
