import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import Dreamder

@MainActor
private final class GridRecordingTerminal: CELocalShellTerminalView {
    private(set) var grids: [[Int]] = []

    override func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        grids.append([newCols, newRows])
        super.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }
}

@MainActor
private final class ManualScheduler {
    private var pending: [@MainActor () -> Void] = []

    var pendingCount: Int {
        pending.count
    }

    func schedule(_ work: @escaping @MainActor () -> Void) {
        pending.append(work)
    }

    func runPending() {
        let batch = pending
        pending = []
        for work in batch {
            work()
        }
    }
}

@MainActor
private struct ContainerHarness {
    static let contentSize = NSSize(width: 640, height: 320)

    let terminal = GridRecordingTerminal(frame: NSRect(origin: .zero, size: Self.contentSize))
    let scheduler = ManualScheduler()
    let container: TerminalContainerView
    let window: NSWindow

    init() {
        container = TerminalContainerView(terminal: terminal, schedule: scheduler.schedule)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        scheduler.runPending()
    }
}

@MainActor
@Suite(.serialized, .uiGate)
struct TerminalContainerViewTests {
    @Test
    func theTerminalSitsInsideTheContainerAndKeepsItsSizeWhileNothingChanges() {
        let harness = ContainerHarness()

        #expect(harness.terminal.superview === harness.container)
        #expect(harness.terminal.autoresizingMask.isEmpty)
        #expect(harness.terminal.frame.size == ContainerHarness.contentSize)
        #expect(harness.terminal.grids.isEmpty)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test
    func rapidContainerResizesResizeTheTerminalGridExactlyOnceWithTheFinalSize() {
        let harness = ContainerHarness()

        harness.container.setFrameSize(NSSize(width: 300, height: 150))
        harness.container.setFrameSize(NSSize(width: 420, height: 210))
        harness.container.setFrameSize(NSSize(width: 360, height: 180))

        #expect(harness.scheduler.pendingCount == 1)
        #expect(harness.terminal.grids.isEmpty)
        #expect(harness.terminal.frame.size == ContainerHarness.contentSize)

        harness.scheduler.runPending()

        #expect(harness.terminal.frame.size == harness.container.bounds.size)
        #expect(harness.terminal.grids.count == 1)
        let grid = harness.terminal.getTerminal()
        #expect(harness.terminal.grids.first == [grid.cols, grid.rows])
    }

    @Test
    func aResizeThatKeepsTheGridDoesNotResizeTheTerminalGridAgain() {
        let harness = ContainerHarness()
        harness.container.setFrameSize(NSSize(width: 360, height: 180))
        harness.scheduler.runPending()
        #expect(harness.terminal.grids.count == 1)

        harness.container.setFrameSize(NSSize(width: 360.001, height: 180.001))
        harness.scheduler.runPending()

        #expect(harness.terminal.grids.count == 1)
        #expect(harness.terminal.frame.size == harness.container.bounds.size)
    }

    @Test
    func anUnchangedContainerSizeNeverTouchesTheTerminal() {
        let harness = ContainerHarness()
        harness.container.setFrameSize(NSSize(width: 360, height: 180))
        harness.scheduler.runPending()
        let appliedFrame = harness.terminal.frame

        harness.container.setFrameSize(harness.container.frame.size)
        harness.scheduler.runPending()

        #expect(harness.terminal.frame == appliedFrame)
        #expect(harness.terminal.grids.count == 1)
    }

    @Test
    func zeroSizesNeverReachTheTerminal() {
        let harness = ContainerHarness()

        harness.container.setFrameSize(.zero)
        harness.scheduler.runPending()
        harness.container.setFrameSize(NSSize(width: 0, height: 200))
        harness.scheduler.runPending()
        harness.container.setFrameSize(NSSize(width: 200, height: 0))
        harness.scheduler.runPending()

        #expect(harness.terminal.frame.size == ContainerHarness.contentSize)
        #expect(harness.terminal.grids.isEmpty)
    }

    @Test
    func aContainerOutsideAWindowLeavesTheTerminalAloneUntilItIsAttached() {
        let harness = ContainerHarness()
        harness.window.contentView = nil
        harness.scheduler.runPending()

        harness.container.setFrameSize(NSSize(width: 360, height: 180))
        harness.scheduler.runPending()
        #expect(harness.terminal.frame.size == ContainerHarness.contentSize)
        #expect(harness.terminal.grids.isEmpty)

        harness.window.contentView = harness.container
        harness.container.setFrameSize(NSSize(width: 360, height: 180))
        #expect(harness.scheduler.pendingCount == 1)
        harness.scheduler.runPending()

        #expect(harness.terminal.frame.size == harness.container.bounds.size)
        #expect(harness.terminal.grids.count == 1)
    }

    @Test
    func assigningTheFrameSchedulesTheTerminalLayoutToo() {
        let harness = ContainerHarness()

        harness.container.frame = NSRect(x: 0, y: 0, width: 500, height: 260)

        #expect(harness.scheduler.pendingCount == 1)
        harness.scheduler.runPending()
        #expect(harness.terminal.frame.size == harness.container.bounds.size)
        #expect(harness.container.frame == NSRect(x: 0, y: 0, width: 500, height: 260))
    }

    @Test
    func aTerminalThatMovedToAnotherContainerIsNotResizedByTheOldOne() {
        let harness = ContainerHarness()
        let otherScheduler = ManualScheduler()
        let other = TerminalContainerView(terminal: harness.terminal, schedule: otherScheduler.schedule)
        harness.container.setFrameSize(NSSize(width: 360, height: 180))

        harness.scheduler.runPending()

        #expect(harness.terminal.superview === other)
        #expect(harness.terminal.frame.size == ContainerHarness.contentSize)
        #expect(harness.terminal.grids.isEmpty)
    }

    @Test
    func theDefaultSchedulerAppliesTheLayoutOnTheNextRunLoopTurn() async throws {
        let terminal = GridRecordingTerminal(frame: NSRect(origin: .zero, size: ContainerHarness.contentSize))
        let container = TerminalContainerView(terminal: terminal)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: ContainerHarness.contentSize),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container

        container.setFrameSize(NSSize(width: 360, height: 180))
        container.setFrameSize(NSSize(width: 380, height: 190))

        try await eventually { terminal.frame.size == container.bounds.size }
        #expect(terminal.grids.count == 1)
    }

    @Test
    func theContainerIsInvisibleToAccessibilityAndCannotBeDecoded() throws {
        let harness = ContainerHarness()
        #expect(!harness.container.isAccessibilityElement())
        #expect(harness.terminal.isAccessibilityElement())

        let archive = try NSKeyedArchiver.archivedData(
            withRootObject: NSView(frame: .zero),
            requiringSecureCoding: false
        )
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archive)
        unarchiver.requiresSecureCoding = false
        #expect(TerminalContainerView(coder: unarchiver) == nil)
        unarchiver.finishDecoding()
    }
}
