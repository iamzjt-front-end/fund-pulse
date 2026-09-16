import Foundation

/// Session-scoped, bounded cache. Failed lookups are never cached. Entries are
/// keyed by the exact fund/date; in-flight callers share the same network work.
actor FundDataCache<Value: Sendable> {
    private struct Entry { let value: Value; let expires: Date; let created: Date }
    private var entries: [String: Entry] = [:]
    private var pending: [String: Task<Value?, Never>] = [:]
    private let capacity: Int

    init(capacity: Int = 128) { self.capacity = max(capacity, 1) }

    func value(key: String, now: Date = .now, ttl: TimeInterval,
               shouldCache: @escaping @Sendable (Value) -> Bool = { _ in true },
               load: @escaping @Sendable () async -> Value?) async -> Value? {
        if let cached = entries[key], cached.expires > now { return cached.value }
        if let task = pending[key] { return await task.value }
        let task = Task { await load() }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        entries = entries.filter { $0.value.expires > now }
        if let result, shouldCache(result) {
            if entries.count >= capacity, let oldest = entries.min(by: { $0.value.created < $1.value.created })?.key {
                entries[oldest] = nil
            }
            entries[key] = Entry(value: result, expires: now.addingTimeInterval(ttl), created: now)
        }
        return result
    }
}
