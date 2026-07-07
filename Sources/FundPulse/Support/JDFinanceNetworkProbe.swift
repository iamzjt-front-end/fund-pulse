import Foundation
import Observation

enum JDFinanceNetworkProbeSource: String, Equatable {
    case urlSession = "URLSession"
    case webView = "WebView"
}

struct JDFinanceNetworkProbeEntry: Identifiable, Equatable {
    let id = UUID()
    var source: JDFinanceNetworkProbeSource
    var method: String
    var path: String
    var statusCode: Int?
    var topLevelKeys: [String]
    var fieldSummaries: [String]
    var createdAt: Date

    var isVisibleInCapturePanel: Bool {
        !fieldSummaries.isEmpty || isTradeOrderEndpoint
    }

    var isTradeOrderEndpoint: Bool {
        let normalized = path.lowercased()
        return normalized.contains("querytradeorderlist")
            || normalized.contains("querytradeorderbybusinesscodemenu")
    }
}

struct JDFinanceNetworkProbeTarget: Equatable {
    var code: String
    var name: String
    var amount: Double?
}

@MainActor
@Observable
final class JDFinanceNetworkProbe: @unchecked Sendable {
    private(set) var entries: [JDFinanceNetworkProbeEntry] = []
    private var targets: [JDFinanceNetworkProbeTarget] = []
    private let persistsEntriesToDisk: Bool

    init(persistsEntriesToDisk: Bool = false) {
        self.persistsEntriesToDisk = persistsEntriesToDisk
    }

    func clear() {
        entries = []
    }

    func setTargets(_ targets: [JDFinanceNetworkProbeTarget]) {
        self.targets = targets
    }

    func recordURLSession(
        endpoint: String,
        url: URL,
        method: String = "GET",
        statusCode: Int?,
        data: Data,
        now: Date = .now
    ) {
        let summary = Self.summary(from: data, targets: targets)
        appendEntry(
            source: .urlSession,
            method: method,
            path: "\(Self.sanitizedPath(from: url)) · \(endpoint)",
            statusCode: statusCode,
            topLevelKeys: summary.topLevelKeys,
            fieldSummaries: summary.fieldSummaries,
            now: now
        )
    }

    func recordWebViewPayload(_ payload: Any, now: Date = .now) {
        guard let dictionary = payload as? [String: Any] else { return }
        let url = (dictionary["url"] as? String).flatMap(URL.init(string:))
        let method = (dictionary["method"] as? String)?.uppercased() ?? "GET"
        let statusCode = dictionary["status"] as? Int
        let bodyText = dictionary["body"] as? String
        let requestBodyText = dictionary["requestBody"] as? String
        let responseSummary = Self.summary(fromBodyText: bodyText, targets: targets)
        let requestSummaries = Self.requestSummaries(fromBodyText: requestBodyText)

        appendEntry(
            source: .webView,
            method: method,
            path: Self.sanitizedPath(from: url),
            statusCode: statusCode,
            topLevelKeys: responseSummary.topLevelKeys,
            fieldSummaries: Self.mergedSummaries(requestSummaries + responseSummary.fieldSummaries),
            now: now
        )
    }

    private func appendEntry(
        source: JDFinanceNetworkProbeSource,
        method: String,
        path: String,
        statusCode: Int?,
        topLevelKeys: [String],
        fieldSummaries: [String],
        now: Date
    ) {
        let candidate = JDFinanceNetworkProbeEntry(
            source: source,
            method: method,
            path: path,
            statusCode: statusCode,
            topLevelKeys: topLevelKeys,
            fieldSummaries: fieldSummaries,
            createdAt: now
        )
        guard candidate.isVisibleInCapturePanel else { return }

        entries.append(candidate)
        if entries.count > 24 {
            entries.removeFirst(entries.count - 24)
        }
        if persistsEntriesToDisk {
            Self.appendDebugLog(candidate)
        }
    }

