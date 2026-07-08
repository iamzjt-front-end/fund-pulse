import Foundation
import Observation

@Observable
@MainActor
final class JDFinanceHoldingsSyncStore {
    private(set) var preview: JDFinanceHoldingsSyncPreview?
    private(set) var statusMessage = "未连接"
    private(set) var errorMessage: String?
    private(set) var lastError: JDFinanceHoldingsError?
    private(set) var isSyncing = false
    private(set) var isApplying = false
    private(set) var lastSyncedAt: Date?

    private let service: JDFinanceHoldingsService
    private let nowProvider: () -> Date

    init(
        service: JDFinanceHoldingsService = JDFinanceHoldingsService(),
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.nowProvider = now
    }

    func synchronize(portfolioStore: PortfolioStore, cookieHeader: String?) async {
        isSyncing = true
        errorMessage = nil
        lastError = nil
        statusMessage = "正在同步京东持仓..."
        defer { isSyncing = false }

        do {
            let remoteSnapshot = try await service.fetchSnapshot(
                cookieHeader: cookieHeader,
                needsTradeOrderRecords: portfolioStore.needsJDFinanceTradeOrderReconciliation
            )
            let syncedAt = nowProvider()
            try portfolioStore.applyJDFinanceAccountTotal(remoteSnapshot.totalAssets, syncedAt: syncedAt)
            preview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            if let preview {
                Self.writeDebugPreview(preview, now: syncedAt)
            }
            lastSyncedAt = syncedAt
            statusMessage = preview?.isEmpty == true ? "已同步，暂无差异" : "已生成同步预览"
        } catch let error as JDFinanceHoldingsError {
            preview = nil
            lastError = error
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        } catch {
            preview = nil
            lastError = nil
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        }
    }

    func applyNewHoldings(to portfolioStore: PortfolioStore) async {
        await applySelectedHoldings(
            to: portfolioStore,
            importNew: true,
            updateChanged: false,
            importPending: false,
            reconcileConfirmed: false
        )
    }

    func applySelectedHoldings(
        to portfolioStore: PortfolioStore,
        importNew: Bool,
        updateChanged: Bool,
        importPending: Bool,
        reconcileConfirmed: Bool = false
    ) async {
        guard let preview else { return }

        let candidates = importNew ? preview.newHoldings : []
        let pendingCandidates = importPending ? preview.importablePendingNotices : []
        let reconciliationCandidates = reconcileConfirmed ? preview.overwritableReconciliationNotices : []
        let updates = updateChanged
            ? preview.changedHoldings.map {
                FundAmountPositionSyncUpdate(
                    code: $0.code,
                    amount: $0.jdAmount,
                    holdingIncome: $0.jdHoldingIncome
                )
            }
            : []
        let selectedCount = candidates.count + updates.count + pendingCandidates.count + reconciliationCandidates.count
        guard selectedCount > 0 else {
            statusMessage = "请选择要同步的数据"
            return
        }

        isApplying = true
        errorMessage = nil
        lastError = nil
        statusMessage = "正在同步选中数据..."
        defer { isApplying = false }

        let positionDate = DateOnlyFormatter.string(from: nowProvider())
        do {
            for candidate in candidates {
                try await portfolioStore.upsertFund(candidate.draft(positionDate: positionDate))
            }
            for candidate in pendingCandidates {
                try await applyPendingNoticeDraft(candidate, to: portfolioStore, manualCompletion: nil)
            }
            for candidate in reconciliationCandidates {
                try await portfolioStore.applyJDFinanceReconciliation(candidate)
            }
            try await portfolioStore.applyAmountPositionSyncUpdates(updates)
            self.preview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: preview.remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            statusMessage = "已同步 \(selectedCount) 项数据"
        } catch {
            lastError = nil
            errorMessage = error.localizedDescription
            statusMessage = "同步失败"
        }
    }

    func applyPendingNotice(
        _ notice: JDFinanceHoldingPendingNotice,
        to portfolioStore: PortfolioStore,
        manualCompletion: JDFinancePendingManualCompletion?
    ) async {
        guard let preview else { return }
        guard notice.canBuildLocalDraft(manualCompletion: manualCompletion) else {
            statusMessage = "请先补全交易日期和时段"
            return
        }

        isApplying = true
        errorMessage = nil
        lastError = nil
        statusMessage = "正在同步待确认..."
        defer { isApplying = false }

        do {
            try await applyPendingNoticeDraft(notice, to: portfolioStore, manualCompletion: manualCompletion)
            self.preview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: preview.remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            statusMessage = "已同步待确认"
        } catch {
            lastError = nil
            errorMessage = error.localizedDescription
            statusMessage = "同步失败"
        }
    }

    func markSessionCleared() {
        preview = nil
        errorMessage = nil
        lastError = nil
        statusMessage = "已清除京东登录会话"
        lastSyncedAt = nil
    }

