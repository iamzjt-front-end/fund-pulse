import Foundation

enum JDFinanceTradeOrderBatcher {
    private struct BatchKey: Hashable {
        var identity: String
        var action: JDFinancePendingTradeAction
        var tradeDate: String
        var tradeTimeType: PositionTimeType
        var submittedAt: String
    }

    static func logicalRecords(_ records: [JDFinanceTradeOrderRecord]) -> [JDFinanceTradeOrderRecord] {
        let groupedIndices = Dictionary(grouping: records.indices) { index in
            batchKey(for: records[index])
        }
        var consumedIndices = Set<Int>()
        var result: [JDFinanceTradeOrderRecord] = []
        result.reserveCapacity(records.count)

        for index in records.indices {
            guard !consumedIndices.contains(index) else { continue }
            guard let key = batchKey(for: records[index]),
                  let indices = groupedIndices[key],
                  indices.count > 1,
                  let merged = combinedRecord(indices.map { records[$0] })
            else {
                result.append(records[index])
                continue
            }

            consumedIndices.formUnion(indices)
            result.append(merged)
        }

        return result
    }

    private static func batchKey(for record: JDFinanceTradeOrderRecord) -> BatchKey? {
        guard record.action == .buy,
              record.effectiveStatus == .pending || record.effectiveStatus == .succeeded,
              let tradeDate = record.tradeDate,
              let tradeTimeType = record.tradeTimeType,
              let submittedAt = normalizedSubmittedAt(record.submittedAt),
              let identity = normalizedIdentity(for: record),
              record.amount.map({ $0 > 0 }) == true
        else {
            return nil
        }

        return BatchKey(
            identity: identity,
            action: .buy,
            tradeDate: tradeDate,
            tradeTimeType: tradeTimeType,
            submittedAt: submittedAt
        )
    }

    static func combinedRecord(_ records: [JDFinanceTradeOrderRecord]) -> JDFinanceTradeOrderRecord? {
        guard records.count > 1,
              let key = records.first.flatMap(batchKey(for:)),
              records.dropFirst().allSatisfy({ batchKey(for: $0) == key })
        else {
            return nil
        }
        let codes = Set(records.compactMap { normalizedCode($0.code) })
        let amounts = records.compactMap(\.amount)
        guard codes.count <= 1,
              amounts.count == records.count,
              amounts.allSatisfy({ $0 > 0 }),
              Set(amounts).count > 1
        else {
            return nil
        }

        let sourceOrderKeys = Array(Set(records.flatMap(sourceOrderKeys))).sorted()
        guard sourceOrderKeys.count > 1 else { return nil }

        let statuses = records.map(\.effectiveStatus)
        let status: JDFinanceTradeOrderStatus = statuses.allSatisfy { $0 == .succeeded }
            ? .succeeded
            : .pending
        let shares: Double? = records.allSatisfy({ $0.shares != nil })
            ? records.compactMap(\.shares).reduce(0, +)
            : nil
        let code = codes.first
        let resolvedRecord = records.first { $0.isCodeResolved }

        return JDFinanceTradeOrderRecord(
            stableOrderKey: JDFinanceSyncFingerprint.logicalTradeOrderGroup(
                sourceOrderKeys: sourceOrderKeys
            ),
            sourceOrderKeys: sourceOrderKeys,
            code: code,
            codeResolution: resolvedRecord?.codeResolution ?? .unresolved,
            productName: records.compactMap(\.productName).first,
            action: .buy,
            amount: amounts.reduce(0, +),
            shares: shares,
            tradeDate: records.first?.tradeDate,
            tradeTimeType: records.first?.tradeTimeType,
            submittedAt: key.submittedAt,
            status: status,
            statusCode: commonValue(records.compactMap(\.statusCode)),
            statusText: commonValue(records.compactMap(\.statusText))
        )
    }

    private static func sourceOrderKeys(for record: JDFinanceTradeOrderRecord) -> [String] {
        if !record.sourceOrderKeys.isEmpty {
            return record.sourceOrderKeys
        }
        if let stableOrderKey = record.stableOrderKey, !stableOrderKey.isEmpty {
            return [stableOrderKey]
        }
        return [JDFinanceSyncFingerprint.tradeOrderRecord(record)]
    }

    private static func normalizedIdentity(for record: JDFinanceTradeOrderRecord) -> String? {
        if let name = record.productName {
            let normalizedName = name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "转换-", with: "")
                .replacingOccurrences(of: "转入-", with: "")
                .replacingOccurrences(of: "转出-", with: "")
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .replacingOccurrences(of: "（", with: "(")
                .replacingOccurrences(of: "）", with: ")")
                .lowercased()
            if !normalizedName.isEmpty {
                return "name:\(normalizedName)"
            }
        }
        return normalizedCode(record.code).map { "code:\($0)" }
    }

    private static func normalizedCode(_ code: String?) -> String? {
        let value = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func normalizedSubmittedAt(_ submittedAt: String?) -> String? {
        let value = submittedAt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func commonValue<Value: Hashable>(_ values: [Value]) -> Value? {
        guard let first = values.first,
              values.allSatisfy({ $0 == first })
        else {
            return nil
        }
        return first
    }
}
