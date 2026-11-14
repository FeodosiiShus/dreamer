import SwiftUI

extension CommitToolWindowActions {
    var amendBinding: Binding<Bool> {
        Binding(
            get: { viewModel.amend },
            set: { startSetAmend($0) }
        )
    }
}
