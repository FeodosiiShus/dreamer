import AppKit
import Foundation
import Synchronization
import Testing
@testable import Dreamder

final class ProjectNavigatorTrashingFileManager: FileManager {
    typealias Failure = @Sendable (URL, URL) -> (any Error)?

    let trashDirectory: URL
    private let failure = Mutex<Failure?>(nil)

    init(trashDirectory: URL) {
        self.trashDirectory = trashDirectory
        super.init()
    }

    func setTransferFailure(_ newFailure: Failure?) {
        failure.withLock { $0 = newFailure }
    }

    private func injectedError(from source: URL, to destination: URL) -> (any Error)? {
        failure.withLock { $0 }?(source, destination)
    }

    override func trashItem(
        at url: URL,
        resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?
    ) throws {
        try moveItem(at: url, to: trashDirectory.appending(path: url.lastPathComponent))
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let error = injectedError(from: srcURL, to: dstURL) {
            throw error
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if let error = injectedError(from: srcURL, to: dstURL) {
            throw error
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

extension ProjectNavigatorFileOperations {
    static func failing(
        with error: any Error,
        where condition: @escaping @Sendable (URL, URL) -> Bool
    ) -> ProjectNavigatorFileOperations {
        ProjectNavigatorFileOperations(
            move: { source, destination in
                if condition(source, destination) { throw error }
                try ProjectNavigatorFileOperations.live.move(source, destination)
            },
            copy: { source, destination in
                if condition(source, destination) { throw error }
                try ProjectNavigatorFileOperations.live.copy(source, destination)
            },
            remove: { try ProjectNavigatorFileOperations.live.remove($0) }
        )
    }
}

extension ProjectNavigatorControllerHarness {
    func failTransfers(with error: any Error, where condition: @escaping @Sendable (URL, URL) -> Bool) throws {
        let manager = try #require(fileManager.fileManager as? ProjectNavigatorTrashingFileManager)
        manager.setTransferFailure { condition($0, $1) ? error : nil }
        controller.fileOperations = .failing(with: error, where: condition)
    }

    func applyFilter() async {
        controller.handleFilterChange()
        await controller.filterTask?.value
    }
}
