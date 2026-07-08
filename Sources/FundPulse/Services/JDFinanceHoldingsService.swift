import Foundation

struct JDFinanceHoldingsService: Sendable {
    static let endpoint = URL(string: "https://ms.jr.jd.com/gw/generic/base/h5/m/fundHoldGroup")!
    static let detailEndpoint = URL(string: "https://ms.jr.jd.com/gw/generic/jj/newna/m/getNewFundPositionDetail")!
    static let tradeOrderListEndpoint = URL(
        string: "https://ms.jr.jd.com/gw2/generic/cfGateway/newna/m/queryTradeOrderList"
    )!
    static let legacyTradeOrderListEndpoint = URL(
        string: "https://ms.jr.jd.com/gw2/generic/cfGateway/h5/m/queryTradeOrderList"
    )!

    private let session: URLSession
    private let networkProbe: JDFinanceNetworkProbe?

    init(session: URLSession = .shared, networkProbe: JDFinanceNetworkProbe? = nil) {
        self.session = session
        self.networkProbe = networkProbe
    }

    func fetchSnapshot(cookieHeader: String?, needsTradeOrderRecords: Bool = false) async throws -> JDFinanceHoldingsSnapshot {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "reqData", value: Self.requestPayload)
        ]
        guard let url = components?.url else {
            throw JDFinanceHoldingsError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("https://jdjr.jd.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            await networkProbe?.recordURLSession(
                endpoint: "fundHoldGroup",
                url: url,
                statusCode: statusCode,
                data: data
            )
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw JDFinanceHoldingsError.network("京东持仓接口请求失败")
            }
            var snapshot = try JDFinanceHoldingsParser.parse(data: data)
            if let cookieHeader, !cookieHeader.isEmpty {
                let tradeOrderRecords = await tradeOrderRecordsIfNeeded(
                    for: snapshot.products,
                    cookieHeader: cookieHeader,
                    forceFetch: needsTradeOrderRecords
                )
                snapshot.products = await productsByFillingPendingDetails(
                    for: snapshot.products,
                    cookieHeader: cookieHeader,
                    tradeOrderRecords: tradeOrderRecords,
                    includeReconciliationCandidates: needsTradeOrderRecords
                )
            }
            return snapshot
        } catch let error as JDFinanceHoldingsError {
            throw error
        } catch {
            throw JDFinanceHoldingsError.network(error.localizedDescription)
        }
    }

    private func productsByFillingPendingDetails(
        for products: [JDFinanceHoldingProduct],
        cookieHeader: String,
        tradeOrderRecords: [JDFinanceTradeOrderRecord],
        includeReconciliationCandidates: Bool
    ) async -> [JDFinanceHoldingProduct] {
        var enrichedProducts: [JDFinanceHoldingProduct] = []
        enrichedProducts.reserveCapacity(products.count)

        for var product in products {
            if let detailRequest = product.detailRequest,
               let detail = try? await fetchPendingDetail(detailRequest, cookieHeader: cookieHeader)
            {
                product.pendingDetail = detail
            }
            if includeReconciliationCandidates, product.transactionTip == nil {
                let candidateRecords = Self.candidateTradeOrderRecords(for: product, in: tradeOrderRecords)
                if !candidateRecords.isEmpty {
                    product.pendingDetail = Self.pendingDetail(
                        product.pendingDetail,
                        product: product,
                        statusText: "已拉取京东交易流水用于对账",
                        candidateTradeRecords: candidateRecords
                    )
                }
            } else if let matchedRecords = Self.matchingTradeOrderRecords(for: product, in: tradeOrderRecords) {
                product.pendingDetail = Self.mergedPendingDetail(
                    product.pendingDetail,
                    with: matchedRecords,
                    for: product
                )
            } else if let unmatchedStatus = Self.unmatchedTradeOrderStatus(
                for: product,
                in: tradeOrderRecords
            ) {
                let candidateRecords = Self.candidateTradeOrderRecords(for: product, in: tradeOrderRecords)
                product.pendingDetail = Self.pendingDetail(
                    product.pendingDetail,
                    product: product,
                    statusText: unmatchedStatus,
                    candidateTradeRecords: candidateRecords
                )
            }
            enrichedProducts.append(product)
        }

        return enrichedProducts
    }

    private func tradeOrderRecordsIfNeeded(
        for products: [JDFinanceHoldingProduct],
        cookieHeader: String,
        forceFetch: Bool = false
    ) async -> [JDFinanceTradeOrderRecord] {
        let pendingProducts = products.filter { $0.transactionTip != nil }
        guard forceFetch || !pendingProducts.isEmpty else {
            return []
        }

        var records = (try? await fetchTradeOrderRecords(cookieHeader: cookieHeader)) ?? []
        for product in pendingProducts {
            let productRecords = (try? await fetchTradeOrderRecords(
                for: product,
                cookieHeader: cookieHeader
            )) ?? []
            records.append(contentsOf: productRecords)
        }
        return await recordsByResolvingConversionTargets(Self.deduplicatedTradeOrderRecords(records))
    }

    private func recordsByResolvingConversionTargets(_ records: [JDFinanceTradeOrderRecord]) async -> [JDFinanceTradeOrderRecord] {
        let quoteService = FundQuoteService(session: session)
        var cache: [String: String?] = [:]
        var result: [JDFinanceTradeOrderRecord] = []
        result.reserveCapacity(records.count)

        for var record in records {
            if record.action == .conversion,
               record.conversionTargetCode == nil,
               let targetName = record.conversionTargetName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !targetName.isEmpty
            {
                let code: String?
                if let cached = cache[targetName] {
                    code = cached
                } else {
                    code = await quoteService.lookupFundCode(name: targetName)
                    cache[targetName] = code
                }
                record.conversionTargetCode = code
            }
            result.append(record)
        }

        return result
    }

    private func fetchPendingDetail(
        _ detailRequest: JDFinanceHoldingDetailRequest,
        cookieHeader: String
    ) async throws -> JDFinancePendingTransactionDetail {
        let payloadObject: [String: Any] = [
            "extJson": detailRequest.extJSON,
            "version": 202
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)
        guard let payload = String(data: payloadData, encoding: .utf8) else {
            throw JDFinanceHoldingsError.invalidResponse
        }

        var components = URLComponents(url: Self.detailEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "reqData", value: payload)
        ]
        guard let url = components?.url else {
            throw JDFinanceHoldingsError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("https://roma.jd.com/fund/hold/list/pc/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        await networkProbe?.recordURLSession(
            endpoint: "getNewFundPositionDetail",
            url: url,
            statusCode: statusCode,
            data: data
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw JDFinanceHoldingsError.network("京东持仓详情接口请求失败")
        }

        return try JDFinanceHoldingDetailParser.parse(data: data)
    }

    private func fetchTradeOrderRecords(
        for product: JDFinanceHoldingProduct? = nil,
        cookieHeader: String,
        pageLimit: Int = 8
    ) async throws -> [JDFinanceTradeOrderRecord] {
        var firstError: Error?
        var hasSuccessfulRequest = false
        var allRecords: [JDFinanceTradeOrderRecord] = []
        for endpoint in [Self.tradeOrderListEndpoint, Self.legacyTradeOrderListEndpoint] {
            do {
                let records = try await fetchTradeOrderRecords(
                    from: endpoint,
                    product: product,
                    cookieHeader: cookieHeader,
                    pageLimit: pageLimit
                )
                hasSuccessfulRequest = true
                if !records.isEmpty {
                    allRecords.append(contentsOf: records)
                }
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if !allRecords.isEmpty {
            return Self.deduplicatedTradeOrderRecords(allRecords)
        }

        if hasSuccessfulRequest {
            return []
        }
        throw firstError ?? JDFinanceHoldingsError.network("京东交易记录接口请求失败")
    }

    private func fetchTradeOrderRecords(
        from endpoint: URL,
        product: JDFinanceHoldingProduct?,
        cookieHeader: String,
        pageLimit: Int
    ) async throws -> [JDFinanceTradeOrderRecord] {
        var records: [JDFinanceTradeOrderRecord] = []
        for page in 1...pageLimit {
            let pageRecords = try await fetchTradeOrderRecords(
                from: endpoint,
                page: page,
                product: product,
                cookieHeader: cookieHeader
            )
            if pageRecords.isEmpty { break }
            records.append(contentsOf: pageRecords)
        }
        return records
    }

    private func fetchTradeOrderRecords(
        from endpoint: URL,
        page: Int,
        product: JDFinanceHoldingProduct?,
        cookieHeader: String
    ) async throws -> [JDFinanceTradeOrderRecord] {
        let payload = try Self.tradeOrderRequestPayload(page: page, product: product)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = Self.formEncodedBody(name: "reqData", value: payload)
        request.setValue(Self.tradeOrderReferer(for: product), forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        await networkProbe?.recordURLSession(
            endpoint: "queryTradeOrderList",
            url: endpoint,
            method: "POST",
            statusCode: statusCode,
            data: data
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw JDFinanceHoldingsError.network("京东交易记录接口请求失败")
        }

        return try JDFinanceTradeOrderParser.parse(data: data)
    }

    private static func deduplicatedTradeOrderRecords(_ records: [JDFinanceTradeOrderRecord]) -> [JDFinanceTradeOrderRecord] {
        var seenKeys = Set<String>()
        var result: [JDFinanceTradeOrderRecord] = []
        result.reserveCapacity(records.count)

        for record in records {
            let key = tradeOrderRecordDedupeKey(record)
            if seenKeys.insert(key).inserted {
                result.append(record)
            }
        }

        return result
    }

    private static func tradeOrderRecordDedupeKey(_ record: JDFinanceTradeOrderRecord) -> String {
        [
            record.code ?? "",
            record.productName ?? "",
            record.conversionTargetCode ?? "",
            record.conversionTargetName ?? "",
            record.action?.rawValue ?? "",
            record.amount.map { String(format: "%.2f", $0) } ?? "",
            record.shares.map { String(format: "%.4f", $0) } ?? "",
            record.tradeDate ?? "",
            record.tradeTimeType?.rawValue ?? "",
            record.statusText ?? ""
        ].joined(separator: "|")
    }

    private static func formEncodedBody(name: String, value: String) -> Data? {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: name, value: value)
        ]
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    static func tradeOrderRequestPayload(
        page: Int,
        now: Date = .now,
        product: JDFinanceHoldingProduct? = nil
    ) throws -> String {
        let dateRange = tradeOrderDateRange(now: now)
        var payloadObject: [String: Any] = [
            "businessCode": "FUND",
            "tradeTypeCodeList": [],
            "pageNo": page,
            "pageType": "na",
            "title": "基金交易",
            "orderCreateStartDate": "\(dateRange.start) 00:00:00",
            "orderCreateEndDate": "\(dateRange.end) 23:59:59"
        ]

        if let product {
            payloadObject["busProductId"] = product.skuID
            payloadObject["productId"] = product.skuID
            if product.isCodeResolved {
                payloadObject["productCode"] = product.code
                payloadObject["fundCode"] = product.code
            }
        }

        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject)
        guard let payload = String(data: payloadData, encoding: .utf8) else {
            throw JDFinanceHoldingsError.invalidResponse
        }
        return payload
    }

    private static func tradeOrderReferer(for product: JDFinanceHoldingProduct?) -> String {
        guard let product else {
            return "https://roma.jd.com/wealth/tradeorder/list?pageShowType=1&businessCode=FUND&pageShowTitle=%E5%9F%BA%E9%87%91%E4%BA%A4%E6%98%93"
        }

        var baseParam: [String: Any] = [
            "productId": product.skuID
        ]
        if product.isCodeResolved {
            baseParam["productCode"] = product.code
            baseParam["fundCode"] = product.code
        }
        let baseParamData = (try? JSONSerialization.data(withJSONObject: baseParam)) ?? Data()
        let baseParamText = String(data: baseParamData, encoding: .utf8) ?? "{}"

        var components = URLComponents(string: "https://roma.jd.com/wealth/tradeorder/list")
        components?.queryItems = [
            URLQueryItem(name: "pageShowType", value: "1"),
            URLQueryItem(name: "businessCode", value: "FUND"),
            URLQueryItem(name: "pageShowTitle", value: "基金交易"),
            URLQueryItem(name: "base_paramExtend", value: baseParamText)
        ]
        return components?.url?.absoluteString
            ?? "https://roma.jd.com/wealth/tradeorder/list?pageShowType=1&businessCode=FUND"
    }

    private static func tradeOrderDateRange(now: Date) -> (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let startDate = calendar.date(byAdding: .year, value: -10, to: now) ?? now
        return (
            DateOnlyFormatter.string(from: startDate),
            DateOnlyFormatter.string(from: now)
        )
    }

    private static func matchingTradeOrderRecords(
        for product: JDFinanceHoldingProduct,
        in records: [JDFinanceTradeOrderRecord]
    ) -> [JDFinanceTradeOrderRecord]? {
        let candidates = records.filter { record in
            record.tradeDate != nil
                && record.tradeTimeType != nil
                && matchesIdentity(record, product: product)
                && matchesAction(record, product: product)
                && matchesUsableStatus(record)
        }

        if let expectedCount = product.transactionTip?.tradeCount,
           expectedCount > 1,
           let expectedAmount = product.transactionTip?.totalAmount,
           let groupedRecords = matchingTradeOrderRecordGroup(
                in: candidates,
                expectedAmount: expectedAmount,
                expectedCount: expectedCount
           )
        {
            return groupedRecords
        }

        if let expectedCount = product.transactionTip?.tradeCount,
           expectedCount > 1,
           let expectedAmount = product.transactionTip?.totalAmount,
           let aggregateRecord = matchingAggregateTradeOrderRecord(
                in: candidates,
                expectedAmount: expectedAmount
           )
        {
            return [aggregateRecord]
        }

        if let expectedCount = product.transactionTip?.tradeCount,
           expectedCount > 1,
           let expectedAmount = product.transactionTip?.totalAmount,
           let ungroupedRecords = matchingUngroupedTradeOrderRecords(
                in: candidates,
                expectedAmount: expectedAmount,
                expectedCount: expectedCount
           )
        {
            return ungroupedRecords
        }

        if let expectedCount = product.transactionTip?.tradeCount,
           expectedCount > 1,
           product.transactionTip?.totalAmount == nil,
           let countedRecords = matchingTradeOrderRecordsByCount(
                in: candidates,
                expectedCount: expectedCount
           )
        {
            return countedRecords
        }

        if let matchedRecord = candidates.first(where: { matchesAmount($0, product: product) }) {
            return [matchedRecord]
        }

        return nil
    }

    private static func candidateTradeOrderRecords(
        for product: JDFinanceHoldingProduct,
        in records: [JDFinanceTradeOrderRecord]
    ) -> [JDFinanceTradeOrderRecord] {
        let candidates = records.filter { record in
            matchesIdentity(record, product: product)
                && matchesAction(record, product: product)
        }
        return Array(candidates.prefix(6))
    }

    private static func unmatchedTradeOrderStatus(
        for product: JDFinanceHoldingProduct,
        in records: [JDFinanceTradeOrderRecord]
    ) -> String? {
        guard product.transactionTip != nil,
              product.pendingDetail?.tradeDate == nil || product.pendingDetail?.tradeTimeType == nil
        else {
            return nil
        }

        guard !records.isEmpty else {
            return "已查交易记录，接口未返回可解析的基金交易记录"
        }

        let sameFundRecords = records.filter { record in
            matchesIdentity(record, product: product)
                && matchesAction(record, product: product)
                && matchesUsableStatus(record)
        }
        guard !sameFundRecords.isEmpty else {
            return "已查交易记录，未找到同基金同方向的有效记录"
        }

        let timedRecords = sameFundRecords.filter { record in
            record.tradeDate != nil && record.tradeTimeType != nil
        }
        guard !timedRecords.isEmpty else {
            return "已查交易记录，找到同基金记录，但未返回交易时间"
        }

        if let expectedCount = product.transactionTip?.tradeCount,
           expectedCount > 1,
           let expectedAmount = product.transactionTip?.totalAmount
        {
            return "已查交易记录，找到 \(timedRecords.count) 笔同基金记录，但未匹配到 \(expectedCount) 笔同日同时段合计 \(MoneyFormatter.plainMoney(expectedAmount))"
        }

        if let expectedAmount = product.transactionTip?.totalAmount ?? product.pendingDetail?.amount {
            return "已查交易记录，找到同基金记录，但未匹配到金额 \(MoneyFormatter.plainMoney(expectedAmount))"
        }

        return "已查交易记录，未匹配到可用交易时间"
    }

    private static func matchesIdentity(_ record: JDFinanceTradeOrderRecord, product: JDFinanceHoldingProduct) -> Bool {
        if product.isCodeResolved, let code = record.code, code == product.code {
            return true
        }
        guard let productName = record.productName else {
            return false
        }
        let normalizedRecordName = normalizedFundName(productName)
        let normalizedProductName = normalizedFundName(product.name)
        let canonicalRecordName = canonicalFundName(productName)
        let canonicalProductName = canonicalFundName(product.name)

        if normalizedRecordName == normalizedProductName || canonicalRecordName == canonicalProductName {
            return true
        }

        return canonicalRecordName.count >= 6
            && canonicalProductName.count >= 6
            && (canonicalRecordName.contains(canonicalProductName) || canonicalProductName.contains(canonicalRecordName))
    }

    private static func matchesAction(_ record: JDFinanceTradeOrderRecord, product: JDFinanceHoldingProduct) -> Bool {
        let expectedAction = product.pendingDetail?.action ?? product.transactionTip?.action
        guard let expectedAction, expectedAction != .unknown else {
            return true
        }
        guard let recordAction = record.action, recordAction != .unknown else {
            return true
        }
        return recordAction == expectedAction
    }

    private static func matchesAmount(_ record: JDFinanceTradeOrderRecord, product: JDFinanceHoldingProduct) -> Bool {
        let expectedAmount = product.transactionTip?.totalAmount ?? product.pendingDetail?.amount
        guard let expectedAmount else { return true }
        guard let amount = record.amount else { return false }
        return abs(amount - expectedAmount) < 0.01
    }

    private static func matchesUsableStatus(_ record: JDFinanceTradeOrderRecord) -> Bool {
        guard let statusText = record.statusText else {
            return true
        }

        let normalized = statusText.uppercased()
        let rejectedTokens = [
            "取消",
            "撤单",
            "撤销",
            "失败",
            "退款",
            "CANCEL",
            "FAIL",
            "REFUND"
        ]
        return !rejectedTokens.contains { normalized.contains($0) }
    }

    private static func matchingTradeOrderRecordGroup(
        in records: [JDFinanceTradeOrderRecord],
        expectedAmount: Double,
        expectedCount: Int
    ) -> [JDFinanceTradeOrderRecord]? {
        guard expectedCount > 1 else { return nil }
        let groups = recordsGroupedByTradeTiming(records)
        for group in groups {
            if let subset = matchingAmountSubset(
                in: group.records,
                expectedAmount: expectedAmount,
                expectedCount: expectedCount
            ) {
                return subset
            }
        }
        return nil
    }

    private static func matchingAggregateTradeOrderRecord(
        in records: [JDFinanceTradeOrderRecord],
        expectedAmount: Double
    ) -> JDFinanceTradeOrderRecord? {
        let amountMatches = records.filter { record in
            guard let amount = record.amount else { return false }
            return abs(amount - expectedAmount) < 0.01
        }
        return amountMatches.count == 1 ? amountMatches.first : nil
    }

    private static func matchingUngroupedTradeOrderRecords(
        in records: [JDFinanceTradeOrderRecord],
        expectedAmount: Double,
        expectedCount: Int
    ) -> [JDFinanceTradeOrderRecord]? {
        matchingAmountSubset(
            in: records,
            expectedAmount: expectedAmount,
            expectedCount: expectedCount
        )
    }

    private static func matchingTradeOrderRecordsByCount(
        in records: [JDFinanceTradeOrderRecord],
        expectedCount: Int
    ) -> [JDFinanceTradeOrderRecord]? {
        guard expectedCount > 1 else { return nil }

        for group in recordsGroupedByTradeTiming(records) where group.records.count == expectedCount {
            return group.records
        }

        return records.count == expectedCount ? records : nil
    }

    private struct TradeTimingGroup {
        var date: String
        var timeType: PositionTimeType
        var records: [JDFinanceTradeOrderRecord]
    }

    private static func recordsGroupedByTradeTiming(_ records: [JDFinanceTradeOrderRecord]) -> [TradeTimingGroup] {
        var groups: [TradeTimingGroup] = []

        for record in records {
            guard let date = record.tradeDate,
                  let timeType = record.tradeTimeType
            else {
                continue
            }

            if let index = groups.firstIndex(where: { $0.date == date && $0.timeType == timeType }) {
                groups[index].records.append(record)
            } else {
                groups.append(TradeTimingGroup(date: date, timeType: timeType, records: [record]))
            }
        }

        return groups
    }

    private static func matchingAmountSubset(
        in records: [JDFinanceTradeOrderRecord],
        expectedAmount: Double,
        expectedCount: Int
    ) -> [JDFinanceTradeOrderRecord]? {
        let candidates = records.filter { record in
            guard let amount = record.amount else { return false }
            return amount > 0 && amount <= expectedAmount + 0.01
        }
        guard candidates.count >= expectedCount else {
            return nil
        }

        var selected: [JDFinanceTradeOrderRecord] = []
        return findAmountSubset(
            in: candidates,
            startIndex: 0,
            expectedAmount: expectedAmount,
            expectedCount: expectedCount,
            selectedAmount: 0,
            selected: &selected
        )
    }

    private static func findAmountSubset(
        in records: [JDFinanceTradeOrderRecord],
        startIndex: Int,
        expectedAmount: Double,
        expectedCount: Int,
        selectedAmount: Double,
        selected: inout [JDFinanceTradeOrderRecord]
    ) -> [JDFinanceTradeOrderRecord]? {
        if selected.count == expectedCount {
            return abs(selectedAmount - expectedAmount) < 0.01 ? selected : nil
        }

        guard startIndex < records.count else { return nil }

        let remainingSlots = expectedCount - selected.count
        guard records.count - startIndex >= remainingSlots else { return nil }

        for index in startIndex..<records.count {
            guard let amount = records[index].amount else { continue }
            let nextAmount = selectedAmount + amount
            if nextAmount > expectedAmount + 0.01 { continue }

            selected.append(records[index])
            if let result = findAmountSubset(
                in: records,
                startIndex: index + 1,
                expectedAmount: expectedAmount,
                expectedCount: expectedCount,
                selectedAmount: nextAmount,
                selected: &selected
            ) {
                return result
            }
            selected.removeLast()
        }

        return nil
    }

    private static func mergedPendingDetail(
        _ detail: JDFinancePendingTransactionDetail?,
        with records: [JDFinanceTradeOrderRecord],
        for product: JDFinanceHoldingProduct
    ) -> JDFinancePendingTransactionDetail {
        let firstKnownAction = records.compactMap(\.action).first { $0 != .unknown }
        let totalRecordAmount = summedAmount(records)
        let totalShares = summedShares(records)
        let commonDate = commonValue(records.compactMap(\.tradeDate))
        let commonTimeType = commonValue(records.compactMap(\.tradeTimeType))

        return JDFinancePendingTransactionDetail(
            action: detail?.action ?? product.transactionTip?.action ?? firstKnownAction,
            amount: detailAmount(detail, product: product, records: records, totalRecordAmount: totalRecordAmount),
            shares: detail?.shares ?? totalShares,
            tradeDate: detail?.tradeDate ?? commonDate,
            tradeTimeType: detail?.tradeTimeType ?? commonTimeType,
            statusText: records.count > 1 ? (aggregateStatusText(for: records) ?? detail?.statusText) : (detail?.statusText ?? aggregateStatusText(for: records)),
            matchedTradeRecords: records
        )
    }

    private static func pendingDetail(
        _ detail: JDFinancePendingTransactionDetail?,
        product: JDFinanceHoldingProduct,
        statusText: String,
        candidateTradeRecords: [JDFinanceTradeOrderRecord] = []
    ) -> JDFinancePendingTransactionDetail {
        let existingCandidates = detail?.candidateTradeRecords ?? []
        return JDFinancePendingTransactionDetail(
            action: detail?.action ?? product.transactionTip?.action,
            amount: detail?.amount ?? product.transactionTip?.totalAmount,
            shares: detail?.shares,
            tradeDate: detail?.tradeDate,
            tradeTimeType: detail?.tradeTimeType,
            statusText: statusText,
            matchedTradeRecords: detail?.matchedTradeRecords ?? [],
            candidateTradeRecords: existingCandidates.isEmpty ? candidateTradeRecords : existingCandidates
        )
    }

    private static func detailAmount(
        _ detail: JDFinancePendingTransactionDetail?,
        product: JDFinanceHoldingProduct,
        records: [JDFinanceTradeOrderRecord],
        totalRecordAmount: Double?
    ) -> Double? {
        if records.count > 1 {
            return product.transactionTip?.totalAmount ?? totalRecordAmount ?? detail?.amount
        }
        return detail?.amount ?? records.first?.amount ?? product.transactionTip?.totalAmount
    }

    private static func summedAmount(_ records: [JDFinanceTradeOrderRecord]) -> Double? {
        let amounts = records.compactMap(\.amount)
        guard amounts.count == records.count else { return nil }
        return amounts.reduce(0, +)
    }

    private static func summedShares(_ records: [JDFinanceTradeOrderRecord]) -> Double? {
        let shares = records.compactMap(\.shares)
        guard !shares.isEmpty, shares.count == records.count else { return nil }
        return shares.reduce(0, +)
    }

    private static func commonValue<Value: Hashable>(_ values: [Value]) -> Value? {
        guard let first = values.first,
              values.allSatisfy({ $0 == first })
        else {
            return nil
        }
        return first
    }

    private static func aggregateStatusText(for records: [JDFinanceTradeOrderRecord]) -> String? {
        guard records.count > 1 else {
            return records.first?.statusText
        }

        if let date = commonValue(records.compactMap(\.tradeDate)),
           let timeType = commonValue(records.compactMap(\.tradeTimeType))
        {
            return "匹配交易记录：\(records.count) 笔，\(date) \(timeType.title)"
        }

        return "匹配交易记录：\(records.count) 笔"
    }

    private static func normalizedFundName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    private static func canonicalFundName(_ value: String) -> String {
        normalizedFundName(value)
            .replacingOccurrences(of: "中证", with: "")
            .replacingOccurrences(of: "转换-", with: "")
            .replacingOccurrences(of: "转入-", with: "")
            .replacingOccurrences(of: "转出-", with: "")
    }

    private static let requestPayload = """
    {"clientVersion":"","clientType":"android","apiVersion":1,"appChannel":"fund_jjcc","sortKey":"1","sortDirection":"DESC","extParams":{"channelCode":"outside"}}
    """
}

