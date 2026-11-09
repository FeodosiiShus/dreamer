import Foundation
import Observation

enum WelcomeTab: String, CaseIterable, Identifiable {
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Projects"
        }
    }
}

enum WelcomeKeyCommand {
    case moveUp
    case moveDown
    case open
    case remove
}

@MainActor
@Observable
final class WelcomeViewModel {
    let manager: RecentProjectsManager
    let services: WelcomeServices
    let home: String

    var selectedTab: WelcomeTab = .projects
    var selection: String?
    var isCloneSheetPresented = false
    var checkoutBranchURL: URL?

    private(set) var query = ""

    init(
        manager: RecentProjectsManager = .shared,
        services: WelcomeServices = .live,
        home: String = NSHomeDirectory()
    ) {
        self.manager = manager
        self.services = services
        self.home = home
        reconcileSelection()
    }

    var appName: String {
        Bundle.displayName
    }

    var appVersion: String {
        Self.versionText(version: Bundle.versionString, postfix: Bundle.versionPostfix)
    }

    static func versionText(version: String?, postfix: String?) -> String {
        "Version \(version ?? "")\(postfix ?? "")"
    }

    var isEmptyState: Bool {
        manager.recentProjects.isEmpty
    }

    var projects: [RecentProject] {
        RecentProjectsFilter.filter(manager.recentProjects, query: query, home: home)
    }

    var selectedProject: RecentProject? {
        projects.first { $0.path == selection }
    }

    func updateQuery(_ text: String) {
        query = text
        selection = projects.first?.path
    }

    func reconcileSelection() {
        guard selectedProject == nil else { return }
        selection = projects.first?.path
    }

    func refresh() async {
        updateQuery("")
        await manager.validate()
        reconcileSelection()
    }

    func moveSelection(by delta: Int) {
        let list = projects
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.path == selection }
        let fallback = delta > 0 ? -1 : list.count
        let target = min(max((current ?? fallback) + delta, 0), list.count - 1)
        selection = list[target].path
    }

    func perform(_ command: WelcomeKeyCommand) {
        switch command {
        case .moveUp: moveSelection(by: -1)
        case .moveDown: moveSelection(by: 1)
        case .open: openSelection()
        case .remove: removeSelection()
        }
    }

    func open(_ project: RecentProject) {
        open(url: project.url)
    }

    func open(url: URL) {
        services.open(url) { [services] in services.dismiss() }
    }

    func open(urls: [URL]) -> Bool {
        urls.forEach { open(url: $0) }
        return !urls.isEmpty
    }

    func openSelection() {
        guard let project = selectedProject else { return }
        open(project)
    }

    func removeSelection() {
        guard let project = selectedProject else { return }
        remove(project)
    }

    func remove(_ project: RecentProject) {
        guard services.confirmRemoval(project) else { return }
        manager.removeRecentProject(path: project.path)
        reconcileSelection()
    }

    func copyPath(of project: RecentProject) {
        services.copyToClipboard(project.path)
    }

    func reveal(_ project: RecentProject) {
        services.reveal([project.url])
    }

    func newProject() {
        services.newProject { [services] in services.dismiss() }
    }

    func openFromDisk() {
        services.openFromDisk { [services] in services.dismiss() }
    }

    func showCloneSheet() {
        isCloneSheetPresented = true
    }

    func showCheckoutBranch(for url: URL) {
        checkoutBranchURL = url
    }

    var showCheckoutBranchAction: (URL) -> Void {
        { [self] url in showCheckoutBranch(for: url) }
    }

    var openDocumentAction: (URL) -> Void {
        { [self] url in open(url: url) }
    }

    var submitSearchAction: () -> Void {
        { [self] in openSelection() }
    }
}
