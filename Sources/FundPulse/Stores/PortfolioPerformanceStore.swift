import Foundation
import Observation

enum PortfolioPerformanceStoreError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case unreadablePersistedData(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "收益历史来自更高版本（v\(version)），为避免丢失数据，当前版本不会覆盖它"
        case .unreadablePersistedData(let reason):
            "收益历史暂时无法读取，为避免丢失数据，当前版本不会覆盖它：\(reason)"
        }
    }
}

@Observable
@MainActor
final class PortfolioPerformanceStore {
    private(set) var snapshot: PortfolioPerformanceSnapshot = .empty
    private(set) var dataDirectory: URL
    private(set) var lastError: String?
    private(set) var hasUnreadablePersistedData = false

    init(dataDirectory: URL = AppDataPaths.sharedDataDirectory) {
        self.dataDirectory = dataDirectory
        load()
    }

    var dataFileURL: URL {
        dataDirectory.appending(path: "portfolio-performance.json")
    }

    func load() {
        do {
            guard FileManager.default.fileExists(atPath: dataFileURL.path) else {
                snapshot = .empty
                lastError = nil
                hasUnreadablePersistedData = false
                return
            }

            let data = try Data(contentsOf: dataFileURL)
            guard !data.isEmpty else {
                snapshot = .empty
                lastError = nil
                hasUnreadablePersistedData = false
                return
            }

            let decoded = try Self.decoder.decode(
                PortfolioPerformanceSnapshot.self,
                from: data
            )
            guard decoded.schemaVersion <= PortfolioPerformanceSnapshot.currentSchemaVersion else {
                throw PortfolioPerformanceStoreError.unsupportedSchemaVersion(decoded.schemaVersion)
            }
            snapshot = PortfolioPerformanceRecorder.normalized(decoded)
            lastError = nil
            hasUnreadablePersistedData = false
        } catch {
            snapshot = .empty
            lastError = error.localizedDescription
            hasUnreadablePersistedData = true
        }
    }

    @discardableResult
    func record(
        portfolio: PortfolioSnapshot,
        now: Date = .now,
        allQuotesConfirmed: Bool
    ) -> Bool {
        guard let candidate = PortfolioPerformanceRecorder.candidate(
            from: portfolio,
            now: now,
            allQuotesConfirmed: allQuotesConfirmed
        ) else {
            return false
        }
        return record(candidate)
    }

    @discardableResult
    func record(_ candidate: PortfolioPerformanceRecorder.Candidate) -> Bool {
        guard !hasUnreadablePersistedData else { return false }
        let next = PortfolioPerformanceRecorder.recording(candidate, in: snapshot)
        guard next != snapshot else { return false }

        do {
            try persist(next)
            snapshot = next
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func clear() -> Bool {
        do {
            try persist(.empty)
            snapshot = .empty
            lastError = nil
            hasUnreadablePersistedData = false
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func replace(_ replacement: PortfolioPerformanceSnapshot) throws {
        guard replacement.schemaVersion <= PortfolioPerformanceSnapshot.currentSchemaVersion else {
            throw PortfolioPerformanceStoreError.unsupportedSchemaVersion(replacement.schemaVersion)
        }
        let normalized = PortfolioPerformanceRecorder.normalized(replacement)
        try persist(normalized)
        snapshot = normalized
        lastError = nil
        hasUnreadablePersistedData = false
    }

    @discardableResult
    func applyJDFinancePerformanceMerge(
        _ plan: PortfolioPerformanceMergePlan,
        overwriteConflicts: Bool = false
    ) throws -> Bool {
        try ensurePersistedDataIsReadable()
        let next = try PortfolioPerformanceMergePlanner.applying(
            plan,
            to: snapshot,
            overwriteConflicts: overwriteConflicts
        )
        guard next != snapshot else { return false }
        try persist(next)
        snapshot = next
        lastError = nil
        return true
    }

    func importSnapshot(from data: Data) throws {
        let decoded = try Self.decoder.decode(PortfolioPerformanceSnapshot.self, from: data)
        try replace(decoded)
    }

    func importSnapshot(from url: URL) throws {
        try importSnapshot(from: Data(contentsOf: url))
    }

    func exportSnapshot() throws -> Data {
        try ensurePersistedDataIsReadable()
        return try Self.encoder.encode(snapshot)
    }

    func snapshotForExport() throws -> PortfolioPerformanceSnapshot {
        try ensurePersistedDataIsReadable()
        return snapshot
    }

    func exportSnapshot(to url: URL) throws {
        try exportSnapshot().write(to: url, options: .atomic)
    }

    private func persist(_ value: PortfolioPerformanceSnapshot) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: dataFileURL, options: .atomic)
    }

    private func ensurePersistedDataIsReadable() throws {
        guard !hasUnreadablePersistedData else {
            throw PortfolioPerformanceStoreError.unreadablePersistedData(lastError ?? "未知错误")
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
