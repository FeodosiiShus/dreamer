import Foundation

extension Pipe {
    static func closingOnExec() -> Pipe {
        let pipe = Pipe()
        for descriptor in [pipe.fileHandleForReading.fileDescriptor, pipe.fileHandleForWriting.fileDescriptor] {
            _ = fcntl(descriptor, F_SETFD, fcntl(descriptor, F_GETFD) | FD_CLOEXEC)
        }
        return pipe
    }
}
