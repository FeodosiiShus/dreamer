//
//  DirectoryEventStream.swift
//  Dreamder
//
//  Created by Khan Winter on 6/26/23.
//

import Foundation
import Synchronization

nonisolated enum FSEvent: String, Sendable {
    case changeInDirectory
    case rootChanged
    case itemChangedOwner
    case itemCreated
    case itemCloned
    case itemModified
    case itemRemoved
    case itemRenamed
}

/// Creates a stream of events using the File System Events API.
///
/// The stream of events is started immediately upon initialization, and will only be stopped when either `cancel`
/// is called, or the object is deallocated. The stream is also configured to debounce notifications to happen
/// according to the `debounceDuration` parameter. This directly corresponds with the `latency` parameter in
/// `FSEventStreamCreate`, which will delay notifications until `latency` has passed at which point it will send all
/// the notifications built up during that period of time.
///
/// Use the `callback` parameter to listen for notifications.
/// Notifications are automatically filtered to include certain events, but the FS event API doesn't always correctly
/// flag events so use caution when handling events as they can come frequently.
///
/// The `callback` function will be called with all events that happened since the last event notification,
/// effectively batching all notifications every `debounceDuration`. This callback may not be called on a
/// predictable dispatch queue.
nonisolated final class DirectoryEventStream: Sendable {
    typealias EventCallback = @Sendable ([Event]) -> Void

    private let streamRef: Mutex<FSEventStreamRef?>
    private let callback: EventCallback
    private let debounceDuration: TimeInterval
    let exclusionPaths: [String]

    struct Event: Sendable {
        let path: String
        let eventType: FSEvent
    }

    /// Initialize the event stream and begin listening for events.
    /// - Parameters:
    ///   - directory: The directory to monitor. The listener may receive a ``FSEvent/rootChanged`` event if this
    ///   directory is modified or moved.
    ///   - debounceDuration: The duration to delay notifications for to let the FS events API accumulates events.
    ///                       defaults to 0.1s.
    ///   - callback: A callback provided that the ``DirectoryEventStream`` will send events to. See
    ///               ``DirectoryEventStream``'s documentation for detailed information.
    init(
        directory: String,
        exclusionPaths: [String] = [],
        debounceDuration: TimeInterval = 0.1,
        callback: @escaping EventCallback
    ) {
        self.debounceDuration = debounceDuration
        self.exclusionPaths = exclusionPaths
        self.callback = callback
        self.streamRef = Mutex(nil)
        streamRef.withLock { stream in
            stream = Self.makeStream(
                owner: self,
                directories: [directory],
                exclusionPaths: exclusionPaths,
                debounceDuration: debounceDuration
            )
        }
    }

    static func makeStream(
        owner: DirectoryEventStream,
        directories: [String],
        exclusionPaths: [String],
        debounceDuration: TimeInterval
    ) -> sending FSEventStreamRef? {
        let box = DirectoryEventStreamOwner(owner)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                return UnsafeRawPointer(Unmanaged<DirectoryEventStreamOwner>.fromOpaque(info).retain().toOpaque())
            },
            release: { info in
                guard let info else { return }
                Unmanaged<DirectoryEventStreamOwner>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let contextPtr = withUnsafeMutablePointer(to: &context) { ptr in UnsafeMutablePointer(ptr) }

        let pathsToWatch = directories as CFArray

        guard let ref = withExtendedLifetime(box, { FSEventStreamCreate(
            kCFAllocatorDefault,
            // swiflint:ignore:next opening_brace
            { streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
                guard let clientCallBackInfo,
                      let stream = Unmanaged<DirectoryEventStreamOwner>
                        .fromOpaque(clientCallBackInfo)
                        .takeUnretainedValue()
                        .stream else { return }
                stream.eventStreamHandler(streamRef, numEvents, eventPaths, eventFlags, eventIds)
            },
            contextPtr,
            pathsToWatch,
            UInt64(kFSEventStreamEventIdSinceNow),
            debounceDuration,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                // This will listen for file changes
                | kFSEventStreamCreateFlagFileEvents
                // This provides additional information, like fileId,
                // it is useful when file renamed, because it's firing to separate events with old and new path,
                // but they can be linked by file id
                | kFSEventStreamCreateFlagUseExtendedData
                // Useful for us, always sends after the debounce duration.
                | kFSEventStreamCreateFlagNoDefer
            )
        ) }) else {
            return nil
        }
        if !exclusionPaths.isEmpty {
            _ = FSEventStreamSetExclusionPaths(ref, exclusionPaths as CFArray)
        }
        FSEventStreamSetDispatchQueue(ref, DispatchQueue(label: "dev.dreamder.DirectoryEventStream", qos: .utility))
        FSEventStreamStart(ref)
        return ref
    }

    deinit {
        cancel()
    }

    /// Cancels the events watcher.
    /// This class will have to be re-initialized to begin streaming events again.
    public func cancel() {
        streamRef.withLock { ref in
            if let current = ref {
                FSEventStreamStop(current)
                FSEventStreamInvalidate(current)
                FSEventStreamRelease(current)
            }
            ref = nil
        }
    }

    var isRunning: Bool {
        streamRef.withLock { $0 != nil }
    }

    /// Handler for the fs event stream.
    private func eventStreamHandler(
        _ streamRef: ConstFSEventStreamRef,
        _ numEvents: Int,
        _ eventPaths: UnsafeMutableRawPointer,
        _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
        _ eventIds: UnsafePointer<FSEventStreamEventId>
    ) {
        let events = Self.events(
            fromPayload: unsafeBitCast(eventPaths, to: NSArray.self),
            flags: UnsafeBufferPointer(start: eventFlags, count: numEvents)
        )
        if !events.isEmpty {
            callback(events)
        }
    }

    static func events(fromPayload payload: NSArray, flags: some Sequence<FSEventStreamEventFlags>) -> [Event] {
        guard let eventDictionaries = payload as? [NSDictionary] else {
            return []
        }

        var events: [Event] = []

        for (dictionary, flag) in zip(eventDictionaries, flags) {
            guard let path = dictionary[kFSEventStreamEventExtendedDataPathKey] as? String else {
                continue
            }

            for event in Self.events(fromFlags: flag) {
                events.append(.init(path: path, eventType: event))
            }
        }

        return events
    }

    /// Parses ``FSEvent`` from the raw flag value.
    ///
    /// There can be multiple events in the raw flag value,
    /// bacause of how OS processes almost simlutaneous actions – thus this functions returns a `Set` of `FSEvent`.
    ///
    /// Often returns ``[FSEvent/changeInDirectory]`` as `FSEventStream` returns
    /// `kFSEventStreamEventFlagNone (0x00000000)` frequently without more information.
    /// - Parameter raw: The int value received from the FSEventStream
    /// - Returns: A `Set` of ``FSEvent``'s if at least one valid was found, or `[]` otherwise.
    static func events(fromFlags raw: FSEventStreamEventFlags) -> Set<FSEvent> {
        var events: Set<FSEvent> = []

        if raw == 0 {
            events.insert(.changeInDirectory)
        }
        if raw & UInt32(kFSEventStreamEventFlagRootChanged) > 0 {
            events.insert(.rootChanged)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemChangeOwner) > 0 {
            events.insert(.itemChangedOwner)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemCreated) > 0 {
            events.insert(.itemCreated)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemCloned) > 0 {
            events.insert(.itemCloned)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemModified) > 0 {
            events.insert(.itemModified)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemRemoved) > 0 {
            events.insert(.itemRemoved)
        }
        if raw & UInt32(kFSEventStreamEventFlagItemRenamed) > 0 {
            events.insert(.itemRenamed)
        }

        return events
    }
}

nonisolated private final class DirectoryEventStreamOwner: Sendable {
    weak let stream: DirectoryEventStream?

    init(_ stream: DirectoryEventStream) {
        self.stream = stream
    }
}
