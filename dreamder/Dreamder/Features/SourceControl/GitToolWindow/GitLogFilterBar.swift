import SwiftUI

@Observable
final class GitLogFilterBarModel {
    struct TextState: Hashable {
        let text: String
        let matchesCase: Bool
        let usesRegex: Bool
    }

    let viewModel: GitLogViewModel
    let debounce: Duration

    var text = ""
    var matchesCase = false
    var usesRegex = false
    var showsBranches = false
    var showsUsers = false
    var showsDates = false
    var showsPaths = false
    var pathsText = ""
    var afterDate = Date()
    var beforeDate = Date()
    var usesAfter = false
    var usesBefore = false

    init(viewModel: GitLogViewModel, debounce: Duration = .milliseconds(250)) {
        self.viewModel = viewModel
        self.debounce = debounce
    }

    var textState: TextState {
        TextState(text: text, matchesCase: matchesCase, usesRegex: usesRegex)
    }

    func applyDebouncedText() async {
        try? await Task.sleep(for: debounce)
        guard !Task.isCancelled else { return }
        let updated = viewModel.filters.settingText(text, isRegexpAllowed: usesRegex, isMatchCase: matchesCase)
        guard updated != viewModel.filters else { return }
        await viewModel.setFilters(updated)
    }

    func clearText() {
        text = ""
    }

    func toggleMatchCase() {
        matchesCase.toggle()
    }

    func toggleRegex() {
        usesRegex.toggle()
    }

    func toggler(_ flag: ReferenceWritableKeyPath<GitLogFilterBarModel, Bool>) -> () -> Void {
        { self[keyPath: flag].toggle() }
    }

    func parentBinding(_ filter: GitLogParentFilter) -> Binding<Bool> {
        Binding {
            self.viewModel.filters.parent == filter
        } set: { isOn in
            self.update(self.viewModel.filters.settingParent(isOn ? filter : nil))
        }
    }

    var firstParentBinding: Binding<Bool> {
        Binding {
            self.viewModel.options.firstParent
        } set: { isOn in
            Task {
                await self.viewModel.setFirstParent(isOn)
            }
        }
    }

    func branchAction(_ filter: GitLogBranchFilter?) -> () -> Void {
        { self.chooseBranch(filter) }
    }

    func chooseBranch(_ filter: GitLogBranchFilter?) {
        showsBranches = false
        Task {
            await viewModel.setBranchFilter(filter)
        }
    }

    func clearUsersAction() -> () -> Void {
        { self.chooseUsers([]) }
    }

    func toggleUserAction(_ name: String) -> () -> Void {
        { self.toggleUser(name) }
    }

    func toggleUser(_ name: String) {
        var names = viewModel.filters.user?.userNames ?? []
        if names.contains(name) {
            names.removeAll { $0 == name }
        } else {
            names.append(name)
        }
        chooseUsers(names)
    }

    func chooseUsers(_ names: [String]) {
        update(viewModel.filters.settingUserNames(names))
    }

    var dateSummary: String? {
        guard let date = viewModel.filters.date else { return nil }
        switch (date.after, date.before) {
        case (let after?, let before?):
            return "\(after.formatted(date: .abbreviated, time: .omitted)) – \(before.formatted(date: .abbreviated, time: .omitted))"
        case (let after?, nil):
            return "since \(after.formatted(date: .abbreviated, time: .omitted))"
        case (nil, let before?):
            return "until \(before.formatted(date: .abbreviated, time: .omitted))"
        case (nil, nil):
            return nil
        }
    }

    func presetAction(_ preset: GitLogDatePreset) -> () -> Void {
        { self.applyDate(after: preset.filter().after, before: nil) }
    }

    func clearDates() {
        usesAfter = false
        usesBefore = false
        applyDate(after: nil, before: nil)
    }

    func applyDates() {
        applyDate(after: usesAfter ? afterDate : nil, before: usesBefore ? beforeDate : nil)
    }

    func applyDate(after: Date?, before: Date?) {
        showsDates = false
        update(viewModel.filters.settingDate(after: after, before: before))
    }

    func clearPaths() {
        pathsText = ""
        applyPaths()
    }

    func applyPaths() {
        showsPaths = false
        update(viewModel.filters.settingPaths(from: pathsText))
    }

    private func update(_ updated: GitLogFilterCollection) {
        Task {
            await viewModel.setFilters(updated)
        }
    }
}

struct GitLogFilterBar: View {
    @State private var model: GitLogFilterBarModel

    init(viewModel: GitLogViewModel, model: GitLogFilterBarModel? = nil) {
        _model = State(initialValue: model ?? GitLogFilterBarModel(viewModel: viewModel))
    }

    private var viewModel: GitLogViewModel {
        model.viewModel
    }

