import Foundation

@MainActor
private final class CompletionGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }
}

@MainActor
struct FormatOnSave {
    static let defaultTimeout: Duration = .seconds(5)

    var isEnabled: () -> Bool
    var canFormat: (CodeFileDocument) -> Bool
    var format: (CodeFileDocument) async -> Void
    var timeout: Duration

    static func live(
        service: FormattingService = FormattingService(),
        timeout: Duration = FormatOnSave.defaultTimeout,
        settings: Settings = .shared
    ) -> FormatOnSave {
        FormatOnSave(
            isEnabled: { settings.preferences.textEditing.formatOnSave },
            canFormat: { service.canFormatDocument($0) },
            format: { _ = await service.formatDocument($0) },
            timeout: timeout
        )
    }

    func shouldFormat(_ codeFile: CodeFileDocument) -> Bool {
        isEnabled() && canFormat(codeFile)
    }

    func run(for codeFile: CodeFileDocument) async {
        guard shouldFormat(codeFile) else { return }
        let gate = CompletionGate()
        let work = Task { @MainActor in
            await format(codeFile)
            gate.open()
        }
        let timer = Task { @MainActor in
            try? await Task.sleep(for: timeout)
            gate.open()
        }
        await gate.wait()
        timer.cancel()
        work.cancel()
    }
}
