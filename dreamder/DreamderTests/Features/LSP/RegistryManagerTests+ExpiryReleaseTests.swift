import Foundation
import Synchronization
import Testing
@testable import Dreamder

private final class ExpiryReturnedFlag: Sendable {
    let value = Mutex(false)
}

extension RegistryManagerTests {
    @Test
    func aManagerReleasedBeforeItsCacheExpiresIsNotTouchedWhenTheExpiryReturns() async throws {
        try await withTempDir { directory in
            let path = installPath(in: directory)
            try seedRegistry(Self.staleJSON, at: path)
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            let returned = ExpiryReturnedFlag()
            var manager: RegistryManager? = RegistryManager(
                installPath: path,
                registryURL: nil,
                checksumURL: nil,
                cacheExpiry: {
                    for await _ in stream { break }
                    returned.value.withLock { $0 = true }
                }
            )
            weak let released = manager
            #expect(manager?.registryItems.map(\.name) == ["stale-ls"])

            manager = nil
            try await eventually { released == nil }
            continuation.yield()
            try await eventually { returned.value.withLock { $0 } }
            await Task.yield()
            await Task.yield()

            #expect(released == nil)
            #expect(returned.value.withLock { $0 })
        }
    }
}
