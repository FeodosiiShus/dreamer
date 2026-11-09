import AppKit
import CodeEditTextView
import Foundation
import Testing
@testable import Dreamder

extension DreamderAutomationTests {
    @Test
    func snapshotUsesTheWindowServerImageWhenOneIsAvailable() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            harness.bringToFront()
            let provided = try makeImage(width: 64, height: 32)
            var requested: [NSWindow] = []
            let output = directory.appending(path: "provided-shots")

            DreamderAutomation.snapshot(
                to: output.path(percentEncoded: false),
                windowImage: { window in
                    requested.append(window)
                    return provided
                }
            )

            #expect(requested.contains { $0 === window })
            let manifest = try outputLines("windows.txt", in: output)
            let manifestIndex = try #require(manifest.indices.dropFirst().first {
                manifest[$0].hasPrefix("\(window.windowNumber) ")
            })
            let picture = try Data(contentsOf: output.appending(path: "window-\(manifestIndex - 1).png"))
            let representation = try #require(NSBitmapImageRep(data: picture))
            #expect(representation.pixelsWide == 64)
        }
    }

    @Test
    func snapshotWithoutADirectoryWritesIntoTheTemporaryDirectory() throws {
        removeTemporaryFile("windows.txt")
        defer {
            removeTemporaryFile("windows.txt")
            let names = (try? FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path())) ?? []
            for name in names where name.hasPrefix("window-") && name.hasSuffix(".png") {
                removeTemporaryFile(name)
            }
        }

        DreamderAutomation.snapshot(to: nil, windowImage: { _ in nil })

        #expect(try outputLines("windows.txt", in: temporaryDirectory).first?.hasPrefix("capture=") == true)
    }

    @Test
    func snapshotRendersTheContentViewWhenNoWindowServerImageExists() throws {
        try withTempDir { directory in
            let harness = try makeHarness(in: directory)
            defer { harness.close() }
            let window = try #require(harness.controller.window)
            harness.bringToFront()
            let output = directory.appending(path: "in-process-shots")

            DreamderAutomation.snapshot(to: output.path(percentEncoded: false), windowImage: { _ in nil })

            let index = try snapshotIndex(of: window, in: outputLines("windows.txt", in: output))
            let picture = try Data(contentsOf: output.appending(path: "window-\(index).png"))
            #expect(NSBitmapImageRep(data: picture) != nil)
        }
    }

    @Test
    func snapshotSkipsWindowsThatCannotBeRendered() throws {
        try withTempDir { directory in
            let window = makeProbeWindow()
            defer {
                window.hidesContentView = false
                window.close()
            }
            window.orderFront(nil)
            window.hidesContentView = true
            let output = directory.appending(path: "unrenderable-shots")

            DreamderAutomation.snapshot(to: output.path(percentEncoded: false), windowImage: { _ in nil })

            let index = try snapshotIndex(of: window, in: outputLines("windows.txt", in: output))
            #expect(pictureExists("window-\(index).png", in: output) == false)
        }
    }

    @Test
    func snapshotTreatsAWindowWithoutAChildWindowListAsChildless() throws {
        try withTempDir { directory in
            let window = makeProbeWindow()
            defer { window.close() }
            window.orderFront(nil)
            window.reportsNoChildren = true
            let provided = try makeImage(width: 64, height: 32)
            let output = directory.appending(path: "childless-shots")

            DreamderAutomation.snapshot(to: output.path(percentEncoded: false), windowImage: { _ in provided })

            let index = try snapshotIndex(of: window, in: outputLines("windows.txt", in: output))
            #expect(pictureExists("window-\(index).png", in: output))
            #expect(pictureExists("window-\(index)-popup-0.png", in: output) == false)
        }
    }

    @Test
    func snapshotWritesEveryVisibleChildWindowAsAPopupPicture() throws {
        try withTempDir { directory in
            let parent = makeProbeWindow()
            let child = makeProbeWindow(width: 120, style: [.borderless])
            defer {
                child.reportedFrame = nil
                parent.removeChildWindow(child)
                child.close()
                parent.close()
            }
            attachChild(child, to: parent)
            child.reportedFrame = parent.frame
            let provided = try makeImage(width: 64, height: 32)
            let output = directory.appending(path: "popup-shots")

            DreamderAutomation.snapshot(to: output.path(percentEncoded: false), windowImage: { _ in provided })

            let index = try snapshotIndex(of: parent, in: outputLines("windows.txt", in: output))
            #expect(pictureExists("window-\(index).png", in: output))
            let popup = try Data(contentsOf: output.appending(path: "window-\(index)-popup-0.png"))
            #expect(NSBitmapImageRep(data: popup)?.pixelsWide == 64)
        }
    }

    @Test
    func snapshotCompositesOnlyTheChildWindowsThatRender() throws {
        try withTempDir { directory in
            let parent = makeProbeWindow()
            let child = makeProbeWindow(width: 120, style: [.borderless])
            defer {
                child.reportedFrame = nil
                child.hidesContentView = false
                parent.removeChildWindow(child)
                child.close()
                parent.close()
            }
            attachChild(child, to: parent)
            child.reportedFrame = parent.frame
            child.hidesContentView = true
            let provided = try makeImage(width: 64, height: 32)
            let output = directory.appending(path: "partial-shots")

            DreamderAutomation.snapshot(
                to: output.path(percentEncoded: false),
                windowImage: { window in window === parent ? provided : nil }
            )

            let index = try snapshotIndex(of: parent, in: outputLines("windows.txt", in: output))
            #expect(pictureExists("window-\(index).png", in: output))
            #expect(pictureExists("window-\(index)-popup-0.png", in: output) == false)
        }
    }

    @Test
    func snapshotKeepsTheWindowPictureWhenTheCompositeCannotBeAllocated() throws {
        try withTempDir { directory in
            let parent = makeProbeWindow()
            let child = makeProbeWindow(width: 120, style: [.borderless])
            defer {
                child.reportedFrame = nil
                parent.removeChildWindow(child)
                child.close()
                parent.close()
            }
            attachChild(child, to: parent)
            child.reportedFrame = parent.frame
            let provided = try makeImage(width: 64, height: 32)
            let output = directory.appending(path: "no-composite-shots")
            var requestedSizes: [[Int]] = []

            DreamderAutomation.snapshot(
                to: output.path(percentEncoded: false),
                windowImage: { _ in provided },
                makeContext: { width, height in
                    requestedSizes.append([width, height])
                    return nil
                }
            )

            let index = try snapshotIndex(of: parent, in: outputLines("windows.txt", in: output))
            let picture = try Data(contentsOf: output.appending(path: "window-\(index).png"))
            let representation = try #require(NSBitmapImageRep(data: picture))
            #expect(representation.pixelsWide == 64)
            #expect(representation.pixelsHigh == 32)
            #expect(requestedSizes.contains { $0.allSatisfy { $0 > 0 } })
        }
    }
}
