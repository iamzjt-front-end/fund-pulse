import Foundation
import CryptoKit

enum JDFinanceSyncFingerprint {
    static func tradeDraft(_ draft: FundTradeDraft) -> String {
        return [
            "trade",
            draft.action.rawValue,
            normalizedCode(draft.code),
            draft.tradeDate,
            draft.tradeTimeType.rawValue,
            moneyPart(draft.amount),
            sharesPart(draft.shares)
        ].joined(separator: "|")
    }

    static func conversionDraft(_ draft: FundConversionDraft) -> String {
        [
            "conversion",
            normalizedCode(draft.fromCode),
            normalizedCode(draft.toCode),
            draft.tradeDate,
            draft.tradeTimeType.rawValue,
            sharesPart(draft.shares)
        ].joined(separator: "|")
    }

    static func tradeOrderRecord(_ record: JDFinanceTradeOrderRecord, fallbackCode: String? = nil) -> String {
        if let stableOrderKey = record.stableOrderKey, !stableOrderKey.isEmpty {
            return stableOrderKey
        }
        let composite = [
            "order",
            record.action?.rawValue ?? "unknown",
            normalizedCode(record.code ?? fallbackCode ?? ""),
            normalizedName(record.productName ?? ""),
            normalizedCode(record.conversionTargetCode ?? ""),
            normalizedName(record.conversionTargetName ?? ""),
            record.tradeDate ?? "",
            record.tradeTimeType?.rawValue ?? "",
            record.submittedAt ?? "",
            moneyPart(record.amount),
            sharesPart(record.shares)
        ].joined(separator: "|")
        return "jd-flow-" + sha256(composite)
    }

    static func stableOrderKey(rawOrderID: String?) -> String? {
        guard let rawOrderID = rawOrderID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawOrderID.isEmpty
        else {
            return nil
        }
        return "jd-order-" + sha256(rawOrderID)
    }

    static func accountKey(cookieHeader: String?) -> String? {
        guard let cookieHeader else { return nil }
        let stableCookieNames = ["pt_pin", "pin", "pwdt_id"]
        let pairs = cookieHeader.split(separator: ";")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2,
                  stableCookieNames.contains(parts[0].lowercased()),
                  !parts[1].isEmpty
            else {
                continue
            }
            return "jd-account-" + sha256(parts[1])
        }
        return nil
    }

    static func positionBaseline(code: String, syncedAt: Date) -> String {
        let value = [
            "position-baseline",
            normalizedCode(code),
            ISO8601DateFormatter().string(from: syncedAt)
        ].joined(separator: "|")
        return "jd-position-" + sha256(value)
    }

    private static func normalizedCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "转换-", with: "")
            .replacingOccurrences(of: "转入-", with: "")
            .replacingOccurrences(of: "转出-", with: "")
            .lowercased()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func moneyPart(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", (value * 100).rounded() / 100)
    }

    private static func sharesPart(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.6f", (value * 1_000_000).rounded() / 1_000_000)
    }
}
