import Foundation
import Testing
@testable import Dreamder

@Suite
struct DirectoryEventStreamRescanFlagTests {
    private func events(_ flags: Int) -> Set<FSEvent> {
        DirectoryEventStream.events(fromFlags: FSEventStreamEventFlags(flags))
    }

    @Test
    func everyFlagThatDemandsARescanMapsToTheRescanEvent() {
        #expect(events(Int(kFSEventStreamEventFlagMustScanSubDirs)) == [.mustRescan])
        #expect(events(Int(kFSEventStreamEventFlagUserDropped)) == [.mustRescan])
        #expect(events(Int(kFSEventStreamEventFlagKernelDropped)) == [.mustRescan])
        #expect(events(Int(kFSEventStreamEventFlagRootChanged)) == [.mustRescan])
    }

    @Test
    func theKernelAndUserDropFlagsUsuallyArriveTogetherWithMustScanSubDirsAndYieldOneRescan() {
        let combined = kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped

        #expect(events(Int(combined)) == [.mustRescan])
    }

    @Test
    func aRescanFlagKeepsTheItemEventsOfTheSameFlagWord() {
        let combined = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagItemCreated

        #expect(events(Int(combined)) == [.mustRescan, .itemCreated])
    }

    @Test
    func flagsThatNeedNoRescanNeverProduceTheRescanEvent() {
        let harmless = kFSEventStreamEventFlagItemIsFile
            | kFSEventStreamEventFlagItemIsDir
            | kFSEventStreamEventFlagMount
            | kFSEventStreamEventFlagUnmount
            | kFSEventStreamEventFlagEventIdsWrapped
            | kFSEventStreamEventFlagHistoryDone

        #expect(events(Int(harmless)).isEmpty)
        #expect(events(Int(kFSEventStreamEventFlagItemModified)) == [.itemModified])
    }

    @Test
    func aDroppedEventsPayloadReachesTheConsumersAsARescanOfItsPath() {
        let pathKey = kFSEventStreamEventExtendedDataPathKey as String
        let payload = NSArray(array: [
            NSDictionary(dictionary: [pathKey: "/root"]),
            NSDictionary(dictionary: [pathKey: "/root/sub/file.txt"])
        ])
        let flags: [FSEventStreamEventFlags] = [
            FSEventStreamEventFlags(Int(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagKernelDropped)),
            FSEventStreamEventFlags(Int(kFSEventStreamEventFlagItemModified))
        ]

        let result = DirectoryEventStream.events(fromPayload: payload, flags: flags)

        #expect(result.map(\.path) == ["/root", "/root/sub/file.txt"])
        #expect(result.map(\.eventType) == [.mustRescan, .itemModified])
    }
}
