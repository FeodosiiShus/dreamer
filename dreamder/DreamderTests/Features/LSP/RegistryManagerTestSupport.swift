import Foundation

nonisolated enum StoredZip {
    static func make(entries: [(name: String, contents: String)]) -> Data {
        var archive = Data()
        var directory = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let body = Data(entry.contents.utf8)
            let checksum = crc32(body)
            let offset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0x21))
            archive.appendLittleEndian(checksum)
            archive.appendLittleEndian(UInt32(body.count))
            archive.appendLittleEndian(UInt32(body.count))
            archive.appendLittleEndian(UInt16(name.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(name)
            archive.append(body)

            directory.appendLittleEndian(UInt32(0x0201_4B50))
            directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(20))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0x21))
            directory.appendLittleEndian(checksum)
            directory.appendLittleEndian(UInt32(body.count))
            directory.appendLittleEndian(UInt32(body.count))
            directory.appendLittleEndian(UInt16(name.count))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt16(0))
            directory.appendLittleEndian(UInt32(0))
            directory.appendLittleEndian(offset)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(directory.count))
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

extension Data {
    nonisolated mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

actor FakeNetwork {
    enum Outcome: Sendable {
        case body(Data, status: Int)
        case failure(String)
        case notHTTP
    }

    struct Failure: Error, Sendable {
        let message: String
    }

    private var scripts: [URL: [Outcome]] = [:]
    private var holding = false
    private var heldRequests: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [URL] = []

    func script(_ url: URL, _ outcomes: [Outcome]) {
        scripts[url] = outcomes
    }

    func hold() {
        holding = true
    }

    func release() {
        holding = false
        let waiting = heldRequests
        heldRequests = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    func requestCount(for url: URL) -> Int {
        requests.filter { $0 == url }.count
    }

    func respond(to url: URL) async throws -> (Data, URLResponse) {
        requests.append(url)
        if holding {
            await withCheckedContinuation { heldRequests.append($0) }
        }
        var queue = scripts[url] ?? []
        guard let outcome = queue.first else {
            throw Failure(message: "unscripted \(url.absoluteString)")
        }
        if queue.count > 1 {
            queue.removeFirst()
            scripts[url] = queue
        }
        switch outcome {
        case let .body(data, status):
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            ) else {
                throw Failure(message: "unusable status \(status)")
            }
            return (data, response)
        case .failure(let message):
            throw Failure(message: message)
        case .notHTTP:
            return (Data(), URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
    }
}

actor DelayRecorder {
    private(set) var values: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        values.append(seconds)
    }
}

nonisolated enum RegistryHostileSource: CaseIterable, Sendable {
    case npm
    case pypi
    case cargo
    case golang
    case githubBinary
    case githubBuild

    var sourceID: String {
        switch self {
        case .npm: "pkg:npm/tool@1.0.0"
        case .pypi: "pkg:pypi/tool@1.0.0"
        case .cargo: "pkg:cargo/tool@1.0.0"
        case .golang: "pkg:golang/github.com/acme/tool@v1.0.0"
        case .githubBinary, .githubBuild: "pkg:github/acme/tool@v1.0.0"
        }
    }

    var sourceExtras: String {
        switch self {
        case .npm, .pypi, .cargo, .golang: ""
        case .githubBinary: #", "asset": { "target": "darwin", "file": "tool.zip" }"#
        case .githubBuild: #", "build": { "run": "make" }"#
        }
    }
}
