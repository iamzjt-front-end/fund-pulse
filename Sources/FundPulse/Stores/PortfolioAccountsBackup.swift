import Foundation

struct PortfolioAccountsBackup: Codable, Equatable {
    var schemaVersion = 1
    var createdAt: Date
    var registry: PortfolioAccountsRegistry
    var portfolios: [String: PortfolioSnapshot]
}

extension PortfolioAccountsStore {
    private var restoreJournalURL: URL { dataDirectory.appending(path: "pending-accounts-restore.json") }
    private var backupDirectory: URL { dataDirectory.appending(path: "Backups", directoryHint: .isDirectory) }

    var latestBackupURL: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("all-accounts-") && $0.pathExtension == "json" }
            .max { lhs, rhs in
                let a = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let b = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (a ?? .distantPast) < (b ?? .distantPast)
            }
    }

    func backupSnapshot() throws -> PortfolioAccountsBackup {
        try ensureRegistryIsWritable()
        var portfolios: [String: PortfolioSnapshot] = [:]
        for account in accounts {
            guard let store = store(for: account.id) else { throw PortfolioAccountsStoreError.accountNotFound }
            portfolios[account.id] = try store.backupSnapshot()
        }
        return PortfolioAccountsBackup(createdAt: .now, registry: makeRegistry(), portfolios: portfolios)
    }

    func exportBackup(to url: URL) throws {
        try Self.encoder.encode(backupSnapshot()).write(to: url, options: .atomic)
    }

    func previewBackup(from url: URL) throws -> PortfolioAccountsBackup {
        let backup = try Self.decoder.decode(PortfolioAccountsBackup.self, from: Data(contentsOf: url))
        try validateBackup(backup)
        return backup
    }

    func restoreBackup(_ backup: PortfolioAccountsBackup) throws {
        try ensureRegistryIsWritable()
        guard !isRefreshing, !accounts.contains(where: { store(for: $0.id)?.isRefreshingQuotes == true }) else {
            throw PortfolioAccountsStoreError.accountIsRefreshing
        }
        guard !FileManager.default.fileExists(atPath: restoreJournalURL.path) else {
            throw PortfolioStoreError.importRecoveryRequired
        }
        try validateBackup(backup)
        for account in backup.registry.accounts {
            let journal = dataDirectory(for: account).appending(path: "pending-import-rollback.json")
            guard !FileManager.default.fileExists(atPath: journal.path) else {
                throw PortfolioStoreError.importRecoveryRequired
            }
        }
        let previous = try backupSnapshot()
        let data = try Self.encoder.encode(previous)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try data.write(to: backupDirectory.appending(path: "all-accounts-\(UUID().uuidString).json"), options: .atomic)
        try data.write(to: restoreJournalURL, options: .atomic)
        do {
            try writeBackup(backup)
            try FileManager.default.removeItem(at: restoreJournalURL)
            apply(backup.registry)
        } catch {
            let originalError = error
            // Retain the journal if rollback fails; load() resumes recovery before
            // exposing any account. Normal registry writes are blocked meanwhile.
            try? recoverInterruptedAccountsRestore()
            throw originalError
        }
    }

    func recoverInterruptedAccountsRestore() throws {
        guard FileManager.default.fileExists(atPath: restoreJournalURL.path) else { return }
        let previous = try Self.decoder.decode(PortfolioAccountsBackup.self, from: Data(contentsOf: restoreJournalURL))
        try validateBackup(previous)
        try writeBackup(previous)
        try FileManager.default.removeItem(at: restoreJournalURL)
    }

    private func validateBackup(_ backup: PortfolioAccountsBackup) throws {
        guard backup.schemaVersion == 1 else {
            throw PortfolioAccountsStoreError.unsupportedSchemaVersion(backup.schemaVersion)
        }
        try validate(backup.registry)
        let identifiers = Set(backup.registry.accounts.map(\.id))
        guard backup.registry.selectedAccountID.map({ identifiers.contains($0) }) ?? true,
              backup.registry.lastSelectedAccountID.map({ identifiers.contains($0) }) ?? true else {
            throw PortfolioAccountsStoreError.invalidRegistry("备份选择了不存在的账户")
        }
        guard Set(backup.portfolios.keys) == Set(backup.registry.accounts.map(\.id)) else {
            throw PortfolioAccountsStoreError.invalidRegistry("备份的账户和持仓不匹配")
        }
        for account in backup.registry.accounts {
            guard let portfolio = backup.portfolios[account.id] else { throw PortfolioAccountsStoreError.accountNotFound }
            try PortfolioValidation.validate(portfolio, accountKind: account.kind)
        }
    }

    private func writeBackup(_ backup: PortfolioAccountsBackup) throws {
        for account in backup.registry.accounts {
            guard var portfolio = backup.portfolios[account.id] else { throw PortfolioAccountsStoreError.accountNotFound }
            let directory = dataDirectory(for: account)
            let history = portfolio.portfolioPerformanceHistory ?? .empty
            portfolio.portfolioPerformanceHistory = nil
            portfolio.schemaVersion = nil
            portfolio.accountKind = nil
            try JSONPortfolioRepository(dataDirectory: directory).save(portfolio)
            try PortfolioPerformanceStore(dataDirectory: directory).replace(history)
        }
        try persist(backup.registry)
    }
}
