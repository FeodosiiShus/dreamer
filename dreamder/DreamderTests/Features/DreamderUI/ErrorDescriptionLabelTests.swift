import AppKit
import SwiftUI
import Testing
@testable import Dreamder

private struct ErrorLabelPlainFailure: Error {}

private struct ErrorLabelDescribedFailure: LocalizedError {
    var errorDescription: String?
    var failureReason: String?
    var recoverySuggestion: String?
}

@MainActor
@Suite(.uiGate)
struct ErrorDescriptionLabelTests {
    @Test func localizedErrorShowsDescriptionReasonAndSuggestionInOrder() {
        let error = ErrorLabelDescribedFailure(
            errorDescription: "Install failed",
            failureReason: "No network",
            recoverySuggestion: "Reconnect and retry"
        )
        #expect(ErrorDescriptionLabel.lines(for: error) == ["Install failed", "No network", "Reconnect and retry"])
    }

    @Test func localizedErrorSkipsMissingParts() {
        #expect(ErrorDescriptionLabel.lines(for: ErrorLabelDescribedFailure(errorDescription: "Only this")) == ["Only this"])
        #expect(ErrorDescriptionLabel.lines(for: ErrorLabelDescribedFailure(failureReason: "Because")) == ["Because"])
        #expect(ErrorDescriptionLabel.lines(for: ErrorLabelDescribedFailure()).isEmpty)
    }

    @Test func plainErrorShowsItsLocalizedDescription() {
        let error = ErrorLabelPlainFailure()
        #expect(ErrorDescriptionLabel.lines(for: error) == [error.localizedDescription])
    }

    @Test func labelRendersEveryKindOfError() async throws {
        let size = NSSize(width: 400, height: 120)
        let described = HostedViewFixture.host(size: size) {
            ErrorDescriptionLabel(
                error: ErrorLabelDescribedFailure(
                    errorDescription: "Install failed",
                    failureReason: "No network",
                    recoverySuggestion: "Reconnect and retry"
                )
            )
        }
        defer { described.close() }
        let plain = HostedViewFixture.host(size: size) {
            ErrorDescriptionLabel(error: ErrorLabelPlainFailure())
        }
        defer { plain.close() }

        try await described.settle()
        try await plain.settle()

        #expect(described.renders())
        #expect(plain.renders())
        #expect(HostedView.pixelsDiffer(described.snapshot(), plain.snapshot()))
    }
}
