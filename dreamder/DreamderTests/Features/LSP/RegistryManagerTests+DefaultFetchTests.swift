import Foundation
import Testing
@testable import Dreamder

extension RegistryManagerTests {
    @Test
    func theDefaultFetchReportsAnUnreachableHostAsAConnectionError() async throws {
        try await withTempDir { directory in
            let manager = RegistryManager(
                installPath: installPath(in: directory),
                registryURL: nil,
                checksumURL: nil
            )
            let unreachable = try #require(URL(string: "https://127.0.0.1:1/registry.json.zip"))

            await #expect(throws: URLError.self) {
                try await manager.fetch(unreachable)
            }
            #expect(manager.registryItems.isEmpty)
        }
    }

    @Test
    func theDefaultFetchReadsTheBytesOfAFileUrl() async throws {
        try await withTempDir { directory in
            let manager = RegistryManager(
                installPath: installPath(in: directory),
                registryURL: nil,
                checksumURL: nil
            )
            let file = directory.appending(path: "payload.bin")
            try Data("registry bytes".utf8).write(to: file)

            let (data, response) = try await manager.fetch(file)

            #expect(data == Data("registry bytes".utf8))
            #expect(response.url == file)
        }
    }
}