enum JDFinanceHoldingsParser {
    static func parse(data: Data) throws -> JDFinanceHoldingsSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JDFinanceHoldingsError.invalidResponse
        }

        guard let envelope = object as? [String: Any] else {
            throw JDFinanceHoldingsError.invalidResponse
        }

        try validateLoginState(in: envelope)

        let outerResultData = envelope["resultData"] as? [String: Any]
        if let outerResultData {
            try validateLoginState(in: outerResultData)
        }

        let payload = (outerResultData?["resultData"] as? [String: Any]) ?? outerResultData
        guard let payload else {
            throw JDFinanceHoldingsError.invalidResponse
        }

        let headAssetsData = payload["headAssetsData"] as? [String: Any]
        let fundData = payload["fundData"] as? [String: Any]
        let fundList = fundData?["fundList"] as? [[String: Any]] ?? []
        let productRows = fundList.flatMap { row in
            row["productList"] as? [[String: Any]] ?? []
        }
        let products = productRows.compactMap(parseProduct)

        guard !products.isEmpty else {
            throw JDFinanceHoldingsError.emptyHoldings
        }

        return JDFinanceHoldingsSnapshot(
            totalAssets: numericValue(headAssetsData?["totalAssets"]),
            yesterdayIncome: numericValue(headAssetsData?["yesterdayIncome"]),
            todayIncome: numericValue(headAssetsData?["todayIncome"]),
            holdIncome: numericValue(headAssetsData?["holdIncome"]),
            totalIncome: numericValue(headAssetsData?["totalIncome"]),
            products: products
        )
    }

    private static func validateLoginState(in dictionary: [String: Any]) throws {
        let resultCode = stringValue(dictionary["resultCode"])
        let resultMessage = stringValue(dictionary["resultMsg"]) ?? ""
        if resultCode == "3" || resultMessage.contains("请先登录") || resultMessage.contains("登录京东") {
            throw JDFinanceHoldingsError.notLoggedIn
        }
    }

    private static func parseProduct(_ dictionary: [String: Any]) -> JDFinanceHoldingProduct? {
        guard let skuID = stringValue(dictionary["skuId"] ?? dictionary["skuID"] ?? dictionary["sku"]),
              let name = stringValue(dictionary["productName"] ?? dictionary["name"]),
              let totalAmount = numericValue(dictionary["totalAmount"])
        else {
            return nil
        }
        let explicitCode = explicitFundCode(in: dictionary)

        return JDFinanceHoldingProduct(
            skuID: skuID,
            code: explicitCode ?? "",
            codeResolution: explicitCode == nil ? .unresolved : .explicit,
            name: name,
            totalAmount: totalAmount,
            yesterdayIncome: numericValue(dictionary["yesterdayIncome"]),
            yesterdayIncomeNotice: noticeTextValue(dictionary["yesterdayIncome"]),
            todayIncome: numericValue(dictionary["todayIncome"]),
            holdIncome: numericValue(dictionary["holdIncome"]),
            holdRate: numericValue(dictionary["holdRate"]),
            transactionTip: parseTransactionTip(dictionary["transactionTip"]),
            detailRequest: parseDetailRequest(in: dictionary),
            pendingDetail: nil
        )
    }

    private static func parseTransactionTip(_ value: Any?) -> JDFinanceTransactionTip? {
        guard let text = stringValue(value) else { return nil }
        return JDFinanceTransactionTip(
            text: text,
            action: pendingTradeAction(from: text),
            tradeCount: regexInt(pattern: #"(\d+)\s*笔"#, in: text),
            totalAmount: transactionTotalAmount(from: text)
        )
    }

    private static func parseDetailRequest(in dictionary: [String: Any]) -> JDFinanceHoldingDetailRequest? {
        guard let extJSON = nestedStringValue(forKey: "extJson", in: dictionary) else {
            return nil
        }
        return JDFinanceHoldingDetailRequest(extJSON: extJSON)
    }

    private static func nestedStringValue(forKey targetKey: String, in value: Any?) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, value) in dictionary where key.caseInsensitiveCompare(targetKey) == .orderedSame {
                if let text = stringValue(value) {
                    return text
                }
            }
            for value in dictionary.values {
                if let text = nestedStringValue(forKey: targetKey, in: value) {
                    return text
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let text = nestedStringValue(forKey: targetKey, in: item) {
                    return text
                }
            }
        }

        return nil
    }

    private static func explicitFundCode(in dictionary: [String: Any]) -> String? {
        let explicitCodeKeys = [
            "fundCode",
            "fundcode",
            "fund_code",
            "fundCd",
            "fundcd",
            "fundNo",
            "fundno",
            "productCode",
            "productcode",
            "jjdm"
        ]

        for key in explicitCodeKeys {
            if let code = normalizedFundCode(from: dictionary[key]) {
                return code
            }
        }

        for value in dictionary.values {
            if let nested = value as? [String: Any],
               let code = explicitFundCode(in: nested)
            {
                return code
            }
        }

        return nil
    }

    private static func normalizedFundCode(from value: Any?) -> String? {
        guard let rawValue = stringValue(value) else { return nil }
        let digits = rawValue.filter(\.isNumber)
        guard digits.count == 6 else { return nil }
        return digits
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        case let value as [String: Any]:
            return stringValue(value["text"])
                ?? stringValue(value["subTitle"])
                ?? stringValue(value["title"])
                ?? stringValue(value["amt"])
        default:
            return nil
        }
    }

    private static func noticeTextValue(_ value: Any?) -> String? {
        guard numericValue(value) == nil else { return nil }
        return stringValue(value)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            guard value.isFinite else { return nil }
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return parseNumber(value)
        case let value as [String: Any]:
            return numericValue(value["amt"])
                ?? numericValue(value["text"])
                ?? numericValue(value["subTitle"])
                ?? numericValue(value["title"])
        default:
            return nil
        }
    }

    private static func parseNumber(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "+", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized != "--",
              normalized != "-"
        else {
            return nil
        }
        return Double(normalized)
    }

    private static func pendingTradeAction(from text: String) -> JDFinancePendingTradeAction {
        if text.contains("转换") || text.contains("转入") || text.contains("转出") {
            return .conversion
        }
        if text.contains("买入") || text.contains("申购") || text.contains("加仓") {
            return .buy
        }
        if text.contains("卖出") || text.contains("赎回") || text.contains("减仓") {
            return .sell
        }
        return .unknown
    }

    private static func transactionTotalAmount(from text: String) -> Double? {
        if let value = regexString(pattern: #"合计\s*([+-]?[0-9][0-9,]*(?:\.[0-9]+)?)\s*元"#, in: text) {
            return parseNumber(value)
        }
        if let value = regexString(pattern: #"([+-]?[0-9][0-9,]*(?:\.[0-9]+)?)\s*元"#, in: text) {
            return parseNumber(value)
        }
        return nil
    }

    private static func regexInt(pattern: String, in text: String) -> Int? {
        regexString(pattern: pattern, in: text).flatMap(Int.init)
    }

    private static func regexString(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }
}

