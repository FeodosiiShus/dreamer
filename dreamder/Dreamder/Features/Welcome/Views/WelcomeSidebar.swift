import SwiftUI

struct WelcomeSidebar: View {
    let model: WelcomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.appName)
                        .font(Islands.headerTitleFont)
                        .foregroundStyle(Islands.foreground)
                    Text(model.appVersion)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
            }
            .padding(.top, 44)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
            VStack(spacing: 2) {
                ForEach(WelcomeTab.allCases) { tab in
                    WelcomeTabButton(tab: tab, isSelected: model.selectedTab == tab, model: model)
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Islands.frame)
    }
}

struct WelcomeTabButton: View {
    let tab: WelcomeTab
    let isSelected: Bool
    let model: WelcomeViewModel

    var body: some View {
        Button(action: select) {
            Text(tab.title)
                .font(Islands.uiFont)
                .foregroundStyle(Islands.foreground)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: WelcomeMetrics.tabHeight)
                .background {
                    RoundedRectangle(cornerRadius: Islands.rowRadius)
                        .fill(isSelected ? Islands.selection : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func select() {
        model.selectedTab = tab
    }
}
