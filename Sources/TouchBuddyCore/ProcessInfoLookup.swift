import Darwin
import Foundation

private struct ProcessEntry {
    let parentPID: Int32
    let name: String
}

private func processEntry(pid: Int32) -> ProcessEntry? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let name = withUnsafePointer(to: &info.kp_proc.p_comm) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
    }
    return ProcessEntry(parentPID: info.kp_eproc.e_ppid, name: name)
}

private let maxAncestorDepth = 16

/// `pid` is the hook's parent (main passes getppid()). Walks up looking for claude/node;
/// if none is found, falls back to the hook's grandparent, i.e. the parent of `pid`.
public func findClaudeAncestorPID(startingAt pid: Int32) -> Int32? {
    var current = pid
    var visited = 0
    while current > 1, visited < maxAncestorDepth {
        guard let entry = processEntry(pid: current) else { break }
        if entry.name == "claude" || entry.name == "node" {
            return current
        }
        current = entry.parentPID
        visited += 1
    }
    return hookGrandparent(hookParent: pid)
}

private func hookGrandparent(hookParent pid: Int32) -> Int32? {
    guard let grandparent = processEntry(pid: pid)?.parentPID, grandparent > 1 else { return nil }
    return grandparent
}

public func isProcessAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    return kill(pid, 0) == 0 || errno == EPERM
}
