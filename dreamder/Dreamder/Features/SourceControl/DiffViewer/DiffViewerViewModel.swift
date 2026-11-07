import AppKit
import Foundation

struct DiffScrollRequest: Equatable {
    let row: Int
    let token: Int
}

@MainActor
@Observable
final class DiffViewerViewModel {
    static let maximumDisplayedRows = 20_000

    private(set) var files: [DiffFileRequest]
    private(set) var selectedID: String?
    private(set) var diff: TextDiff?
    private(set) var metrics = DiffLayoutMetrics.empty
    private(set) var isLoading = false
    private(set) var message: String?
    private(set) var currentHunkIndex: Int?
    private(set) var scrollRequest: DiffScrollRequest?
    private(set) var title: String

    private let repository: DiffRepository
    private let mode: DiffViewerMode
    private var loadToken = 0
    private var scrollToken = 0

    init(repository: DiffRepository, mode: DiffViewerMode, files: [DiffFileRequest]) {
        self.repository = repository
        self.mode = mode
        self.files = files
        let first = files.first
        self.selectedID = first?.id
        self.title = first.map { Self.windowTitle(for: $0, mode: mode) } ?? "Diff"
    }

    var showsFileList: Bool { files.count > 1 }

    var selectedFile: DiffFileRequest? {
        guard let selectedID else { return nil }
        return files.first { $0.id == selectedID }
    }

    var differenceCount: Int { diff?.differenceCount ?? 0 }

    var canNavigatePrevious: Bool {
        guard let diff, !diff.hunks.isEmpty else { return false }
        let index = currentHunkIndex ?? diff.hunks.count
        return index > 0
    }

    var canNavigateNext: Bool {
        guard let diff, !diff.hunks.isEmpty else { return false }
        let index = currentHunkIndex ?? -1
        return index < diff.hunks.count - 1
    }

    var differenceSummary: String {
        guard diff != nil else { return "" }
        switch differenceCount {
        case 0:
            return "No differences"
        case 1:
            return "1 difference"
        default:
            return "\(differenceCount) differences"
        }
    }

    func loadInitial() async {
        guard let id = selectedID else { return }
        await select(id)
    }

    func updateFiles(_ files: [DiffFileRequest]) async {
        guard !files.isEmpty else { return }
        self.files = files
        let id = selectedID.flatMap { current in
            files.contains { $0.id == current } ? current : nil
        } ?? files[0].id
        await select(id)
    }

    func select(_ id: String) async {
        guard let file = files.first(where: { $0.id == id }) else { return }
        selectedID = file.id
        title = Self.windowTitle(for: file, mode: mode)
        diff = nil
        metrics = .empty
        message = nil
        currentHunkIndex = nil
        scrollRequest = nil
        isLoading = true

        loadToken += 1
        let token = loadToken
        let content = await repository.load(file)
        guard token == loadToken else { return }

        isLoading = false
        apply(content)
    }

    func nextDifference() {
        guard let diff, !diff.hunks.isEmpty else { return }
        let index = min((currentHunkIndex ?? -1) + 1, diff.hunks.count - 1)
        showHunk(at: index)
    }

    func previousDifference() {
        guard let diff, !diff.hunks.isEmpty else { return }
        let index = max((currentHunkIndex ?? diff.hunks.count) - 1, 0)
        showHunk(at: index)
    }

    private func showHunk(at index: Int) {
        guard let diff, diff.hunks.indices.contains(index) else { return }
        currentHunkIndex = index
        scrollToken += 1
        scrollRequest = DiffScrollRequest(row: diff.hunks[index].rows.lowerBound, token: scrollToken)
    }

    private func apply(_ content: DiffDocumentContent) {
        if content.left.isBinary || content.right.isBinary {
            message = "Binary file"
            return
        }

        let leftText = content.left.stringValue ?? ""
        let rightText = content.right.stringValue ?? ""
        guard !leftText.isEmpty || !rightText.isEmpty else {
            message = "Nothing to compare"
            return
        }

        let diff = TextDiff(left: leftText, right: rightText)
        guard diff.rows.count <= Self.maximumDisplayedRows else {
            message = "Diff is too large to display (\(diff.differenceCount) differences)"
            return
        }

        self.diff = diff
        metrics = DiffLayoutMetrics.make(for: diff)
    }

    private static func windowTitle(for file: DiffFileRequest, mode: DiffViewerMode) -> String {
        switch mode {
        case .workingTree(let ref):
            return "\(file.fileName) (\(ref) vs Local)"
        case let .commit(hash, parentHash):
            let parent = parentHash.map { String($0.prefix(8)) } ?? "Empty"
            return "\(file.fileName) (\(parent) vs \(String(hash.prefix(8))))"
        }
    }
}
