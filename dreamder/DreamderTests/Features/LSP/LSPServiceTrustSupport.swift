import Foundation
import Synchronization
@testable import Dreamder

final class UntrustedNoticeRecorder: Sendable {
    struct Report: Equatable {
        let workspacePath: String
        let executable: String
    }

    private let storage = Mutex<[Report]>([])

    var reports: [Report] {
        storage.withLock { $0 }
    }

    func record(_ workspacePath: String, _ executable: String) {
        storage.withLock { $0.append(Report(workspacePath: workspacePath, executable: executable)) }
    }
}

@MainActor
final class LSPServiceBox {
    var service: LSPService?
}
