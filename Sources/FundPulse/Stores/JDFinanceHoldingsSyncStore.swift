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
    private let codeResolver: JDFinanceFundCodeResolver
    private let nowProvider: () -> Date
    private var syncGeneration = 0
    private var syncTask: Task<Void, Never>?
    private var previewAccountKey: String?

    init(
        service: JDFinanceHoldingsService = JDFinanceHoldingsService(),
        codeResolver: JDFinanceFundCodeResolver = JDFinanceFundCodeResolver(),
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.codeResolver = codeResolver
        self.nowProvider = now
    }

    func synchronize(portfolioStore: PortfolioStore, cookieHeader: String?) async {
        syncGeneration &+= 1
        let generation = syncGeneration
        syncTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await runSynchronization(
                portfolioStore: portfolioStore,
                cookieHeader: cookieHeader,
                generation: generation
            )
        }
        syncTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func runSynchronization(
        portfolioStore: PortfolioStore,
        cookieHeader: String?,
        generation: Int
    ) async {
        isSyncing = true
        preview = nil
        previewAccountKey = nil
        errorMessage = nil
        lastError = nil
        statusMessage = "正在同步京东持仓..."
        defer {
            if generation == syncGeneration {
                isSyncing = false
                syncTask = nil
            }
        }

        do {
            guard JDFinanceWebSession.hasUsableCookieHeader(cookieHeader) else {
                throw JDFinanceHoldingsError.notLoggedIn
            }
            guard let currentAccountKey = JDFinanceSyncFingerprint.accountKey(cookieHeader: cookieHeader) else {
                throw PortfolioStoreError.jdFinanceAccountUnidentified
            }
            try Self.validateAccountBinding(currentAccountKey, in: portfolioStore)
            let syncedAt = nowProvider()
            let remoteSnapshot = try await service.fetchSnapshot(
                cookieHeader: cookieHeader,
                needsTradeOrderRecords: portfolioStore.needsJDFinanceTradeOrderReconciliation,
                tradeOrderStartDate: portfolioStore.jdFinanceTradeOrderStartDate(now: syncedAt)
            )
            try Task.checkCancellation()
            let resolvedRemoteSnapshot = await codeResolver.resolve(
                snapshot: remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            try Task.checkCancellation()
            guard generation == syncGeneration else { return }
            try Self.validateAccountBinding(currentAccountKey, in: portfolioStore)

            let plannedPreview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: resolvedRemoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            let syncState = Self.nextSyncState(
                current: portfolioStore.snapshot.jdFinanceSyncState,
                remoteSnapshot: resolvedRemoteSnapshot,
                plannedPreview: plannedPreview,
                accountKey: currentAccountKey,
                syncedAt: syncedAt
            )
            let syncedPendingBuyAmounts = plannedPreview.remoteSnapshot.products.reduce(
                into: [String: Double?]()
            ) { result, product in
                guard product.isCodeResolved else { return }
                result[product.code] = product.syncedPendingBuyAmount
            }
            let syncedTodayIncomes = plannedPreview.remoteSnapshot.products.reduce(
                into: [String: Double?]()
            ) { result, product in
                guard product.isCodeResolved else { return }
                result[product.code] = product.todayIncome
            }
            try portfolioStore.applyJDFinanceSyncMetadata(
                accountTotal: resolvedRemoteSnapshot.totalAssets,
                confirmations: plannedPreview.automaticConfirmations,
                syncedAt: syncedAt,
                syncState: syncState,
                syncedPendingBuyAmounts: syncedPendingBuyAmounts,
                syncedTodayIncomes: syncedTodayIncomes
            )
            var updatedPreview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: resolvedRemoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            updatedPreview.autoConfirmedCount = plannedPreview.automaticConfirmations.count
            updatedPreview.baselineRepresentedCount = plannedPreview.baselineRepresentedCount
            preview = updatedPreview
            previewAccountKey = currentAccountKey
#if DEBUG
            Self.writeDebugPreview(updatedPreview, now: syncedAt)
#endif
            lastSyncedAt = syncedAt
            if updatedPreview.autoConfirmedCount > 0, updatedPreview.isEmpty {
                statusMessage = "已同步，自动确认 \(updatedPreview.autoConfirmedCount) 笔"
            } else {
                statusMessage = updatedPreview.isEmpty ? "已同步，暂无差异" : "已生成同步预览"
            }
        } catch is CancellationError {
            return
        } catch let error as JDFinanceHoldingsError {
            guard generation == syncGeneration else { return }
            lastError = error
            errorMessage = error.localizedDescription
            statusMessage = error.localizedDescription
        } catch {
            guard generation == syncGeneration else { return }
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
            reconcileConfirmed: false,
            importUnrecorded: false
        )
    }

    func applySelectedHoldings(
        to portfolioStore: PortfolioStore,
        importNew: Bool,
        updateChanged: Bool,
        importPending: Bool,
        reconcileConfirmed: Bool = false,
        importUnrecorded: Bool = false
    ) async {
        guard let preview else { return }

        let candidates = importNew ? preview.newHoldings : []
        let pendingCandidates = importPending ? preview.importablePendingNotices : []
        let reconciliationCandidates = reconcileConfirmed ? preview.overwritableReconciliationNotices : []
        let unrecordedCandidates = importUnrecorded ? preview.importableUnrecordedOrders : []
        let updates = updateChanged
            ? preview.changedHoldings.map {
                FundAmountPositionSyncUpdate(
                    code: $0.code,
                    amount: $0.jdAmount,
                    holdingIncome: $0.jdHoldingIncome,
                    syncedPendingBuyAmount: $0.jdPendingBuyAmount,
                    syncedAt: self.nowProvider()
                )
            }
            : []
        let selectedCount = candidates.count
            + updates.count
            + pendingCandidates.count
            + reconciliationCandidates.count
            + unrecordedCandidates.count
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
            let accountKey = try validatedPreviewAccount(in: portfolioStore)
            try await portfolioStore.performJDFinanceAtomicMutation { stagingStore in
                for candidate in candidates {
                    try await stagingStore.upsertFund(candidate.draft(positionDate: positionDate))
                }
                for candidate in pendingCandidates {
                    try await self.applyPendingNoticeDraft(candidate, to: stagingStore, manualCompletion: nil)
                }
                for candidate in reconciliationCandidates {
                    try await stagingStore.applyJDFinanceReconciliation(candidate)
                    for order in candidate.matchedTradeRecords {
                        try stagingStore.markJDFinanceOrderRepresented(
                            Self.orderKey(order),
                            dismissed: false
                        )
                    }
                }
                try await stagingStore.applyAmountPositionSyncUpdates(updates)
                for candidate in unrecordedCandidates {
                    try await self.importUnrecordedOrder(candidate, to: stagingStore)
                    try stagingStore.markJDFinanceOrderRepresented(
                        Self.orderKey(candidate.record),
                        dismissed: false
                    )
                }
                try Self.validateAccountBinding(accountKey, in: portfolioStore)
            }
            var updatedPreview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: preview.remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            updatedPreview.autoConfirmedCount = preview.autoConfirmedCount
            self.preview = updatedPreview
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
            let accountKey = try validatedPreviewAccount(in: portfolioStore)
            try await portfolioStore.performJDFinanceAtomicMutation { stagingStore in
                try await self.applyPendingNoticeDraft(
                    notice,
                    to: stagingStore,
                    manualCompletion: manualCompletion
                )
                try Self.validateAccountBinding(accountKey, in: portfolioStore)
            }
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
        syncGeneration &+= 1
        syncTask?.cancel()
        syncTask = nil
        isSyncing = false
        preview = nil
        previewAccountKey = nil
        errorMessage = nil
        lastError = nil
        statusMessage = "已清除京东登录会话"
        lastSyncedAt = nil
    }

    func markUnrecordedOrderAsIncluded(
        _ order: JDFinanceUnrecordedOrder,
        in portfolioStore: PortfolioStore
    ) {
        guard let preview else { return }
        do {
            _ = try validatedPreviewAccount(in: portfolioStore)
            try portfolioStore.markJDFinanceOrderRepresented(
                Self.orderKey(order.record),
                dismissed: true
            )
            var updatedPreview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: preview.remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            updatedPreview.autoConfirmedCount = preview.autoConfirmedCount
            updatedPreview.baselineRepresentedCount = preview.baselineRepresentedCount
            self.preview = updatedPreview
            statusMessage = "已标记为当前持仓已包含"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "标记失败"
        }
    }

    func resetSyncBaseline(in portfolioStore: PortfolioStore) {
        do {
            try portfolioStore.resetJDFinanceSyncState()
            preview = nil
            previewAccountKey = nil
            lastSyncedAt = nil
            errorMessage = nil
            statusMessage = "已重置同步基线，请重新同步"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "重置基线失败"
        }
    }

    func applyFullClearance(
        _ holding: JDFinanceMissingLocalHolding,
        to portfolioStore: PortfolioStore
    ) async {
        guard let preview, holding.canClear, let order = holding.finalOutflowOrder else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = "正在应用清仓对账..."
        defer { isApplying = false }

        do {
            let accountKey = try validatedPreviewAccount(in: portfolioStore)
            let syncedAt = nowProvider()
            try await portfolioStore.performJDFinanceAtomicMutation { stagingStore in
                try stagingStore.applyJDFinanceFullClearance(holding, syncedAt: syncedAt)
                try stagingStore.markJDFinanceOrderRepresented(
                    Self.orderKey(order),
                    dismissed: false
                )
                try Self.validateAccountBinding(accountKey, in: portfolioStore)
            }
            var updatedPreview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: preview.remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            updatedPreview.autoConfirmedCount = preview.autoConfirmedCount
            updatedPreview.baselineRepresentedCount = preview.baselineRepresentedCount
            self.preview = updatedPreview
            statusMessage = "已完成 \(holding.name) 清仓对账"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "清仓对账失败"
        }
    }

    func applyUnrecordedOrder(
        _ order: JDFinanceUnrecordedOrder,
        to portfolioStore: PortfolioStore
    ) async {
        guard let preview, order.isImportable else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = "正在导入京东流水..."
        defer { isApplying = false }

        do {
            let accountKey = try validatedPreviewAccount(in: portfolioStore)
            try await portfolioStore.performJDFinanceAtomicMutation { stagingStore in
                try await self.importUnrecordedOrder(order, to: stagingStore)
                try stagingStore.markJDFinanceOrderRepresented(
                    Self.orderKey(order.record),
                    dismissed: false
                )
                try Self.validateAccountBinding(accountKey, in: portfolioStore)
            }
            var updatedPreview = JDFinanceHoldingsSyncPlanner.preview(
                remoteSnapshot: preview.remoteSnapshot,
                localSnapshot: portfolioStore.snapshot
            )
            updatedPreview.autoConfirmedCount = preview.autoConfirmedCount
            updatedPreview.baselineRepresentedCount = preview.baselineRepresentedCount
            self.preview = updatedPreview
            statusMessage = "已导入 1 笔京东流水"
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "流水导入失败"
        }
    }

    private func applyPendingNoticeDraft(
        _ notice: JDFinanceHoldingPendingNotice,
        to portfolioStore: PortfolioStore,
        manualCompletion: JDFinancePendingManualCompletion?
    ) async throws {
        if let fundDraft = notice.fundPositionDraft(manualCompletion: manualCompletion) {
            try await portfolioStore.upsertFund(fundDraft)
            let initialTradeDraft = FundTradeDraft(
                action: .buy,
                code: fundDraft.code,
                mode: .amount,
                amount: fundDraft.positionAmount,
                shares: nil,
                tradeDate: fundDraft.positionDate,
                tradeTimeType: fundDraft.positionTimeType
            )
            let metadata = syncMetadata(
                syncKey: JDFinanceSyncFingerprint.tradeDraft(initialTradeDraft),
                statusText: notice.detailStatusText ?? notice.message
            )
            try portfolioStore.markImportedTradeIfPresent(
                initialTradeDraft,
                syncMetadata: metadata
            )

            if let matchedDrafts = notice.tradeDrafts(manualCompletion: manualCompletion),
               matchedDrafts.count > 1
            {
                for tradeDraft in matchedDrafts.dropFirst() {
                    try await portfolioStore.importTradeIfNeeded(
                        tradeDraft,
                        syncMetadata: syncMetadata(
                            syncKey: JDFinanceSyncFingerprint.tradeDraft(tradeDraft),
                            statusText: notice.detailStatusText ?? notice.message
                        )
                    )
                }
            }
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

    private func validatedPreviewAccount(in portfolioStore: PortfolioStore) throws -> String {
        guard let previewAccountKey else {
            throw PortfolioStoreError.jdFinanceAccountUnidentified
        }
        try Self.validateAccountBinding(previewAccountKey, in: portfolioStore)
        return previewAccountKey
    }

    private static func validateAccountBinding(
        _ currentAccountKey: String,
        in portfolioStore: PortfolioStore
    ) throws {
        let establishedAccountKeys = Set([
            portfolioStore.snapshot.jdFinanceSyncState?.accountKey,
            portfolioStore.performanceStore.snapshot.jdFinanceSync?.accountKey
        ].compactMap { $0 })
        guard establishedAccountKeys.count <= 1,
              establishedAccountKeys.first.map({ $0 == currentAccountKey }) ?? true
        else {
            throw PortfolioStoreError.jdFinanceAccountMismatch
        }
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

    private func importUnrecordedOrder(
        _ order: JDFinanceUnrecordedOrder,
        to portfolioStore: PortfolioStore
    ) async throws {
        let syncKey = order.record.stableOrderKey
            ?? JDFinanceSyncFingerprint.tradeOrderRecord(order.record)
        let metadata = FundTradeSyncMetadata(
            source: .jdFinance,
            syncKey: syncKey,
            externalStatus: .externalConfirmed,
            externalStatusText: order.record.statusText,
            waitsForExternalConfirmation: false
        )

        if let conversionDraft = order.conversionDraft() {
            try await portfolioStore.importConversionIfNeeded(
                conversionDraft,
                syncMetadata: metadata
            )
            return
        }
        if let tradeDraft = order.tradeDraft() {
            try await portfolioStore.importTradeIfNeeded(
                tradeDraft,
                syncMetadata: metadata
            )
            return
        }
        throw JDFinanceHoldingsError.invalidResponse
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
        let unresolvedHoldings = preview.unresolvedHoldings.map { holding in
            [
                "hasSKUReference": holding.skuID.isEmpty ? "false" : "true",
                "name": holding.name,
                "amount": MoneyFormatter.plainMoney(holding.amount),
                "holdingIncome": holding.holdingIncome.map(MoneyFormatter.plainMoney) ?? "--",
                "message": holding.message
            ]
        }
        let remoteProducts = preview.remoteSnapshot.products.map { product in
            [
                "code": product.code,
                "codeResolution": product.codeResolution.rawValue,
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
            "tradeOrderCount": preview.remoteSnapshot.tradeOrders.count,
            "tradeOrderFetchState": debugTradeOrderFetchState(preview.remoteSnapshot.tradeOrderFetchState),
            "automaticConfirmationCount": preview.autoConfirmedCount,
            "baselineRepresentedCount": preview.baselineRepresentedCount,
            "unrecordedOrderCount": preview.unrecordedOrders.count,
            "informationalOrderCount": preview.informationalOrders.count,
            "warningCount": preview.warnings.count,
            "pendingNoticeCount": notices.count,
            "pendingNotices": notices,
            "reconciliationCount": reconciliations.count,
            "reconciliations": reconciliations,
            "unresolvedCount": unresolvedHoldings.count,
            "unresolvedHoldings": unresolvedHoldings
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

    private static func nextSyncState(
        current: JDFinanceSyncState?,
        remoteSnapshot: JDFinanceHoldingsSnapshot,
        plannedPreview: JDFinanceHoldingsSyncPreview,
        accountKey: String?,
        syncedAt: Date
    ) -> JDFinanceSyncState {
        var representedKeys = Set(current?.representedOrderKeys ?? [])
        representedKeys.formUnion(plannedPreview.baselineOrderKeys)
        representedKeys.formUnion(plannedPreview.automaticConfirmations.compactMap(\.syncKey))
        representedKeys.formUnion(plannedPreview.automaticConfirmations.flatMap(\.representedOrderKeys))

        var trackedPendingKeys = Set(current?.trackedPendingOrderKeys ?? [])
        let terminalKeys = Set(remoteSnapshot.tradeOrders.compactMap { order -> String? in
            switch order.effectiveStatus {
            case .succeeded, .cancelled, .failed:
                return orderKey(order)
            case .pending, .unknown:
                return nil
            }
        })
        trackedPendingKeys.subtract(terminalKeys)

        let baselineDate = DateOnlyFormatter.string(
            from: current?.baselineEstablishedAt ?? syncedAt
        )
        let pendingProductCodes = Set(
            plannedPreview.remoteSnapshot.products
                .filter { $0.transactionTip != nil }
                .map(\.code)
        )
        let pendingProductNames = Set(
            plannedPreview.remoteSnapshot.products
                .filter { $0.transactionTip != nil }
                .map { canonicalName($0.name) }
        )
        let pendingOrders = remoteSnapshot.tradeOrders.filter { order in
            guard order.effectiveStatus == .pending else { return false }
            let key = orderKey(order)
            return trackedPendingKeys.contains(key)
                || order.tradeDate.map { $0 >= baselineDate } == true
                || order.code.map(pendingProductCodes.contains) == true
                || order.productName.map { pendingProductNames.contains(canonicalName($0)) } == true
        }
        trackedPendingKeys.formUnion(pendingOrders.map(orderKey))
        let currentPendingStart = pendingOrders.compactMap(\.tradeDate).min()
        let trackedPendingStartDate: String?
        if trackedPendingKeys.isEmpty {
            trackedPendingStartDate = nil
        } else {
            trackedPendingStartDate = [current?.trackedPendingStartDate, currentPendingStart]
                .compactMap { $0 }
                .min()
        }

        return JDFinanceSyncState(
            accountKey: current?.accountKey ?? accountKey,
            baselineEstablishedAt: current?.baselineEstablishedAt ?? syncedAt,
            lastCompleteTradeOrderSyncAt: remoteSnapshot.tradeOrderFetchState.isComplete
                ? syncedAt
                : current?.lastCompleteTradeOrderSyncAt,
            representedOrderKeys: representedKeys.sorted(),
            dismissedOrderKeys: (current?.dismissedOrderKeys ?? []).sorted(),
            trackedPendingOrderKeys: trackedPendingKeys.sorted(),
            trackedPendingStartDate: trackedPendingStartDate
        )
    }

    private static func orderKey(_ order: JDFinanceTradeOrderRecord) -> String {
        order.stableOrderKey ?? JDFinanceSyncFingerprint.tradeOrderRecord(order)
    }

    private static func canonicalName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "转换-", with: "")
            .replacingOccurrences(of: "转入-", with: "")
            .replacingOccurrences(of: "转出-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
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

    private static func debugTradeOrderFetchState(_ state: JDFinanceTradeOrderFetchState) -> String {
        switch state {
        case .notRequested:
            "notRequested"
        case .complete:
            "complete"
        case .incomplete:
            "incomplete"
        }
    }

    private static func debugPreviewURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "fund-pulse", directoryHint: .isDirectory)
            .appending(path: "jd-sync-preview-debug.json")
    }
}
