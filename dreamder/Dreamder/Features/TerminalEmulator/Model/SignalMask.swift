import Darwin

nonisolated enum SignalMask {
    static func withEmptyMask<Value>(_ body: () -> Value) -> Value {
        var empty = sigset_t()
        var saved = sigset_t()
        sigemptyset(&empty)
        pthread_sigmask(SIG_SETMASK, &empty, &saved)
        defer { pthread_sigmask(SIG_SETMASK, &saved, nil) }
        return body()
    }
}
