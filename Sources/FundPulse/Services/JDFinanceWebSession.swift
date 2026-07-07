import Foundation
import WebKit

@MainActor
enum JDFinanceWebSession {
    private static var cachedCookieHeader: String?
    private static let authenticationCookieNames: Set<String> = [
        "pt_key",
        "thor",
        "wskey"
    ]

    static let loginURL = URL(
        string: "https://plogin.m.jd.com/login/login?qqlogin=false&wxlogin=false&appid=2508&source=JDJR_PC&returnurl=https%3A%2F%2Fjdjr.jd.com%2F"
    )!
    static let holdingsURL = URL(string: "https://jdjr.jd.com/")!
    static let holdingsPCURL = URL(string: "https://roma.jd.com/fund/hold/list/pc/")!
    static let tradeOrderURL = URL(
        string: "https://roma.jd.com/wealth/tradeorder/list?pageShowType=1&businessCode=FUND&pageShowTitle=%E5%9F%BA%E9%87%91%E4%BA%A4%E6%98%93"
    )!

    static func isLoginReturnURL(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return host == "jdjr.jd.com"
    }

    static func didCompleteLoginNavigation(url: URL?, cookieHeader: String?) -> Bool {
        guard isLoginReturnURL(url) else { return false }
        return hasUsableCookieHeader(cookieHeader)
    }

    static func hasUsableCookieHeader(_ cookieHeader: String?) -> Bool {
        let cookieNames = cookieNamesWithValues(in: cookieHeader)
        return !cookieNames.isDisjoint(with: authenticationCookieNames)
    }

    static func cookieHeader() async -> String? {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let header = (cookies + (HTTPCookieStorage.shared.cookies ?? []))
                    .filter(isJDCookie)
                    .sorted { lhs, rhs in
                        if lhs.domain == rhs.domain {
                            return lhs.name < rhs.name
                        }
                        return lhs.domain < rhs.domain
                    }
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                let resolvedHeader = hasUsableCookieHeader(header) ? header : cachedCookieHeader
                if hasUsableCookieHeader(resolvedHeader) {
                    cachedCookieHeader = resolvedHeader
                    continuation.resume(returning: resolvedHeader)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func rememberCookieHeader(_ cookieHeader: String?) {
        guard hasUsableCookieHeader(cookieHeader) else { return }
        cachedCookieHeader = cookieHeader
    }

    static func clearSession() async {
        cachedCookieHeader = nil
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                let jdRecords = records.filter { isJDRecordName($0.displayName) }
                guard !jdRecords.isEmpty else {
                    continuation.resume()
                    return
                }
                dataStore.removeData(ofTypes: dataTypes, for: jdRecords) {
                    continuation.resume()
                }
            }
        }
    }

    private static func isJDCookie(_ cookie: HTTPCookie) -> Bool {
        isJDDomain(cookie.domain)
    }

    private static func cookieNamesWithValues(in cookieHeader: String?) -> Set<String> {
        guard let cookieHeader else { return [] }

        let pairs = cookieHeader.split(separator: ";").compactMap { segment -> (String, String)? in
            let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { return nil }
            return (name, value)
        }

        return Set(pairs.map(\.0))
    }

    private static func isJDRecordName(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized.contains("jd")
            || normalized.contains("360buy")
            || normalized.contains("jdpay")
    }

    private static func isJDDomain(_ domain: String) -> Bool {
        let normalized = domain
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        return normalized == "jd.com"
            || normalized.hasSuffix(".jd.com")
            || normalized == "360buy.com"
            || normalized.hasSuffix(".360buy.com")
            || normalized == "jdpay.com"
            || normalized.hasSuffix(".jdpay.com")
    }
}
