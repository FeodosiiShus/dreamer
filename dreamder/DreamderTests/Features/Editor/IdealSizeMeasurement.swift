import AppKit
import SwiftUI
import Testing
@testable import Dreamder

@MainActor
final class IdealSizeRecorder {
    private(set) var size: CGSize?

    func record(_ size: CGSize) {
        self.size = size
    }
}

extension View {
    func recordingIdealSize(in recorder: IdealSizeRecorder, floor: CGFloat = 0) -> some View {
        frame(minWidth: floor, minHeight: floor, alignment: .topLeading)
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, size in
                        recorder.record(size)
                    }
                }
            }
    }
}

extension HostedView {
    func idealSize(of recorder: IdealSizeRecorder, timeout: Duration = .seconds(30)) async throws -> CGSize {
        try await eventually(timeout: timeout) {
            layout()
            return recorder.size != nil
        }
        try await settle(.milliseconds(50))
        return recorder.size ?? .zero
    }
}
