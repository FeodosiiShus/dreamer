import Foundation
import Testing

@MainActor
func eventually(
    timeout: Duration = .seconds(90),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(condition(), sourceLocation: sourceLocation)
}

@MainActor
func eventually(
    timeout: Duration = .seconds(90),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while try await !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(try await condition(), sourceLocation: sourceLocation)
}
