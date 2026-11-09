import Darwin

nonisolated enum ProcessTree {
    nonisolated struct System: Sendable {
        var children: @Sendable (pid_t) -> [pid_t]
        var processGroup: @Sendable (pid_t) -> pid_t
        var deliver: @Sendable (pid_t, Int32) -> Int32
        var deliverToGroup: @Sendable (pid_t, Int32) -> Int32

        static let live = System(
            children: ProcessTree.children(of:),
            processGroup: getpgid,
            deliver: kill,
            deliverToGroup: killpg
        )
    }

    static let maxRounds = 4

    static func children(of parent: pid_t) -> [pid_t] {
        guard parent > 0 else { return [] }
        let type = UInt32(PROC_PPID_ONLY)
        let info = UInt32(parent)
        let requiredBytes = max(Int(proc_listpids(type, info, nil, 0)), 0)
        var buffer = [pid_t](repeating: 0, count: requiredBytes / MemoryLayout<pid_t>.size)
        let capacityBytes = Int32(buffer.count * MemoryLayout<pid_t>.size)
        _ = buffer.withUnsafeMutableBytes { raw in
            proc_listpids(type, info, raw.baseAddress, capacityBytes)
        }
        return buffer.prefix { $0 > 0 }.map { $0 }
    }

    static func descendants(of root: pid_t, children: (pid_t) -> [pid_t] = ProcessTree.children(of:)) -> [pid_t] {
        var found: [pid_t] = []
        var seen: Set<pid_t> = [root]
        var queue = [root]
        var index = 0
        while index < queue.count {
            for child in children(queue[index]) where seen.insert(child).inserted {
                found.append(child)
                queue.append(child)
            }
            index += 1
        }
        return found
    }

    static func send(_ signal: Int32, to root: pid_t, using system: System = .live) {
        guard root > 0 else { return }
        var delivered: Set<pid_t> = []
        var batch = [root] + descendants(of: root, children: system.children)
        var group: pid_t? = system.processGroup(root) == root ? root : nil
        var round = 0
        while !batch.isEmpty, round < maxRounds {
            round += 1
            let ordered = signal == SIGCONT ? Array(batch.reversed()) : batch
            for pid in ordered {
                if pid == group {
                    _ = system.deliverToGroup(pid, signal)
                } else if group == nil || system.processGroup(pid) != group {
                    _ = system.deliver(pid, signal)
                }
            }
            delivered.formUnion(batch)
            group = nil
            batch = descendants(of: root, children: system.children).filter { !delivered.contains($0) }
        }
    }
}
