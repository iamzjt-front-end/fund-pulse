import Foundation

extension PortfolioStore {
    func load() {
        loadState = .loading

        do {
            try ensureAccountsRestoreCompleted()
            try recoverInterruptedImport()
            performanceStore.load()
            if let loadedSnapshot = try repository.load() {
                try PortfolioValidation.validate(loadedSnapshot, accountKind: accountKind)
                snapshot = loadedSnapshot
                persistedSnapshot = loadedSnapshot
                loadState = .loaded
                return
            }

            snapshot = .empty
            persistedSnapshot = nil
            loadState = .missingPlainData(hasLegacyStore: AppDataPaths.hasLegacyStore(in: dataDirectory))
        } catch {
            snapshot = .empty
            persistedSnapshot = nil
            loadState = .failed(error.localizedDescription)
        }
    }

    func exportPortfolio(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let backup = try backupSnapshot()
        let data = try encoder.encode(backup)
        try data.write(to: url, options: .atomic)
    }

    func backupSnapshot() throws -> PortfolioSnapshot {
        if case .failed(let reason) = loadState { throw PortfolioStoreError.performanceHistoryWriteFailed(reason) }
        var backup = snapshot
        backup.schemaVersion = PortfolioValidation.schemaVersion
        backup.accountKind = accountKind
        backup.portfolioPerformanceHistory = try performanceStore.snapshotForExport()
        return backup
    }

    func importPortfolio(from url: URL) throws {
        try importPortfolio(previewPortfolioImport(from: url))
    }

    func previewPortfolioImport(from url: URL) throws -> PortfolioSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let importedSnapshot = try decoder.decode(PortfolioSnapshot.self, from: data)
        try PortfolioValidation.validate(importedSnapshot, accountKind: accountKind)
        return importedSnapshot
    }

    func importPortfolio(_ backup: PortfolioSnapshot) throws {
        try PortfolioValidation.validate(backup, accountKind: accountKind)
        guard !FileManager.default.fileExists(atPath: importRollbackURL.path) else {
            throw PortfolioStoreError.importRecoveryRequired
        }
        var importedSnapshot = backup
        importedSnapshot.schemaVersion = nil
        importedSnapshot.accountKind = nil
        let importedPerformance = importedSnapshot.portfolioPerformanceHistory ?? .empty
        importedSnapshot.portfolioPerformanceHistory = nil

        let previousSnapshot = snapshot
        let previousPerformance = try performanceStore.snapshotForExport()
        let rollback = PortfolioImportRollback(portfolio: previousSnapshot, performance: previousPerformance)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        if persistedSnapshot != nil {
            let backups = dataDirectory.appending(path: "Backups", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            try exportPortfolio(to: backups.appending(path: "before-import-\(UUID().uuidString).json"))
        } else if FileManager.default.fileExists(atPath: dataFileURL.path) {
            // Preserve unreadable source bytes before an explicit restore.
            try FileManager.default.copyItem(at: dataFileURL,
                to: dataDirectory.appending(path: "before-import-\(UUID().uuidString).raw"))
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(rollback).write(to: importRollbackURL, options: .atomic)
        isImporting = true
        defer { isImporting = false }
        do {
            try save(importedSnapshot)
            try performanceStore.replace(importedPerformance)
            try FileManager.default.removeItem(at: importRollbackURL)
            snapshot = importedSnapshot
            loadState = .loaded
            quoteRefreshWarning = nil
            lastSuccessfulQuoteRefresh = nil
        } catch {
            let importError = error
            do {
                try save(previousSnapshot)
                try performanceStore.replace(previousPerformance)
                try FileManager.default.removeItem(at: importRollbackURL)
            } catch {
                loadState = .failed("导入回滚尚未完成：\(error.localizedDescription)，请恢复磁盘写入后重新加载")
            }
            snapshot = previousSnapshot
            throw importError
        }
    }

    var importRollbackURL: URL { dataDirectory.appending(path: "pending-import-rollback.json") }

    private func recoverInterruptedImport() throws {
        guard FileManager.default.fileExists(atPath: importRollbackURL.path) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let rollback = try decoder.decode(PortfolioImportRollback.self, from: Data(contentsOf: importRollbackURL))
        try PortfolioValidation.validate(rollback.portfolio, accountKind: accountKind)
        try repository.save(rollback.portfolio)
        try performanceStore.replace(rollback.performance)
        try FileManager.default.removeItem(at: importRollbackURL)
    }

    func ensureAccountsRestoreCompleted() throws {
        let accountsRoot = dataDirectory.deletingLastPathComponent().lastPathComponent == "accounts"
            ? dataDirectory.deletingLastPathComponent().deletingLastPathComponent() : dataDirectory
        guard !FileManager.default.fileExists(atPath: accountsRoot.appending(path: "pending-accounts-restore.json").path) else {
            throw PortfolioStoreError.importRecoveryRequired
        }
    }

    func save(_ snapshot: PortfolioSnapshot) throws {
        do {
            try ensureAccountsRestoreCompleted()
            guard isImporting || !FileManager.default.fileExists(atPath: importRollbackURL.path) else {
                throw PortfolioStoreError.importRecoveryRequired
            }
            try repository.save(snapshot)
            persistedSnapshot = snapshot
        } catch {
            if let persistedSnapshot {
                self.snapshot = persistedSnapshot
            }
            throw error
        }
    }

}
