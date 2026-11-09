import AppKit
import SwiftUI

struct BranchesPopupRowActions {
    let row: BranchesPopupRow
    let viewModel: BranchesPopupViewModel
    let anchors: BranchesPopupRowAnchors
    let presentMenu: @MainActor (BranchesPopupRow, BranchesPopupRowAnchors, BranchesPopupViewModel) -> Void
    let focusSearch: @MainActor () -> Void

    func activate() {
        viewModel.activate(row)
        focusSearch()
    }

    func toggle() {
        viewModel.toggleExpansion(row.id)
        focusSearch()
    }

    func openMenu() {
        presentMenu(row, anchors, viewModel)
        focusSearch()
    }

    func toggleFavorite() {
        if let ref = row.ref {
            viewModel.toggleFavorite(ref)
        }
        focusSearch()
    }
}

struct GitBranchesPopupView: View {
    private let dismissPopup: () -> Void
    private let onSizeChange: ((CGSize) -> Void)?
    let presentMenu: @MainActor (BranchesPopupRow, BranchesPopupRowAnchors, BranchesPopupViewModel) -> Void

    @State private var viewModel: BranchesPopupViewModel
    @State private var anchors = BranchesPopupRowAnchors()
    @State private var keyMonitor: BranchesPopupKeyMonitor?
    @State private var popupWindow: NSWindow?
    @State private var searchText: String
    @FocusState private var isSearchFocused: Bool

    init(
        sourceControlManager: SourceControlManager,
        workspace: WorkspaceDocument,
        dismiss: @escaping () -> Void,
        onSizeChange: ((CGSize) -> Void)? = nil
    ) {
        self.init(
            viewModel: BranchesPopupViewModel(
                sourceControlManager: sourceControlManager,
                workspace: workspace,
                dismiss: dismiss
            ),
            dismiss: dismiss,
            onSizeChange: onSizeChange
        )
    }

    init(
        viewModel: BranchesPopupViewModel,
        dismiss: @escaping () -> Void,
        onSizeChange: ((CGSize) -> Void)? = nil,
        initialSearchText: String = "",
        presentMenu: @escaping @MainActor (BranchesPopupRow, BranchesPopupRowAnchors, BranchesPopupViewModel) -> Void
            = { BranchesPopupMenuPresenter.present(row: $0, anchors: $1, model: $2) }
    ) {
        self.dismissPopup = dismiss
        self.onSizeChange = onSizeChange
        self.presentMenu = presentMenu
        _viewModel = State(wrappedValue: viewModel)
        _searchText = State(wrappedValue: initialSearchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(width: 380, height: viewModel.preferredHeight)
        .glassPopup()
        .modifier(BranchesPopupSizeReporter(onSizeChange: onSizeChange))
        .background(
            BranchesPopupWindowReader(onWindowChange: configureWindow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        .onAppear(perform: appeared)
        .onDisappear(perform: removeKeyMonitor)
        .task { await viewModel.reload() }
        .task(id: searchText) { await applySearchText() }
    }

    func appeared() {
        viewModel.presentRefActions = { row in
            presentMenu(row, anchors, viewModel)
        }
        requestSearchFocus()
    }

    func removeKeyMonitor() {
        keyMonitor?.remove()
        keyMonitor = nil
    }

    func applySearchText() async {
        if searchText == viewModel.query { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        viewModel.query = searchText
    }

    func searchTextChanged(_ oldValue: String, _ value: String) {
        guard value == "/" else { return }
        searchText = ""
        viewModel.query = ""
    }

    private var header: some View {
        HStack(spacing: 4) {
            HStack(spacing: 5) {
                Image("general/search")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 14, height: 14)
                TextField("Search for branches and actions", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                    .focused($isSearchFocused)
                    .onChange(of: searchText, searchTextChanged)
            }
            .padding(.horizontal, 7)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Islands.controlRadius).fill(Islands.islandRaised))
            .overlay(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .strokeBorder(Islands.componentBorder, lineWidth: 1)
            )

            Button(action: viewModel.fetch) {
                fetchLabel
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .help("Fetch")

            Menu {
                Toggle("Show Actions in Search Results", isOn: $viewModel.showsActionsInSearch)
                Divider()
                Toggle("Group by Directory", isOn: $viewModel.groupsByDirectory)
                Toggle("Show Recent Branches", isOn: $viewModel.showsRecentBranches)
                Toggle("Show Tags", isOn: $viewModel.showsTags)
            } label: {
                Image("general/settings")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .help("Options")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var fetchLabel: some View {
        if viewModel.isFetching {
            ProgressView()
                .controlSize(.small)
        } else {
            Image("vcs/fetch")
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            rowContent(row)
                        }
                        if let message = viewModel.emptyMessage {
                            Text(message)
                                .font(Islands.smallFont)
                                .foregroundStyle(Islands.secondaryForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                }
                .onChange(of: viewModel.selectedID) { _, selectedID in
                    guard let selectedID else { return }
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ row: BranchesPopupRow) -> some View {
        if row.kind == .separator {
            Rectangle()
                .fill(Islands.separator)
                .frame(height: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        } else {
            let actions = BranchesPopupRowActions(
                row: row,
                viewModel: viewModel,
                anchors: anchors,
                presentMenu: presentMenu,
                focusSearch: requestSearchFocus
            )
            BranchesPopupRowView(
                row: row,
                isSelected: viewModel.selectedID == row.id,
                isExpanded: row.isExpanded,
                onActivate: actions.activate,
                onToggle: actions.toggle,
                onOpenMenu: actions.openMenu,
                onToggleFavorite: actions.toggleFavorite
            )
            .overlay(alignment: .topTrailing) {
                BranchesPopupAnchorView(id: row.id, anchors: anchors)
                    .frame(width: 1, height: 1)
            }
            .id(row.id)
        }
    }

    private func requestSearchFocus() {
        Task { isSearchFocused = true }
    }

    private func configureWindow(_ window: NSWindow?) {
        guard let window, popupWindow !== window else { return }
        popupWindow = window
        let monitor = BranchesPopupKeyMonitor { event in
            BranchesPopupKeyboard.handle(
                event,
                model: viewModel,
                anchors: anchors,
                dismiss: dismissPopup
            )
        }
        monitor.install(on: window)
        keyMonitor?.remove()
        keyMonitor = monitor
        requestSearchFocus()
    }
}
