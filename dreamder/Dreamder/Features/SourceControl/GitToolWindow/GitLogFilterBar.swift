import SwiftUI

struct GitLogFilterBar: View {
    @Environment(SourceControlManager.self) private var sourceControlManager
    let viewModel: GitLogViewModel

    @State private var text = ""
    @State private var matchesCase = false
    @State private var usesRegex = false
    @State private var showsBranches = false
    @State private var showsUsers = false
    @State private var showsDates = false
    @State private var showsPaths = false
    @State private var pathsText = ""
    @State private var afterDate = Date()
    @State private var beforeDate = Date()
    @State private var usesAfter = false
    @State private var usesBefore = false

    private struct TextState: Hashable {
        let text: String
        let matchesCase: Bool
        let usesRegex: Bool
    }

    var body: some View {
        VStack(spacing: 6) {
            textField
            HStack(spacing: 6) {
                popupButton(
                    title: "Branch",
                    value: viewModel.filters.branch?.displayText,
                    isPresented: $showsBranches
                ) {
                    branchesPopup
                }
                popupButton(
                    title: "User",
                    value: viewModel.filters.user?.displayText,
                    isPresented: $showsUsers
                ) {
                    usersPopup
                }
                popupButton(
                    title: "Date",
                    value: dateSummary,
                    isPresented: $showsDates
                ) {
                    datesPopup
                }
                popupButton(
                    title: "Paths",
                    value: viewModel.filters.structure?.paths.joined(separator: ", "),
                    isPresented: $showsPaths
                ) {
                    pathsPopup
                }
                optionsMenu
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .task(id: TextState(text: text, matchesCase: matchesCase, usesRegex: usesRegex)) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let updated = viewModel.filters.settingText(text, isRegexpAllowed: usesRegex, isMatchCase: matchesCase)
            guard updated != viewModel.filters else { return }
            await viewModel.setFilters(updated)
        }
    }

    private var textField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Islands.secondaryForeground)
            TextField(
                "",
                text: $text,
                prompt: Text("Text or hash").foregroundStyle(Islands.disabledForeground)
            )
            .textFieldStyle(.plain)
            .font(Islands.uiFont)
            .foregroundStyle(Islands.foreground)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Islands.secondaryForeground)
                }
                .buttonStyle(.plain)
            }
            toggleButton("Cc", help: "Match Case", isOn: $matchesCase)
            toggleButton(".*", help: "Regex", isOn: $usesRegex)
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

    private func toggleButton(_ label: String, help: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isOn.wrappedValue ? Islands.foreground : Islands.secondaryForeground)
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: Islands.rowRadius)
                        .fill(isOn.wrappedValue ? Islands.selection : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func popupButton<Content: View>(
        title: String,
        value: String?,
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isActive = value?.isEmpty == false
        return Button {
            isPresented.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(isActive ? "\(title): \(value ?? "")" : title)
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
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            content()
        }
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Hide Merge Commits", isOn: parentBinding(.noMerges))
            Toggle("Only Merge Commits", isOn: parentBinding(.onlyMerges))
            Divider()
            Toggle("First Parent Only", isOn: firstParentBinding)
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

    private func parentBinding(_ filter: GitLogParentFilter) -> Binding<Bool> {
        Binding {
            viewModel.filters.parent == filter
        } set: { isOn in
            let updated = viewModel.filters.settingParent(isOn ? filter : nil)
            Task {
                await viewModel.setFilters(updated)
            }
        }
    }

    private var firstParentBinding: Binding<Bool> {
        Binding {
            viewModel.options.firstParent
        } set: { isOn in
            Task {
                await viewModel.setFirstParent(isOn)
            }
        }
    }

    private var branchesPopup: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GitLogBranchRow(
                    title: "All",
                    subtitle: nil,
                    icon: "vcs/currentBranchLabel",
                    isSelected: viewModel.filters.branch == nil
                ) {
                    chooseBranch(nil)
                }
                GitLogBranchRow(
                    title: "HEAD",
                    subtitle: sourceControlManager.currentBranch?.name,
                    icon: "vcs/currentBranchLabel",
                    isSelected: viewModel.filters.branch == .fromBranch("HEAD")
                ) {
                    chooseBranch(.fromBranch("HEAD"))
                }
                ForEach(branchNames, id: \.self) { name in
                    GitLogBranchRow(
                        title: name,
                        subtitle: nil,
                        icon: "vcs/branch",
                        isSelected: viewModel.filters.branch == .fromBranch(name)
                    ) {
                        chooseBranch(.fromBranch(name))
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 260, height: 280)
    }

    private var branchNames: [String] {
        sourceControlManager.orderedLocalBranches.map(\.logFilterName)
            + sourceControlManager.branches.filter(\.isRemote).map(\.logFilterName).sorted()
    }

    private func chooseBranch(_ filter: GitLogBranchFilter?) {
        showsBranches = false
        Task {
            await viewModel.setBranchFilter(filter)
        }
    }

    private var usersPopup: some View {
        let selected = Set(viewModel.filters.user?.userNames ?? [])
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                GitLogBranchRow(
                    title: "All",
                    subtitle: nil,
                    icon: "general/user",
                    isSelected: selected.isEmpty
                ) {
                    chooseUsers([])
                }
                GitLogBranchRow(
                    title: "me",
                    subtitle: nil,
                    icon: "general/user",
                    isSelected: selected.contains(GitLogUserFilter.me)
                ) {
                    toggleUser(GitLogUserFilter.me, selected: selected)
                }
                ForEach(viewModel.availableUsers, id: \.self) { user in
                    GitLogBranchRow(
                        title: user.shortPresentation,
                        subtitle: user.email,
                        icon: "general/user",
                        isSelected: selected.contains(user.shortPresentation)
                    ) {
                        toggleUser(user.shortPresentation, selected: selected)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280, height: 280)
    }

    private func toggleUser(_ name: String, selected: Set<String>) {
        var names = viewModel.filters.user?.userNames ?? []
        if selected.contains(name) {
            names.removeAll { $0 == name }
        } else {
            names.append(name)
        }
        chooseUsers(names)
    }

    private func chooseUsers(_ names: [String]) {
        let updated = viewModel.filters.settingUserNames(names)
        Task {
            await viewModel.setFilters(updated)
        }
    }

    private var dateSummary: String? {
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

    private var datesPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(GitLogDatePreset.allCases) { preset in
                Button(preset.title) {
                    applyDate(after: preset.filter().after, before: nil)
                }
                .buttonStyle(.plain)
                .font(Islands.uiFont)
            }
            Divider()
            Toggle("After", isOn: $usesAfter)
            if usesAfter {
                DatePicker("", selection: $afterDate, displayedComponents: .date)
                    .labelsHidden()
            }
            Toggle("Before", isOn: $usesBefore)
            if usesBefore {
                DatePicker("", selection: $beforeDate, displayedComponents: .date)
                    .labelsHidden()
            }
            HStack {
                Button("Clear") {
                    usesAfter = false
                    usesBefore = false
                    applyDate(after: nil, before: nil)
                }
                Spacer()
                Button("Apply") {
                    applyDate(after: usesAfter ? afterDate : nil, before: usesBefore ? beforeDate : nil)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func applyDate(after: Date?, before: Date?) {
        showsDates = false
        let updated = viewModel.filters.settingDate(after: after, before: before)
        Task {
            await viewModel.setFilters(updated)
        }
    }

    private var pathsPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paths relative to the repository root, separated by commas or new lines")
                .font(Islands.smallFont)
                .foregroundStyle(Islands.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $pathsText)
                .font(Islands.uiFont)
                .frame(height: 80)
            HStack {
                Button("Clear") {
                    pathsText = ""
                    applyPaths()
                }
                Spacer()
                Button("Apply") {
                    applyPaths()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func applyPaths() {
        showsPaths = false
        let updated = viewModel.filters.settingPaths(from: pathsText)
        Task {
            await viewModel.setFilters(updated)
        }
    }
}