    private static func summary(
        from data: Data,
        targets: [JDFinanceNetworkProbeTarget]
    ) -> (topLevelKeys: [String], fieldSummaries: [String]) {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return ([], [])
        }
        return summary(fromJSONObject: object, targets: targets)
    }

    private static func summary(
        fromBodyText bodyText: String?,
        targets: [JDFinanceNetworkProbeTarget]
    ) -> (topLevelKeys: [String], fieldSummaries: [String]) {
        guard let bodyText,
              let data = bodyText.prefix(250_000).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return ([], [])
        }
        return summary(fromJSONObject: object, targets: targets)
    }

    private static func summary(
        fromJSONObject object: Any,
        targets: [JDFinanceNetworkProbeTarget]
    ) -> (topLevelKeys: [String], fieldSummaries: [String]) {
        let topLevelKeys: [String]
        if let dictionary = object as? [String: Any] {
            let keys = dictionary.keys
                .filter { !isSensitivePath($0) }
                .sorted()
            topLevelKeys = Array(keys.prefix(8))
        } else {
            topLevelKeys = []
        }

        var summaries = tradeOrderSummaries(in: object, targets: targets)
        if !summaries.isEmpty {
            return (topLevelKeys, summaries)
        }

        var seen = Set<String>()
        for summary in summaries {
            seen.insert(summary)
        }

        for leaf in leafValues(in: object) {
            guard !isSensitivePath(leaf.path),
                  let summary = safeSummary(for: leaf)
            else { continue }

            if seen.insert(summary).inserted {
                summaries.append(summary)
            }
            if summaries.count >= 12 { break }
        }

        return (topLevelKeys, summaries)
    }

    private static func requestSummaries(fromBodyText bodyText: String?) -> [String] {
        guard let object = requestJSONObject(fromBodyText: bodyText) else {
            return []
        }

        let importantKeys: Set<String> = [
            "businesscode",
            "pageshowtype",
            "pageno",
            "pagetype",
            "title",
            "busproductid",
            "productid",
            "productcode",
            "fundcode",
            "ordercreatestartdate",
            "ordercreateenddate"
        ]
        var summaries: [String] = []
        var seen = Set<String>()

        for leaf in leafValues(in: object) {
            let normalizedKey = leaf.key.lowercased()
            guard importantKeys.contains(normalizedKey),
                  !isSensitivePath(leaf.path)
            else { continue }

            let value = leaf.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }

            let summary: String
            if normalizedKey == "busproductid" || normalizedKey == "productid" {
                if let code = JDFinanceFundCodeMapper.inferCode(from: value) {
                    summary = "请求.\(shortFieldName(leaf.path)): \(value)(\(code))"
                } else {
                    summary = "请求.\(shortFieldName(leaf.path)): \(abbreviated(value))"
                }
            } else if normalizedKey == "productcode" || normalizedKey == "fundcode" {
                summary = "请求.\(shortFieldName(leaf.path)): \(fundCode(from: value) ?? abbreviated(value))"
            } else if let date = normalizedDate(from: value),
                      normalizedKey == "ordercreatestartdate" || normalizedKey == "ordercreateenddate"
            {
                summary = "请求.\(shortFieldName(leaf.path)): \(date)"
            } else {
                summary = "请求.\(shortFieldName(leaf.path)): \(abbreviated(value))"
            }

            if seen.insert(summary).inserted {
                summaries.append(summary)
            }
            if summaries.count >= 10 { break }
        }

        return summaries
    }

    private static func requestJSONObject(fromBodyText bodyText: String?) -> Any? {
        guard let bodyText else { return nil }
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let object = jsonObject(from: trimmed) {
            return object
        }

        if let components = URLComponents(string: "?\(trimmed)"),
           let reqData = components.queryItems?.first(where: { $0.name == "reqData" })?.value
        {
            return jsonObject(from: reqData)
        }

        return nil
    }

    private static func mergedSummaries(_ summaries: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for summary in summaries where seen.insert(summary).inserted {
            result.append(summary)
            if result.count >= 12 { break }
        }
        return result
    }

    private static func tradeOrderSummaries(
        in object: Any,
        targets: [JDFinanceNetworkProbeTarget]
    ) -> [String] {
        var rows = tradeOrderRows(in: object)
        if !targets.isEmpty {
            let matchedRows = rows.filter { row in
                targets.contains { target in
                    tradeOrderRow(row, matches: target)
                }
            }
            if !matchedRows.isEmpty {
                rows = matchedRows
            }
        }

        var summaries: [String] = []
        var seen = Set<String>()
        for row in rows.prefix(12) {
            guard let summary = tradeOrderSummary(row),
                  seen.insert(summary).inserted
            else { continue }
            summaries.append(summary)
            for leaf in leafValues(in: row) {
                guard !isSensitivePath(leaf.path),
                      let fieldSummary = safeSummary(for: leaf)
                else { continue }
                let detail = "交易字段.\(fieldSummary)"
                if seen.insert(detail).inserted {
                    summaries.append(detail)
                }
                if summaries.count >= 12 { break }
            }
            if summaries.count >= 12 { break }
        }
        return summaries
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
        let hasTiming = firstTradeTiming(in: dictionary) != nil
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

    private static func tradeOrderRow(
        _ row: [String: Any],
        matches target: JDFinanceNetworkProbeTarget
    ) -> Bool {
        if let code = explicitFundCode(in: row), code == target.code {
            return true
        }

        guard let productName = firstStringValue(
            in: row,
            keys: ["productName", "sellProductName", "fundName", "productFullName", "productTitle", "skuName", "name"]
        ) else {
            return false
        }

        let rowName = canonicalName(productName)
        let targetName = canonicalName(target.name)
        return rowName.count >= 6
            && targetName.count >= 6
            && (rowName.contains(targetName) || targetName.contains(rowName))
    }

    private static func tradeOrderSummary(_ row: [String: Any]) -> String? {
        let code = explicitFundCode(in: row)
        let productName = firstStringValue(
            in: row,
            keys: ["productName", "sellProductName", "fundName", "productFullName", "productTitle", "skuName", "name"]
        )
        let amount = firstNumericValue(
            in: row,
            keys: tradeAmountKeys
        )
        let timing = firstTradeTiming(in: row)
        let status = firstStringValue(
            in: row,
            keys: ["statusName", "statusDesc", "statusText", "statusCode", "orderStatus", "orderStatusName"]
        )
        let type = firstStringValue(
            in: row,
            keys: ["tradeTypeName", "tradeTypeCode", "tradeType", "tradeTypeDesc", "orderTypeName"]
        )

        guard code != nil || productName != nil || amount != nil || timing != nil else {
            return nil
        }

        var parts: [String] = ["交易记录"]
        if let code { parts.append(code) }
        if let productName { parts.append(abbreviated(productName)) }
        if let amount { parts.append(MoneyFormatter.plainMoney(amount)) }
        if let timing {
            if let timeType = timing.timeType {
                parts.append("\(timing.date) \(timeType.title)")
            } else {
                parts.append(timing.date)
            }
        }
        if let status { parts.append(abbreviated(status)) }
        if let type { parts.append(abbreviated(type)) }
        return parts.joined(separator: " · ")
    }

    private struct Leaf {
        var path: String
        var key: String
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
        return [Leaf(path: path, key: path.components(separatedBy: ".").last ?? path, value: text)]
    }

    private static func safeSummary(for leaf: Leaf) -> String? {
        let path = leaf.path.lowercased()
        let value = leaf.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let code = fundCode(from: value),
           path.contains("code") || path.contains("fund") || value.range(of: #"^\d{6}$"#, options: .regularExpression) != nil
        {
            return "\(shortFieldName(leaf.path)): \(code)"
        }

        if let date = normalizedDate(from: value),
           isTradeTimingPath(path) || value.contains("交易日") || value.contains("下单时间") || value.contains("申请时间")
        {
            if let timeType = explicitTimeType(from: value) ?? clockTimeType(from: value) {
                return "\(shortFieldName(leaf.path)): \(date) \(timeType.title)"
            }
            return "\(shortFieldName(leaf.path)): \(date)"
        }

        if let timestampDate = normalizedTimestampDate(from: value),
           isTradeTimingPath(path)
        {
            if let timeType = clockTimeType(from: timestampDate.rawText) {
                return "\(shortFieldName(leaf.path)): \(timestampDate.date) \(timeType.title)"
            }
            return "\(shortFieldName(leaf.path)): \(timestampDate.date)"
        }

        if let timeType = explicitTimeType(from: value) ?? clockTimeType(from: value),
           isTradeTimingPath(path) || value.contains("15:00")
        {
            return "\(shortFieldName(leaf.path)): \(timeType.title)"
        }

        if isProductNamePath(path) {
            return "\(shortFieldName(leaf.path)): \(abbreviated(value))"
        }

        if isAmountPath(path) || value.contains("元") || value.contains("合计") {
            if let amount = numericValue(value) {
                return "\(shortFieldName(leaf.path)): \(MoneyFormatter.plainMoney(amount))"
            }
        }

        if isStatusPath(path) || containsTradeStatus(value) {
            return "\(shortFieldName(leaf.path)): \(abbreviated(value))"
        }

        return nil
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
            "jjdm",
            "code"
        ]
        for key in explicitCodeKeys {
            if let code = fundCode(from: stringValue(dictionary[key]) ?? "") {
                return code
            }
        }

        let productIDKeys = ["productId", "productID", "skuId", "skuID", "sku"]
        for key in productIDKeys {
            if let rawValue = stringValue(dictionary[key]),
               let code = JDFinanceFundCodeMapper.inferCode(from: rawValue)
            {
                return code
            }
        }

        return nil
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
            if let text = stringValue(dictionary[key]),
               let value = numericValue(text)
            {
                return value
            }
            if let number = dictionary[key] as? NSNumber {
                return number.doubleValue
            }
        }
        return nil
    }

    private static func firstTradeTiming(in dictionary: [String: Any]) -> (date: String, timeType: PositionTimeType?)? {
        let preferredLeaves = leafValues(in: dictionary).filter { leaf in
            isTradeTimingPath(leaf.path.lowercased())
        }

        for leaf in preferredLeaves {
            if let timing = normalizedDateAndTime(from: leaf.value) {
                return timing
            }
        }
        return nil
    }

    private static func normalizedDateAndTime(from value: String) -> (date: String, timeType: PositionTimeType?)? {
        let normalizedText = normalizedTimestampDate(from: value)?.rawText ?? value
        guard let date = normalizedDate(from: normalizedText) else {
            return nil
        }
        return (date, explicitTimeType(from: normalizedText) ?? clockTimeType(from: normalizedText))
    }

    private static func canonicalName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "中证", with: "")
            .lowercased()
    }

    private static func sanitizedPath(from url: URL?) -> String {
        guard let url else { return "--" }
        let host = url.host() ?? ""
        return host.isEmpty ? url.path : "\(host)\(url.path)"
    }

    private static func shortFieldName(_ path: String) -> String {
        path
            .split(separator: ".")
            .suffix(2)
            .joined(separator: ".")
            .replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
    }

    private static func abbreviated(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return "\(trimmed.prefix(80))..."
    }

    private static func isSensitivePath(_ path: String) -> Bool {
        let normalized = path.lowercased()
        let sensitiveTokens = [
            "cookie",
            "token",
            "orderid",
            "orderno",
            "order_id",
            "order_no",
            "extjson",
            "pt_key",
            "pt_pin",
            "pin",
            "wskey",
            "thor",
            "eid",
            "fp",
            "uuid",
            "encrypt",
            "sign"
        ]
        return sensitiveTokens.contains { normalized.contains($0) }
    }

    private static func isAmountPath(_ path: String) -> Bool {
        (path.contains("amount") || path.contains("amt") || path.contains("money") || path.contains("balance"))
            && !path.contains("income")
            && !path.contains("profit")
            && !path.contains("rate")
            && !path.contains("share")
    }

    private static func isProductNamePath(_ path: String) -> Bool {
        path.contains("productname")
            || path.contains("fundname")
            || path.contains("sellproductname")
            || path.contains("buyproductname")
    }

    private static func isStatusPath(_ path: String) -> Bool {
        path.contains("status") || path.contains("state") || path.contains("type") || path.contains("desc") || path.contains("tip")
    }

    private static func isTradeTimingPath(_ path: String) -> Bool {
        let positive = ["trade", "apply", "accept", "create", "deal", "entrust", "submit", "business", "biz", "time", "date"]
        let negative = ["update", "expect", "estimate", "income", "profit", "nav", "netvalue", "notice", "tip"]
        return positive.contains { path.contains($0) }
            && !negative.contains { path.contains($0) }
    }

    private static func containsTradeStatus(_ value: String) -> Bool {
        value.contains("买入")
            || value.contains("卖出")
            || value.contains("申购")
            || value.contains("赎回")
            || value.contains("交易中")
            || value.contains("确认")
            || value.contains("处理中")
    }

    private static func fundCode(from value: String) -> String? {
        let digits = value.filter(\.isNumber)
        return digits.count == 6 ? digits : nil
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

    private static func normalizedTimestampDate(from text: String) -> (date: String, rawText: String)? {
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
        let rawText = formatter.string(from: date)
        return (String(rawText.prefix(10)), rawText)
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

    private static func appendDebugLog(_ entry: JDFinanceNetworkProbeEntry) {
        do {
            let url = debugLogURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            rotateDebugLogIfNeeded(at: url)

            let status = entry.statusCode.map(String.init) ?? "--"
            let keys = entry.topLevelKeys.isEmpty ? "" : " keys=\(entry.topLevelKeys.joined(separator: ","))"
            let fields = entry.fieldSummaries.isEmpty ? "" : " | \(entry.fieldSummaries.joined(separator: " | "))"
            let line = "\(debugTimestamp(entry.createdAt)) \(entry.source.rawValue) \(entry.method) \(entry.path) \(status)\(keys)\(fields)\n"
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url)
            {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Debug capture should never affect syncing.
        }
    }

    private static func rotateDebugLogIfNeeded(at url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 1_000_000
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func debugLogURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "fund-pulse", directoryHint: .isDirectory)
            .appending(path: "jd-network-probe.log")
    }

    private static func debugTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
