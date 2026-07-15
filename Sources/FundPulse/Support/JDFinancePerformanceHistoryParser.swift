import Foundation
import CoreFoundation

enum JDFinancePerformanceHistoryParser {
    static func parse(data: Data) throws -> [JDFinancePerformanceDay] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }

        guard let envelope = object as? [String: Any] else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        try validateOuterEnvelope(envelope)

        guard let resultData = envelope["resultData"] as? [String: Any] else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        try validateInnerEnvelope(resultData)

        guard let payloadValue = resultData["data"] else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        guard let payload = payloadValue as? [String: Any] else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        guard let mapValue = payload["incomeRateVoMap"] else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        if mapValue is NSNull {
            return []
        }
        guard let map = mapValue as? [String: Any] else {
            throw JDFinancePerformanceHistoryError.invalidResponse
        }

        var days: [JDFinancePerformanceDay] = []
        days.reserveCapacity(map.count)
        for (dateKey, rowValue) in map {
            guard isValidDate(dateKey),
                  let row = rowValue as? [String: Any],
                  let incomeAmount = requiredNumber(row["incomeAmount"])
            else {
                throw JDFinancePerformanceHistoryError.invalidResponse
            }

            if let incomeDateValue = row["incomeDate"], !(incomeDateValue is NSNull) {
                guard let incomeDate = incomeDateValue as? String,
                      incomeDate == dateKey
                else {
                    throw JDFinancePerformanceHistoryError.invalidResponse
                }
            }

            let incomeRate: Double?
            if let value = row["incomeRate"], !(value is NSNull) {
                guard let parsed = optionalNumber(value) else {
                    throw JDFinancePerformanceHistoryError.invalidResponse
                }
                incomeRate = parsed
            } else {
                incomeRate = nil
            }

            days.append(
                JDFinancePerformanceDay(
                    date: dateKey,
                    incomeAmount: incomeAmount,
                    incomeRate: incomeRate
                )
            )
        }
        return days.sorted { $0.date < $1.date }
    }

    private static func validateOuterEnvelope(_ envelope: [String: Any]) throws {
        let message = message(in: envelope)
        if isLoginFailure(code: envelope["resultCode"], message: message) {
            throw JDFinancePerformanceHistoryError.notLoggedIn
        }

        guard let resultCode = integerValue(envelope["resultCode"]), resultCode == 0 else {
            if let message, !message.isEmpty {
                throw JDFinancePerformanceHistoryError.server(message)
            }
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        if let success = envelope["success"] as? Bool, !success {
            throw JDFinancePerformanceHistoryError.server(message ?? "京东历史收益接口请求失败")
        }
    }

    private static func validateInnerEnvelope(_ envelope: [String: Any]) throws {
        let message = message(in: envelope)
        if isLoginFailure(code: envelope["code"], message: message) {
            throw JDFinancePerformanceHistoryError.notLoggedIn
        }

        guard let code = stringValue(envelope["code"]), code == "0000" else {
            if let message, !message.isEmpty {
                throw JDFinancePerformanceHistoryError.server(message)
            }
            throw JDFinancePerformanceHistoryError.invalidResponse
        }
        if let success = envelope["success"] as? Bool, !success {
            throw JDFinancePerformanceHistoryError.server(message ?? "京东历史收益接口请求失败")
        }
    }

    private static func isLoginFailure(code: Any?, message: String?) -> Bool {
        let normalizedCode = stringValue(code)?.lowercased() ?? ""
        if ["3", "0003", "1003", "not_login", "notlogin", "login_expired"].contains(normalizedCode) {
            return true
        }

        let normalizedMessage = message?.lowercased() ?? ""
        return normalizedMessage.contains("请先登录")
            || normalizedMessage.contains("登录状态")
            || normalizedMessage.contains("重新登录")
            || normalizedMessage.contains("not login")
            || normalizedMessage.contains("login expired")
    }

    private static func message(in object: [String: Any]) -> String? {
        for key in ["message", "resultMsg", "msg"] {
            if let value = object[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return value
            }
        }
        return nil
    }

    private static func isValidDate(_ value: String) -> Bool {
        guard let date = DateOnlyFormatter.parse(value) else { return false }
        return DateOnlyFormatter.string(from: date) == value
    }

    private static func requiredNumber(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        return optionalNumber(value)
    }

    private static func optionalNumber(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            guard !isBooleanNumber(number) else { return nil }
            let parsed = number.doubleValue
            return parsed.isFinite ? parsed : nil
        }
        guard let string = value as? String else { return nil }
        let normalized = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard !normalized.isEmpty,
              normalized != "--",
              let parsed = Double(normalized),
              parsed.isFinite
        else {
            return nil
        }
        return parsed
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            guard !isBooleanNumber(number) else { return nil }
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            guard !isBooleanNumber(number) else { return nil }
            return number.stringValue
        }
        return nil
    }

    private static func isBooleanNumber(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
