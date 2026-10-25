import Foundation

/// One admitted operation, persisted before Dart packs pixels. A leftover lease
/// on the next process launch disables GPU work for this app build, including
/// offline launches. Normal interruption is distinct from an unhandled exit.
final class GpuRequestGate {
    enum Failure: Error { case blocked, busy, interrupted }
    private struct Record: Codable {
        var build: String
        var active: String?
        var blocked: Bool
        var reason: String?
    }
    private let url: URL
    private let lock = NSLock()
    private var record: Record
    private var foreground: Bool
    private var interrupted = false

    init(url: URL, build: String, foreground: Bool) throws {
        self.url = url
        self.foreground = foreground
        if FileManager.default.fileExists(atPath: url.path) {
            let previous = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
            record = previous.build == build
                ? Record(build: build, active: nil, blocked: previous.blocked || previous.active != nil,
                    reason: previous.reason ?? (previous.active != nil ? "unfinished_lease" : (previous.blocked ? "unknown" : nil)))
                : Record(build: build, active: nil, blocked: false)
        } else {
            record = Record(build: build, active: nil, blocked: false)
        }
        try persist()
    }

    private func persist() throws {
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var fileURL = url
        try? fileURL.setResourceValues(values)
    }

    func begin() throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard foreground else { throw Failure.interrupted }
        guard !record.blocked else { throw Failure.blocked }
        guard record.active == nil else { throw Failure.busy }
        let lease = UUID().uuidString
        record.active = lease
        interrupted = false
        do { try persist() }
        catch { record.blocked = true; throw error }
        return lease
    }

    func check(_ lease: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard foreground && !interrupted else { throw Failure.interrupted }
        guard !record.blocked && record.active == lease else { throw Failure.blocked }
    }

    func finish(_ lease: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard record.active == lease else { return }
        record.active = nil
        do { try persist() }
        catch { record.blocked = true; throw error }
    }

    var blockedReason: String? {
        lock.lock(); defer { lock.unlock() }
        return record.reason
    }

    func disable(reason: String = "unknown") throws {
        lock.lock(); defer { lock.unlock() }
        if !record.blocked { record.reason = reason }
        record.blocked = true
        try persist()
    }

    func setForeground(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        foreground = value
        if !value && record.active != nil { interrupted = true }
    }
}

/// Cap occupancy at 256 while honoring even a smaller per-pipeline limit.
enum GpuDispatchShape {
    static func make(executionWidth: Int, maxThreads: Int, twoDimensional: Bool) -> (Int, Int) {
        let budget = max(1, min(256, maxThreads))
        let width = twoDimensional ? max(1, min(executionWidth, budget)) : budget
        return (width, twoDimensional ? max(1, budget / width) : 1)
    }
}