    private func applyPendingNoticeDraft(
        _ notice: JDFinanceHoldingPendingNotice,
        to portfolioStore: PortfolioStore,
        manualCompletion: JDFinancePendingManualCompletion?
    ) async throws {
        if let fundDraft = notice.fundPositionDraft(manualCompletion: manualCompletion) {
            try await portfolioStore.upsertFund(fundDraft)
            let metadata = syncMetadata(
                syncKey: JDFinanceSyncFingerprint.tradeDraft(
                    FundTradeDraft(
                        action: .buy,
                        code: fundDraft.code,
                        mode: .amount,
                        amount: fundDraft.positionAmount,
                        shares: nil,
                        tradeDate: fundDraft.positionDate,
                        tradeTimeType: fundDraft.positionTimeType
                    )
                ),
                statusText: notice.detailStatusText ?? notice.message
            )
            try portfolioStore.markImportedTradeIfPresent(
                FundTradeDraft(
                    action: .buy,
                    code: fundDraft.code,
                    mode: .amount,
                    amount: fundDraft.positionAmount,
                    shares: nil,
                    tradeDate: fundDraft.positionDate,
                    tradeTimeType: fundDraft.positionTimeType
                ),
                syncMetadata: metadata
            )
            return
        }

        if let tradeDrafts = notice.tradeDrafts(manualCompletion: manualCompletion),
           !tradeDrafts.isEmpty
        {
            for tradeDraft in tradeDrafts {
                try await portfolioStore.importTradeIfNeeded(
                    tradeDraft,
                    syncMetadata: syncMetadata(
                        syncKey: JDFinanceSyncFingerprint.tradeDraft(tradeDraft),
                        statusText: notice.detailStatusText ?? notice.message
                    )
                )
            }
            return
        }

        let conversionDrafts = notice.conversionDrafts(manualCompletion: manualCompletion)
        if !conversionDrafts.isEmpty {
            for conversionDraft in conversionDrafts {
                try await portfolioStore.importConversionIfNeeded(
                    conversionDraft,
                    syncMetadata: syncMetadata(
                        syncKey: JDFinanceSyncFingerprint.conversionDraft(conversionDraft),
                        statusText: notice.detailStatusText ?? notice.message
                    )
                )
            }
            return
        }

        throw JDFinanceHoldingsError.invalidResponse
    }

    private func syncMetadata(syncKey: String, statusText: String?) -> FundTradeSyncMetadata {
        FundTradeSyncMetadata(
            source: .jdFinance,
            syncKey: syncKey,
            externalStatus: .waitingExternalConfirmation,
            externalStatusText: statusText,
            waitsForExternalConfirmation: true
        )
    }

    private static func writeDebugPreview(_ preview: JDFinanceHoldingsSyncPreview, now: Date) {
        let notices = preview.pendingNotices.map { notice in
            [
                "code": notice.code,
                "name": notice.name,
                "amount": MoneyFormatter.plainMoney(notice.amount),
                "message": notice.message,
                "importable": notice.isImportable ? "true" : "false",
                "syncState": debugSyncState(notice.syncState),
                "requiresManualCompletion": notice.requiresManualCompletion ? "true" : "false",
                "tradeDate": notice.pendingDetail?.tradeDate ?? "--",
                "tradeTimeType": notice.pendingDetail?.tradeTimeType?.title ?? "--",
                "statusText": notice.pendingDetail?.statusText ?? "--",
                "matchedRecords": notice.matchedTradeRecords.map(debugRecordSummary).joined(separator: " || "),
                "candidateRecords": notice.candidateTradeRecords.map(debugRecordSummary).joined(separator: " || ")
            ]
        }
        let reconciliations = preview.reconciliationNotices.map { notice in
            [
                "code": notice.code,
                "name": notice.name,
                "state": debugSyncState(notice.state),
                "tradeDate": notice.tradeDate,
                "tradeTimeType": notice.tradeTimeType.title,
                "localAmount": notice.localAmount.map(MoneyFormatter.plainMoney) ?? "--",
                "jdAmount": notice.jdAmount.map(MoneyFormatter.plainMoney) ?? "--",
                "localShares": notice.localShares.map { "\($0)" } ?? "--",
                "jdShares": notice.jdShares.map { "\($0)" } ?? "--",
                "matchedRecords": notice.matchedTradeRecords.map(debugRecordSummary).joined(separator: " || ")
            ]
        }
        let remoteProducts = preview.remoteSnapshot.products.map { product in
            [
                "code": product.code,
                "name": product.name,
                "totalAmount": MoneyFormatter.plainMoney(product.totalAmount),
                "holdingIncome": product.holdIncome.map(MoneyFormatter.plainMoney) ?? "--",
                "transactionTip": product.transactionTipText ?? "--"
            ]
        }
        let remoteProductTotal = preview.remoteSnapshot.products.reduce(0) { $0 + $1.totalAmount }

        let payload: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: now),
            "remoteTotalAssets": preview.remoteSnapshot.totalAssets.map(MoneyFormatter.plainMoney) ?? "--",
            "remoteProductTotal": MoneyFormatter.plainMoney(remoteProductTotal),
            "remoteProductCount": remoteProducts.count,
            "remoteProducts": remoteProducts,
            "pendingNoticeCount": notices.count,
            "pendingNotices": notices,
            "reconciliationCount": reconciliations.count,
            "reconciliations": reconciliations
        ]

        do {
            let url = debugPreviewURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
        } catch {
            // Debug output must never affect the sync flow.
        }
    }

    private static func debugRecordSummary(_ record: JDFinanceTradeOrderRecord) -> String {
        [
            record.code ?? "--",
            record.productName ?? "--",
            record.action?.title ?? "--",
            record.amount.map(MoneyFormatter.plainMoney) ?? "--",
            record.conversionTargetCode.map { "目标代码:\($0)" } ?? "--",
            record.conversionTargetName.map { "目标:\($0)" } ?? "--",
            record.tradeDate ?? "--",
            record.tradeTimeType?.title ?? "--",
            record.statusText ?? "--"
        ].joined(separator: " · ")
    }

    private static func debugSyncState(_ state: JDFinanceSyncPreviewState?) -> String {
        guard let state else { return "--" }
        switch state {
        case .localConfirmedJDPending:
            return "localConfirmedJDPending"
        case .jdConfirmedNeedsOverwrite:
            return "jdConfirmedNeedsOverwrite"
        case .conflict(let message):
            return "conflict: \(message)"
        }
    }

    private static func debugPreviewURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "fund-pulse", directoryHint: .isDirectory)
            .appending(path: "jd-sync-preview-debug.json")
    }
}
