import Foundation
import Synchronization
@testable import Dreamder

nonisolated final class FakeDownloader: Sendable {
    enum Behavior: Sendable {
        case file(Data)
        case status(Int)
        case nonHTTP
        case fail
        case missingTemporaryFile
    }

    struct Failure: Error {}

    private let behavior: Behavior
    private let staging: URL
    private let log = Mutex<[URLRequest]>([])

    init(_ behavior: Behavior, staging: URL) {
        self.behavior = behavior
        self.staging = staging
    }

    var requests: [URLRequest] {
        log.withLock { $0 }
    }

    var download: PackageFileDownload {
        { [self] request in try await self.respond(to: request) }
    }

    private func respond(to request: URLRequest) async throws -> (URL, URLResponse) {
        log.withLock { $0.append(request) }
        let url = request.url ?? staging
        switch behavior {
        case .file(let data):
            return (try stage(data), try httpResponse(url: url, status: 200))
        case .status(let status):
            return (try stage(Data("error body".utf8)), try httpResponse(url: url, status: status))
        case .nonHTTP:
            let response = URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            return (try stage(Data()), response)
        case .fail:
            throw Failure()
        case .missingTemporaryFile:
            return (staging.appending(path: "never-written"), try httpResponse(url: url, status: 200))
        }
    }

    private func stage(_ data: Data) throws -> URL {
        let file = staging.appending(path: UUID().uuidString)
        try data.write(to: file)
        return file
    }

    private func httpResponse(url: URL, status: Int) throws -> HTTPURLResponse {
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw Failure()
        }
        return response
    }
}