    var body: some View {
        VStack(spacing: 6) {
            textField
            HStack(spacing: 6) {
                popupButton(
                    title: "Branch",
                    value: viewModel.filters.branch?.displayText,
                    isPresented: $model.showsBranches,
                    toggle: model.toggler(\.showsBranches),
                    content: GitLogBranchFilterPopup(model: model)
                )
                popupButton(
                    title: "User",
                    value: viewModel.filters.user?.displayText,
                    isPresented: $model.showsUsers,
                    toggle: model.toggler(\.showsUsers),
                    content: GitLogUserFilterPopup(model: model)
                )
                popupButton(
                    title: "Date",
                    value: model.dateSummary,
                    isPresented: $model.showsDates,
                    toggle: model.toggler(\.showsDates),
                    content: GitLogDateFilterPopup(model: model)
                )
                popupButton(
                    title: "Paths",
                    value: viewModel.filters.structure?.paths.joined(separator: ", "),
                    isPresented: $model.showsPaths,
                    toggle: model.toggler(\.showsPaths),
                    content: GitLogPathsFilterPopup(model: model)
                )
                optionsMenu
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .task(id: model.textState) {
            await model.applyDebouncedText()
        }
    }

    private var textField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Islands.secondaryForeground)
            TextField(
                "",
                text: $model.text,
                prompt: Text("Text or hash").foregroundStyle(Islands.disabledForeground)
            )
            .textFieldStyle(.plain)
            .font(Islands.uiFont)
            .foregroundStyle(Islands.foreground)
            if !model.text.isEmpty {
                Button(action: model.clearText) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
            }
            toggleButton("Cc", help: "Match Case", isOn: model.matchesCase, action: model.toggleMatchCase)
            toggleButton(".*", help: "Regex", isOn: model.usesRegex, action: model.toggleRegex)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .fill(Islands.islandRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Islands.controlRadius)
                .strokeBorder(Islands.componentBorder, lineWidth: 1)
        )
    }

    private func toggleButton(
        _ label: String,
        help: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isOn ? Islands.foreground : Islands.secondaryForeground)
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: Islands.rowRadius)
                        .fill(isOn ? Islands.selection : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func popupButton<Content: View>(
        title: String,
        value: String?,
        isPresented: Binding<Bool>,
        toggle: @escaping () -> Void,
        content: Content
    ) -> some View {
        let isActive = value?.isEmpty == false
        return Button(action: toggle) {
            HStack(spacing: 4) {
                Text(Self.popupLabel(title: title, value: value))
                    .font(Islands.smallFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(isActive ? Islands.foreground : Islands.secondaryForeground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: Islands.controlRadius)
                    .fill(isActive ? Islands.selection : Islands.hover)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .bottom) { content }
    }

    static func popupLabel(title: String, value: String?) -> String {
        guard let value, !value.isEmpty else { return title }
        return "\(title): \(value)"
    }

    private var optionsMenu: some View {
        Menu {
            GitLogFilterOptionItems(model: model)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundStyle(Islands.secondaryForeground)
                .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Options")
    }
}

struct GitLogFilterOptionItems: View {
    let model: GitLogFilterBarModel

    var body: some View {
        Toggle("Hide Merge Commits", isOn: model.parentBinding(.noMerges))
        Toggle("Only Merge Commits", isOn: model.parentBinding(.onlyMerges))
        Divider()
        Toggle("First Parent Only", isOn: model.firstParentBinding)
    }
}

struct GitLogBranchFilterPopup: View {
    @Environment(SourceControlManager.self) private var sourceControlManager
    let model: GitLogFilterBarModel

    private var branchNames: [String] {
        sourceControlManager.orderedLocalBranches.map(\.logFilterName)
            + sourceControlManager.branches.filter(\.isRemote).map(\.logFilterName).sorted()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GitLogBranchRow(
                    title: "All",
                    subtitle: nil,
                    icon: "vcs/currentBranchLabel",
                    isSelected: model.viewModel.filters.branch == nil,
                    action: model.branchAction(nil)
                )
                GitLogBranchRow(
                    title: "HEAD",
                    subtitle: sourceControlManager.currentBranch?.name,
                    icon: "vcs/currentBranchLabel",
                    isSelected: model.viewModel.filters.branch == .fromBranch("HEAD"),
                    action: model.branchAction(.fromBranch("HEAD"))
                )
                ForEach(branchNames, id: \.self) { name in
                    GitLogBranchRow(
                        title: name,
                        subtitle: nil,
                        icon: "vcs/branch",
                        isSelected: model.viewModel.filters.branch == .fromBranch(name),
                        action: model.branchAction(.fromBranch(name))
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 260, height: 280)
    }
}

struct GitLogUserFilterPopup: View {
    let model: GitLogFilterBarModel

    var body: some View {
        let selected = Set(model.viewModel.filters.user?.userNames ?? [])
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GitLogBranchRow(
                    title: "All",
                    subtitle: nil,
                    icon: "general/user",
                    isSelected: selected.isEmpty,
                    action: model.clearUsersAction()
                )
                GitLogBranchRow(
                    title: "me",
                    subtitle: nil,
                    icon: "general/user",
                    isSelected: selected.contains(GitLogUserFilter.me),
                    action: model.toggleUserAction(GitLogUserFilter.me)
                )
                ForEach(model.viewModel.availableUsers, id: \.self) { user in
                    GitLogBranchRow(
                        title: user.shortPresentation,
                        subtitle: user.email,
                        icon: "general/user",
                        isSelected: selected.contains(user.shortPresentation),
                        action: model.toggleUserAction(user.shortPresentation)
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280, height: 280)
    }
}

struct GitLogDateFilterPopup: View {
    @Bindable var model: GitLogFilterBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(GitLogDatePreset.allCases) { preset in
                Button(preset.title, action: model.presetAction(preset))
                    .buttonStyle(.plain)
                    .font(Islands.uiFont)
            }
            Divider()
            Toggle("After", isOn: $model.usesAfter)
            if model.usesAfter {
                DatePicker("", selection: $model.afterDate, displayedComponents: .date)
                    .labelsHidden()
            }
            Toggle("Before", isOn: $model.usesBefore)
            if model.usesBefore {
                DatePicker("", selection: $model.beforeDate, displayedComponents: .date)
                    .labelsHidden()
            }
            HStack {
                Button("Clear", action: model.clearDates)
                Spacer()
                Button("Apply", action: model.applyDates)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}

struct GitLogPathsFilterPopup: View {
    @Bindable var model: GitLogFilterBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paths relative to the repository root, separated by commas or new lines")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $model.pathsText)
                .font(Islands.uiFont)
                .frame(height: 80)
            HStack {
                Button("Clear", action: model.clearPaths)
                Spacer()
                Button("Apply", action: model.applyPaths)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
