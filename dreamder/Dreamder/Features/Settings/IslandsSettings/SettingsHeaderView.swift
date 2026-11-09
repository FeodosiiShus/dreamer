import SwiftUI

struct SettingsHeaderView: View {
    let page: SettingsPage.Name
    let onSelectCategoryPage: (SettingsPage.Name) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if let category = page.category, category.rawValue != page.rawValue {
                Button(action: selectCategoryPage) {
                    Text(category.rawValue)
                        .font(.system(size: Islands.uiFontSize, weight: .semibold))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
                Image("general/chevronRight")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 10, height: 10)
                    .opacity(0.7)
            }
            Text(page.rawValue)
                .font(.system(size: Islands.uiFontSize, weight: .semibold))
                .foregroundStyle(Islands.foreground)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }

    func selectCategoryPage() {
        guard let firstPage = page.category?.pages.first else { return }
        onSelectCategoryPage(firstPage)
    }
}
