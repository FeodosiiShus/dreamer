import AppKit
import CodeEditTextView
import SwiftUI

nonisolated struct DiagnosticTooltipModel: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let severity: WorkspaceDiagnostic.Severity
        let message: String
        let origin: String?
    }

    let entries: [Entry]
    let showsMoreActions: Bool

    static func make(
        diagnostics: [WorkspaceDiagnostic],
        line: Int,
        column: Int,
        showsMoreActions: Bool
    ) -> DiagnosticTooltipModel? {
        var seen = Set<String>()
        let entries = diagnostics
            .filter { contains($0, line: line, column: column) }
            .sorted { $0.severity < $1.severity }
            .compactMap { diagnostic -> Entry? in
                guard seen.insert("\(diagnostic.severity.rawValue):\(diagnostic.message)").inserted else { return nil }
                return Entry(
                    severity: diagnostic.severity,
                    message: diagnostic.message,
                    origin: origin(source: diagnostic.source, code: diagnostic.code)
                )
            }
        guard !entries.isEmpty else { return nil }
        return DiagnosticTooltipModel(entries: entries, showsMoreActions: showsMoreActions)
    }

    static func origin(source: String?, code: String?) -> String? {
        switch (source, code) {
        case let (source?, code?):
            return "\(source) (\(code))"
        case let (source?, nil):
            return source
        case let (nil, code?):
            return code
        case (nil, nil):
            return nil
        }
    }

    private static func contains(_ diagnostic: WorkspaceDiagnostic, line: Int, column: Int) -> Bool {
        guard diagnostic.startLine <= line, diagnostic.endLine >= line else { return false }
        let position = (line: line, column: column)
        let start = (line: diagnostic.startLine, column: diagnostic.startColumn)
        let end = (line: diagnostic.endLine, column: diagnostic.endColumn)
        guard position >= start else { return false }
        if end <= start {
            return position == start
        }
        return position < end
    }
}

struct DiagnosticTooltipView: View {
    static let moreActionsHint = "More actions\u{2026}  \u{2325}\u{23CE}"

    let model: DiagnosticTooltipModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in
                entryRow(entry)
            }
            if model.showsMoreActions {
                Text(Self.moreActionsHint)
                    .font(Islands.smallFont)
                    .foregroundStyle(Islands.link)
            }
        }
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .glassPopup(radius: Islands.popupRadius)
    }

    private func entryRow(_ entry: DiagnosticTooltipModel.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Self.color(for: entry.severity))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.message)
                    .font(Islands.uiFont)
                    .foregroundStyle(Islands.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let origin = entry.origin {
                    Text(verbatim: origin)
                        .font(Islands.smallFont)
                        .foregroundStyle(Islands.secondaryForeground)
                }
            }
        }
    }

    static func color(for severity: WorkspaceDiagnostic.Severity) -> Color {
        switch severity {
        case .error: Islands.errorForeground
        case .warning: Islands.warningForeground
        case .information, .hint: Islands.link
        }
    }
}

@MainActor
final class DiagnosticTooltipPresenter {
    typealias ModelProvider = @MainActor (_ line: Int, _ column: Int) -> DiagnosticTooltipModel?

    typealias PopoverFactory = @MainActor (_ model: DiagnosticTooltipModel, _ anchor: NSRect, _ textView: TextView) -> NSPopover?

    private let delay: Duration
    private let clock: any Clock<Duration>
    private let popoverFactory: PopoverFactory
    private let modelProvider: ModelProvider
    private weak var textView: TextView?
    private var monitor: Any?
    private var showTask: Task<Void, Never>?
    private(set) var popover: NSPopover?
    private(set) var pendingModel: DiagnosticTooltipModel?

    init(
        delay: Duration = .milliseconds(400),
        clock: any Clock<Duration> = ContinuousClock(),
        popoverFactory: @escaping PopoverFactory = { DiagnosticTooltipPresenter.showPopover($0, relativeTo: $1, in: $2) },
        modelProvider: @escaping ModelProvider
    ) {
        self.delay = delay
        self.clock = clock
        self.popoverFactory = popoverFactory
        self.modelProvider = modelProvider
    }

    var isShowing: Bool {
        popover?.isShown ?? false
    }

    func install(textView: TextView) {
        guard monitor == nil else { return }
        self.textView = textView
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func remove() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        dismiss()
        textView = nil
    }

    func handle(_ event: NSEvent) {
        guard let textView, event.window != nil, event.window === textView.window else { return }
        guard event.type == .mouseMoved else {
            dismiss()
            return
        }
        hover(at: textView.convert(event.locationInWindow, from: nil))
    }

    private static func characterOffset(at point: NSPoint, in textView: TextView) -> Int? {
        let layoutManager = textView.layoutManager
        guard let nearest = layoutManager?.textOffsetAtPoint(point) else { return nil }
        guard let line = layoutManager?.textLineForOffset(nearest),
              nearest > line.range.location,
              let boundary = layoutManager?.rectForOffset(nearest),
              point.x < boundary.minX else {
            return nearest
        }
        return nearest - 1
    }

    func hover(at point: NSPoint) {
        guard let textView,
              textView.bounds.contains(point),
              let offset = Self.characterOffset(at: point, in: textView),
              let line = textView.layoutManager.textLineForOffset(offset) else {
            dismiss()
            return
        }
        var anchor = NSRect(origin: point, size: .zero)
        if let rect = textView.layoutManager.rectForOffset(offset) {
            anchor = rect
        }
        hover(line: line.index, column: offset - line.range.location, anchor: anchor)
    }

    func hover(line: Int, column: Int, anchor: NSRect) {
        guard let model = modelProvider(line, column) else {
            dismiss()
            return
        }
        guard model != pendingModel else { return }
        dismiss()
        pendingModel = model
        showTask = Task { [weak self, delay, clock] in
            try? await Task.sleep(for: delay, clock: clock)
            guard !Task.isCancelled else { return }
            self?.present(model, relativeTo: anchor)
        }
    }

    func dismiss() {
        showTask?.cancel()
        showTask = nil
        pendingModel = nil
        popover?.close()
        popover = nil
    }

    private func present(_ model: DiagnosticTooltipModel, relativeTo anchor: NSRect) {
        guard let textView, textView.window != nil else { return }
        popover?.close()
        popover = popoverFactory(model, anchor, textView)
    }

    static func showPopover(_ model: DiagnosticTooltipModel, relativeTo anchor: NSRect, in textView: TextView) -> NSPopover? {
        let controller = NSHostingController(rootView: DiagnosticTooltipView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentViewController = controller
        popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
        return popover
    }
}
