import Foundation

@main enum GateCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: "build/gpu-safety/test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("gate.json")
        func rejected(_ expected: GpuRequestGate.Failure, _ action: () throws -> Void) {
            do { try action(); preconditionFailure("Expected rejection: \(expected)") }
            catch let error as GpuRequestGate.Failure { precondition(String(describing: error) == String(describing: expected)) }
            catch { preconditionFailure("Unexpected error: \(error)") }
        }
        let first = try GpuRequestGate(url: file, build: "1", foreground: true)
        let lease = try first.begin()
        rejected(.busy) { _ = try first.begin() }
        first.setForeground(false)
        rejected(.interrupted) { try first.check(lease) }
        first.setForeground(true)
        rejected(.interrupted) { try first.check(lease) }
        try first.finish(lease)
        let next = try first.begin()
        try first.finish(lease) // A late reply cannot release a newer lease.
        rejected(.busy) { _ = try first.begin() }
        try first.finish(next)
        let normalRelaunch = try GpuRequestGate(url: file, build: "1", foreground: true)
        let completed = try normalRelaunch.begin()
        try normalRelaunch.finish(completed)
        _ = try normalRelaunch.begin() // Simulate process death before finish.
        let afterCrash = try GpuRequestGate(url: file, build: "1", foreground: true)
        rejected(.blocked) { _ = try afterCrash.begin() }
        let stillBlocked = try GpuRequestGate(url: file, build: "1", foreground: true)
        rejected(.blocked) { _ = try stillBlocked.begin() }
        let updated = try GpuRequestGate(url: file, build: "2", foreground: true)
        let updateLease = try updated.begin()
        try updated.disable() // A timeout stays quarantined even after a late end.
        try updated.finish(updateLease)
        rejected(.blocked) { _ = try updated.begin() }
        let unreadable = root.appendingPathComponent("bad.json")
        try Data("broken".utf8).write(to: unreadable)
        do {
            _ = try GpuRequestGate(url: unreadable, build: "1", foreground: true)
            preconditionFailure("Corrupt state must fail closed")
        } catch DecodingError.dataCorrupted { }
        for limit in [1, 8, 32, 64, 128, 192, 256, 832, 1024] {
            for executionWidth in [8, 32, 64] {
                for twoD in [false, true] {
                    let (w, h) = GpuDispatchShape.make(executionWidth: executionWidth,
                        maxThreads: limit, twoDimensional: twoD)
                    precondition(w > 0 && h > 0 && w * h <= limit)
                }
            }
        }
        print("GPU_GATE_CHECK passed: crash persistence, build reset, foreground interruption, busy admission, stale replies, timeout quarantine, corrupt state, dispatch limits")
    }
}
