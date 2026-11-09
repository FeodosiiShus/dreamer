import Foundation
import os
import Synchronization

nonisolated final class UntrustedWorkspaceServerNotice: Sendable {
    typealias Report = @Sendable (_ workspacePath: String, _ executable: String) -> Void

    private static let logger = Logger(
        subsystem: "dev.dreamder.Dreamder",
        category: "LanguageServerDiscovery"
    )

    static let logReport: Report = { workspacePath, executable in
        UntrustedWorkspaceServerNotice.logger.notice(
            "Untrusted workspace \(workspacePath, privacy: .public): skipping \(executable, privacy: .public)"
        )
    }

    static func makeReport(notifier: @escaping @MainActor () -> SafeModeNotifier) -> Report {
        { workspacePath, executable in
            logReport(workspacePath, executable)
            Task { @MainActor in
                notifier().announce(workspacePath: workspacePath, executable: executable)
            }
        }
    }

    static let defaultReport: Report = makeReport(notifier: { SafeModeNotifier.live })

    private let reported = Mutex(Set<String>())
    private let report: Report

    init(report: @escaping Report = UntrustedWorkspaceServerNotice.defaultReport) {
        self.report = report
    }

    func note(workspacePath: String, executable: String) {
        let isFirst = reported.withLock { $0.insert(workspacePath).inserted }
        guard isFirst else { return }
        report(workspacePath, executable)
    }
}