private enum JDFinanceHoldingDetailParser {
    private struct Leaf {
        var path: String
        var value: String
    }

    static func parse(data: Data) throws -> JDFinancePendingTransactionDetail {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JDFinanceHoldingsError.invalidResponse
        }

        guard let envelope = object as? [String: Any] else {
            throw JDFinanceHoldingsError.invalidResponse
        }
        try validateLoginState(in: envelope)

        let leaves = leafValues(in: envelope)
        guard !leaves.isEmpty else {
            throw JDFinanceHoldingsError.invalidResponse
        }

        return JDFinancePendingTransactionDetail(
            action: parseAction(from: leaves),
            amount: parseAmount(from: leaves),
            shares: parseShares(from: leaves),
            tradeDate: parseTradeDate(from: leaves),
            tradeTimeType: parseTradeTimeType(from: leaves),
            statusText: parseStatusText(from: leaves)
        )
    }

    private static func validateLoginState(in dictionary: [String: Any]) throws {
        let resultCode = stringValue(dictionary["resultCode"])
        let resultMessage = stringValue(dictionary["resultMsg"]) ?? ""
        if resultCode == "3" || resultMessage.contains("请先登录") || resultMessage.contains("登录京东") {
            throw JDFinanceHoldingsError.notLoggedIn
        }
    }

    private static func parseAction(from leaves: [Leaf]) -> JDFinancePendingTradeAction? {
        let preferredLeaves = leaves.sorted { lhs, rhs in
            score(lhs.path, keywords: ["action", "type", "trade", "order", "status", "state"]) >
                score(rhs.path, keywords: ["action", "type", "trade", "order", "status", "state"])
        }

        for leaf in preferredLeaves {
            if leaf.value.contains("转换") || leaf.value.contains("转入") || leaf.value.contains("转出") {
                return .conversion
            }
            if leaf.value.contains("买入") || leaf.value.contains("申购") || leaf.value.contains("加仓") {
                return .buy
            }
            if leaf.value.contains("卖出") || leaf.value.contains("赎回") || leaf.value.contains("减仓") {
                return .sell
            }
        }

        return nil
    }

    private static func parseAmount(from leaves: [Leaf]) -> Double? {
        let preferred = leaves
            .filter { leaf in
                let path = leaf.path.lowercased()
                return (path.contains("amount") || path.contains("amt") || path.contains("money") || path.contains("balance"))
                    && !path.contains("share")
                    && !path.contains("income")
                    && !path.contains("profit")
                    && !path.contains("rate")
            }

        for leaf in preferred {
            if let value = numericValue(leaf.value), value > 0 {
                return value
            }
        }

        for leaf in leaves where leaf.value.contains("金额") || leaf.value.contains("合计") || leaf.value.contains("元") {
            if let value = numericValue(leaf.value), value > 0 {
                return value
            }
        }

        return nil
    }

    private static func parseShares(from leaves: [Leaf]) -> Double? {
        let preferred = leaves.filter { leaf in
            let path = leaf.path.lowercased()
            return path.contains("share") || path.contains("份额")
        }

        for leaf in preferred {
            if let value = numericValue(leaf.value), value > 0 {
                return value
            }
        }

        for leaf in leaves where leaf.value.contains("份") {
            if let value = numericValue(leaf.value), value > 0 {
                return value
            }
        }

        return nil
    }

    private static func parseTradeDate(from leaves: [Leaf]) -> String? {
        let preferred = leaves.filter(isTradeTimingCandidate).sorted { lhs, rhs in
            score(lhs.path, keywords: ["trade", "apply", "order", "date", "time"]) >
                score(rhs.path, keywords: ["trade", "apply", "order", "date", "time"])
        }

        for leaf in preferred {
            guard !leaf.value.contains("预计"),
                  let date = normalizedDate(from: leaf.value)
            else { continue }
            return date
        }

        return nil
    }

    private static func parseTradeTimeType(from leaves: [Leaf]) -> PositionTimeType? {
        let preferred = leaves.filter(isTradeTimingCandidate).sorted { lhs, rhs in
            score(lhs.path, keywords: ["trade", "apply", "order", "time", "date"]) >
                score(rhs.path, keywords: ["trade", "apply", "order", "time", "date"])
        }

        for leaf in preferred {
            if let timeType = explicitTimeType(from: leaf.value) ?? clockTimeType(from: leaf.value) {
                return timeType
            }
        }

        return nil
    }

    private static func isTradeTimingCandidate(_ leaf: Leaf) -> Bool {
        let path = leaf.path.lowercased()
        let positivePathTokens = ["trade", "apply", "order", "accept", "create", "deal", "entrust", "submit", "business"]
        let negativePathTokens = ["update", "expect", "estimate", "income", "profit", "nav", "netvalue", "notice", "tip"]
        let hasPositivePath = positivePathTokens.contains { path.contains($0) }
        let hasNegativePath = negativePathTokens.contains { path.contains($0) }
        let hasTradeTimingText = leaf.value.contains("交易日")
            || leaf.value.contains("下单时间")
            || leaf.value.contains("申请时间")
            || leaf.value.contains("受理时间")
            || leaf.value.contains("委托时间")
            || leaf.value.contains("成交时间")

        return (hasPositivePath || hasTradeTimingText) && !hasNegativePath && !leaf.value.contains("预计")
    }

    private static func parseStatusText(from leaves: [Leaf]) -> String? {
        let statusLeaves = leaves.filter { leaf in
            let path = leaf.path.lowercased()
            return path.contains("status") || path.contains("state") || path.contains("tip") || path.contains("desc")
        }
        let candidates = statusLeaves + leaves
        return candidates.first { leaf in
            leaf.value.contains("确认")
                || leaf.value.contains("交易中")
                || leaf.value.contains("处理中")
                || leaf.value.contains("买入中")
                || leaf.value.contains("卖出中")
        }?.value
    }

    private static func leafValues(in value: Any, path: String = "") -> [Leaf] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, value in
                leafValues(in: value, path: path.isEmpty ? key : "\(path).\(key)")
            }
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, value in
                leafValues(in: value, path: "\(path)[\(index)]")
            }
        }

        guard let text = stringValue(value) else { return [] }
        return [Leaf(path: path, value: text)]
    }

    private static func normalizedDate(from text: String) -> String? {
        let patterns = [
            #"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})"#,
            #"(\d{4})\.(\d{1,2})\.(\d{1,2})"#,
            #"\b(\d{4})(\d{2})(\d{2})\b"#
        ]

        for pattern in patterns {
            guard let captures = regexCaptures(pattern: pattern, in: text),
                  captures.count == 3,
                  let year = Int(captures[0]),
                  let month = Int(captures[1]),
                  let day = Int(captures[2])
            else { continue }

            let normalized = String(format: "%04d-%02d-%02d", year, month, day)
            if DateOnlyFormatter.parse(normalized) != nil {
                return normalized
            }
        }

        if let captures = regexCaptures(pattern: #"(?:^|[^0-9])(\d{1,2})[-/.月](\d{1,2})(?:日)?(?:\s+[0-2]?\d[:：][0-5]\d)"#, in: text),
           captures.count == 2,
           let month = Int(captures[0]),
           let day = Int(captures[1])
        {
            let year = Calendar.current.component(.year, from: .now)
            let normalized = String(format: "%04d-%02d-%02d", year, month, day)
            if DateOnlyFormatter.parse(normalized) != nil {
                return normalized
            }
        }

        return nil
    }

    private static func explicitTimeType(from text: String) -> PositionTimeType? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
        if normalized.contains("15:00前")
            || normalized.contains("15点前")
            || normalized.contains("三点前")
            || normalized.contains("下午3点前")
        {
            return .before15
        }

        if normalized.contains("15:00后")
            || normalized.contains("15点后")
            || normalized.contains("三点后")
            || normalized.contains("下午3点后")
        {
            return .after15
        }

        return nil
    }

    private static func clockTimeType(from text: String) -> PositionTimeType? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
        let hourText = regexCaptures(pattern: #"\b([01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?\b"#, in: normalized)?.first
            ?? regexCaptures(pattern: #"(^|[^0-9])([01]?\d|2[0-3])点(?:[0-5]\d分?)?"#, in: normalized)?.last
        guard let hourText,
              let hour = Int(hourText)
        else {
            return nil
        }
        return hour < 15 ? .before15 : .after15
    }

    private static func score(_ value: String, keywords: [String]) -> Int {
        let lowercased = value.lowercased()
        return keywords.reduce(0) { total, keyword in
            total + (lowercased.contains(keyword) ? 1 : 0)
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        case let value as [String: Any]:
            return stringValue(value["text"])
                ?? stringValue(value["subTitle"])
                ?? stringValue(value["title"])
                ?? stringValue(value["amt"])
        default:
            return nil
        }
    }

    private static func numericValue(_ value: String) -> Double? {
        let match = regexCaptures(pattern: #"([+-]?[0-9][0-9,]*(?:\.[0-9]+)?)"#, in: value)?.first ?? value
        let normalized = match
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "+", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized != "--",
              normalized != "-"
        else {
            return nil
        }
        return Double(normalized)
    }

    private static func regexCaptures(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1
        else {
            return nil
        }

        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            captures.append(String(text[range]))
        }
        return captures
    }
}

