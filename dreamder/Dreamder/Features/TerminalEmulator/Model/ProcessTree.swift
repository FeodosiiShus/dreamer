import Darwin

nonisolated enum ProcessTree {
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

    static func descendants(of root: pid_t) -> [pid_t] {
        var found: [pid_t] = []
        var seen: Set<pid_t> = [root]
        var queue = [root]
        var index = 0
        while index < queue.count {
            for child in children(of: queue[index]) where seen.insert(child).inserted {
                found.append(child)
                queue.append(child)
            }
            index += 1
        }
        return found
    }

    static func send(_ signal: Int32, to root: pid_t) {
        guard root > 0 else { return }
        let tree = [root] + descendants(of: root)
        let ordered = signal == SIGCONT ? Array(tree.reversed()) : tree
        for pid in ordered {
            kill(pid, signal)
        }
        if getpgid(root) == root {
            killpg(root, signal)
        }
    }
}
