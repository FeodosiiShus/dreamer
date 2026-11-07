import Foundation

nonisolated extension Pipe {
    static func closingOnExec() -> Pipe {
        let pipe = Pipe()
        for descriptor in [pipe.fileHandleForReading.fileDescriptor, pipe.fileHandleForWriting.fileDescriptor] {
            let flags = fcntl(descriptor, F_GETFD)
            if flags >= 0 {
                _ = fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC)
            }
        }
        return pipe
    }
}
