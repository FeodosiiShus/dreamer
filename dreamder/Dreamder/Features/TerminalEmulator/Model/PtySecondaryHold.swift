import Darwin

nonisolated final class PtySecondaryHold: Sendable {
    typealias Opener = @Sendable (UnsafePointer<CChar>, Int32) -> Int32

    let descriptor: Int32

    init?(primary: Int32, opener: Opener = PtySecondaryHold.openDescriptor) {
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard ptsname_r(primary, &path, path.count) == 0 else { return nil }
        let descriptor = opener(path, O_RDWR | O_NOCTTY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    static func openDescriptor(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
        open(path, flags)
    }
}