enum JDFinanceTradeOrderParser {
    private struct Leaf {
        var path: String
        var value: String
    }

    private static let tradeAmountKeys = [
        "allAmount",
        "amount",
        "orderAmount",
        "tradeAmount",
        "payAmount",
        "actualAmount",
        "applyAmount",
        "applyAmt",
        "orderPayAmount",
        "transactionAmount",
        "businessAmount",
        "allAmountText",
        "amountText",
        "tradeAmountText"
    ]

    static func parse(data: Data) throws -> [JDFinanceTradeOrderRecord] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JDFinanceHoldingsError.invalidResponse
        }

        if let dictionary = object as? [String: Any] {
            try validateLoginState(in: dictionary)
        }

        return tradeOrderRows(in: object).compactMap(parseRecord)
    }

    private static func validateLoginState(in dictionary: [String: Any]) throws {
        let resultCode = stringValue(dictionary["resultCode"])
        let resultMessage = stringValue(dictionary["resultMsg"]) ?? ""
        if resultCode == "3" || resultMessage.contains("请先登录") || resultMessage.contains("登录京东") {
            throw JDFinanceHoldingsError.notLoggedIn
        }
    }

    private static func tradeOrderRows(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            if let rows = dictionary["tradeOrderVoList"] as? [[String: Any]] {
                return rows
            }
            if isTradeOrderRow(dictionary) {
                return [dictionary]
            }
            return dictionary.values.flatMap(tradeOrderRows)
        }

        if let array = value as? [Any] {
            return array.flatMap(tradeOrderRows)
        }

        if let text = value as? String,
           let object = jsonObject(from: text)
        {
            return tradeOrderRows(in: object)
        }

        return []
    }

    private static func isTradeOrderRow(_ dictionary: [String: Any]) -> Bool {
        let hasIdentity = explicitFundCode(in: dictionary) != nil
            || firstStringValue(
                in: dictionary,
                keys: ["productName", "sellProductName", "fundName", "productFullName", "productTitle", "skuName", "name"]
            ) != nil
        let hasAmount = firstNumericValue(in: dictionary, keys: tradeAmountKeys) != nil
        let hasTiming = parseTradeTiming(in: dictionary) != nil
        let hasTradeType = firstStringValue(
            in: dictionary,
            keys: ["tradeTypeName", "tradeTypeCode", "tradeType", "tradeTypeDesc", "orderTypeName"]
        ) != nil
        let hasStatus = firstStringValue(
            in: dictionary,
            keys: ["statusName", "statusDesc", "statusText", "statusCode", "orderStatus", "orderStatusName"]
        ) != nil

        return hasIdentity && (hasAmount || hasTiming || hasTradeType || hasStatus)
    }

    private static func parseRecord(_ dictionary: [String: Any]) -> JDFinanceTradeOrderRecord? {
        let timing = parseTradeTiming(in: dictionary)
        let productName = firstStringValue(
            in: dictionary,
            keys: ["productName", "sellProductName", "fundName", "productFullName", "productTitle", "skuName", "name"]
        )
        let conversionTargetName = firstStringValue(
            in: dictionary,
            keys: ["sellProductName", "targetProductName", "targetFundName", "toProductName", "toFundName"]
        )
        let conversionTargetCode = conversionTargetFundCode(in: dictionary)
        let statusText = firstStringValue(
            in: dictionary,
            keys: ["statusName", "statusDesc", "statusText", "statusCode", "orderStatus", "orderStatusName"]
        )

        guard productName != nil || explicitFundCode(in: dictionary) != nil else {
            return nil
        }

        let code = explicitFundCode(in: dictionary)
        let action = parseAction(in: dictionary)
        let amount = firstNumericValue(in: dictionary, keys: tradeAmountKeys)
        let shares = numericValue(dictionary["share"])
            ?? numericValue(dictionary["shares"])
            ?? numericValue(dictionary["tradeShare"])
        let resolvedShares = shares ?? ((action == .conversion || action == .sell) ? amount : nil)

        return JDFinanceTradeOrderRecord(
            code: code,
            productName: productName,
            conversionTargetCode: action == .conversion ? conversionTargetCode : nil,
            conversionTargetName: action == .conversion ? conversionTargetName : nil,
            action: action,
            amount: amount,
            shares: resolvedShares,
            tradeDate: timing?.date,
            tradeTimeType: timing?.timeType,
            statusText: statusText
        )
    }

    private static func parseAction(in dictionary: [String: Any]) -> JDFinancePendingTradeAction? {
        let candidates = [
            stringValue(dictionary["tradeTypeName"]),
            stringValue(dictionary["tradeTypeCode"]),
            stringValue(dictionary["tradeType"]),
            stringValue(dictionary["tradeTypeDesc"]),
            stringValue(dictionary["orderTypeName"]),
            stringValue(dictionary["statusName"]),
            stringValue(dictionary["statusDesc"])
        ].compactMap { $0 }

        for candidate in candidates {
            let normalized = candidate.uppercased()
            if candidate.contains("转换")
                || normalized.contains("TRANSFORM")
                || normalized.contains("CONVERT")
                || normalized.contains("CONVERSION")
            {
                return .conversion
            }
            if candidate.contains("买入")
                || candidate.contains("申购")
                || candidate.contains("加仓")
                || normalized.contains("BUY")
                || normalized.contains("APPLY")
                || normalized.contains("PURCHASE")
                || normalized.contains("SUBSCRIBE")
                || normalized.contains("TRANSFER_IN")
            {
                return .buy
            }
            if candidate.contains("卖出")
                || candidate.contains("赎回")
                || candidate.contains("减仓")
                || normalized.contains("SELL")
                || normalized.contains("REDEEM")
                || normalized.contains("REDEMPTION")
                || normalized.contains("TRANSFER_OUT")
            {
                return .sell
            }
        }

        return .unknown
    }

    private static func parseTradeTiming(in dictionary: [String: Any]) -> (date: String, timeType: PositionTimeType?)? {
        let preferredLeaves = leafValues(in: dictionary).filter(isTradeTimingCandidate).sorted { lhs, rhs in
            score(lhs.path, keywords: ["biztime", "trade", "apply", "order", "create", "time"]) >
                score(rhs.path, keywords: ["biztime", "trade", "apply", "order", "create", "time"])
        }

        var fallbackDate: String?
        var fallbackTimeType: PositionTimeType?
        for leaf in preferredLeaves {
            if let timing = normalizedDateAndTime(from: leaf.value) {
                if timing.timeType != nil {
                    return timing
                }
                fallbackDate = fallbackDate ?? timing.date
            }
            fallbackTimeType = fallbackTimeType ?? explicitTimeType(from: leaf.value) ?? clockTimeType(from: leaf.value)
            if let fallbackDate, let fallbackTimeType {
                return (fallbackDate, fallbackTimeType)
            }
        }

        if let fallbackDate {
            return (fallbackDate, fallbackTimeType)
        }
        return nil
    }

    private static func isTradeTimingCandidate(_ leaf: Leaf) -> Bool {
        let path = leaf.path.lowercased()
        let positivePathTokens = [
            "biztime",
            "tradetime",
            "tradedate",
            "applytime",
            "applydate",
            "ordertime",
            "ordercreatetime",
            "ordercreatedate",
            "createtime",
            "createdate",
            "accepttime",
            "acceptdate",
            "dealtime",
            "dealdate",
            "submittime",
            "submitdate",
            "businesstime",
            "businessdate",
            "currenttime",
            "paytime",
            "paydate",
            "requesttime",
            "requestdate",
            "time",
            "date"
        ]
        let negativePathTokens = ["update", "expect", "estimate", "income", "profit", "nav", "netvalue", "notice", "tip"]
        return positivePathTokens.contains { path.contains($0) }
            && !negativePathTokens.contains { path.contains($0) }
            && !leaf.value.contains("预计")
    }

    private static func explicitFundCode(in dictionary: [String: Any]) -> String? {
        let explicitCodeKeys = [
            "fundCode",
            "fundcode",
            "fund_code",
            "fundCd",
            "fundNo",
            "productCode",
            "productcode",
            "jjdm"
        ]
        for key in explicitCodeKeys {
            if let code = normalizedFundCode(from: dictionary[key]) {
                return code
            }
        }

        return nil
    }

    private static func conversionTargetFundCode(in dictionary: [String: Any]) -> String? {
        let explicitCodeKeys = [
            "sellFundCode",
            "sellProductCode",
            "targetFundCode",
            "targetProductCode",
            "toFundCode",
            "toProductCode"
        ]
        for key in explicitCodeKeys {
            if let code = normalizedFundCode(from: dictionary[key]) {
                return code
            }
        }
        return nil
    }

    private static func normalizedFundCode(from value: Any?) -> String? {
        guard let rawValue = stringValue(value) else { return nil }
        let digits = rawValue.filter(\.isNumber)
        guard digits.count == 6 else { return nil }
        return digits
    }

    private static func leafValues(in value: Any, path: String = "") -> [Leaf] {
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, value in
                leafValues(in: value, path: path.isEmpty ? key : "\(path).\(key)")
            }
        }

        if let array = value as? [Any] {
            return array.enumerated().flatMap { index, value in
                leafValues(in: value, path: "\(path)[\(index)]")
            }
        }

        guard let text = stringValue(value) else { return [] }
        return [Leaf(path: path, value: text)]
    }

    private static func normalizedDateAndTime(from value: String) -> (date: String, timeType: PositionTimeType?)? {
        let normalizedText: String
        if let timestampText = normalizedTimestampText(from: value) {
            normalizedText = timestampText
        } else {
            normalizedText = value
        }

        guard let date = normalizedDate(from: normalizedText) else {
            return nil
        }
        return (date, explicitTimeType(from: normalizedText) ?? clockTimeType(from: normalizedText))
    }

    private static func normalizedTimestampText(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^\d{10}(\d{3})?$"#, options: .regularExpression) != nil,
              let rawValue = Double(trimmed)
        else {
            return nil
        }

        let seconds = trimmed.count == 13 ? rawValue / 1_000 : rawValue
        guard seconds > 946_684_800,
              seconds < 4_102_444_800
        else {
            return nil
        }

        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func normalizedDate(from text: String) -> String? {
        let patterns = [
            #"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})"#,
            #"(\d{4})\.(\d{1,2})\.(\d{1,2})"#,
            #"\b(\d{4})(\d{2})(\d{2})\b"#
        ]

        for pattern in patterns {
            guard let captures = regexCaptures(pattern: pattern, in: text),
                  captures.count == 3,
                  let year = Int(captures[0]),
                  let month = Int(captures[1]),
                  let day = Int(captures[2])
            else { continue }

            let normalized = String(format: "%04d-%02d-%02d", year, month, day)
            if DateOnlyFormatter.parse(normalized) != nil {
                return normalized
            }
        }

        if let captures = regexCaptures(pattern: #"(?:^|[^0-9])(\d{1,2})[-/.月](\d{1,2})(?:日)?(?:\s+[0-2]?\d[:：][0-5]\d)"#, in: text),
           captures.count == 2,
           let month = Int(captures[0]),
           let day = Int(captures[1])
        {
            let year = Calendar.current.component(.year, from: .now)
            let normalized = String(format: "%04d-%02d-%02d", year, month, day)
            if DateOnlyFormatter.parse(normalized) != nil {
                return normalized
            }
        }

        return nil
    }

    private static func explicitTimeType(from text: String) -> PositionTimeType? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
        if normalized.contains("15:00前")
            || normalized.contains("15点前")
            || normalized.contains("三点前")
            || normalized.contains("下午3点前")
        {
            return .before15
        }

        if normalized.contains("15:00后")
            || normalized.contains("15点后")
            || normalized.contains("三点后")
            || normalized.contains("下午3点后")
        {
            return .after15
        }

        return nil
    }

    private static func clockTimeType(from text: String) -> PositionTimeType? {
        let normalized = text.replacingOccurrences(of: "：", with: ":")
        let hourText = regexCaptures(pattern: #"\b([01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?\b"#, in: normalized)?.first
            ?? regexCaptures(pattern: #"(^|[^0-9])([01]?\d|2[0-3])点(?:[0-5]\d分?)?"#, in: normalized)?.last
        guard let hourText,
              let hour = Int(hourText)
        else {
            return nil
        }
        return hour < 15 ? .before15 : .after15
    }

    private static func score(_ value: String, keywords: [String]) -> Int {
        let lowercased = value.lowercased()
        return keywords.reduce(0) { total, keyword in
            total + (lowercased.contains(keyword) ? 1 : 0)
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        case let value as [String: Any]:
            return stringValue(value["text"])
                ?? stringValue(value["subTitle"])
                ?? stringValue(value["title"])
                ?? stringValue(value["amt"])
        default:
            return nil
        }
    }

    private static func firstStringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = stringValue(dictionary[key]) {
                return value
            }
        }
        return nil
    }

    private static func firstNumericValue(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = numericValue(dictionary[key]) {
                return value
            }
        }
        return nil
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            guard value.isFinite else { return nil }
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return parseNumber(value)
        case let value as [String: Any]:
            return numericValue(value["amt"])
                ?? numericValue(value["text"])
                ?? numericValue(value["subTitle"])
                ?? numericValue(value["title"])
        default:
            return nil
        }
    }

    private static func parseNumber(_ value: String) -> Double? {
        let match = regexCaptures(pattern: #"([+-]?[0-9][0-9,]*(?:\.[0-9]+)?)"#, in: value)?.first ?? value
        let normalized = match
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "+", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized != "--",
              normalized != "-"
        else {
            return nil
        }
        return Double(normalized)
    }

    private static func jsonObject(from text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func regexCaptures(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1
        else {
            return nil
        }

        var captures: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            captures.append(String(text[range]))
        }
        return captures
    }
}
