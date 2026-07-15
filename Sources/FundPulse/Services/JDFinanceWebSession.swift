import Foundation
import WebKit

protocol JDFinanceCookieStorage: AnyObject {
    var cookies: [HTTPCookie]? { get }

    func deleteCookie(_ cookie: HTTPCookie)
}

extension HTTPCookieStorage: JDFinanceCookieStorage {}

enum JDFinanceCookieHeaderFilter {
    private static let forwardedNames: Set<String> = [
        "pt_key",
        "pt_pin",
        "pin",
        "pwdt_id",
        "thor",
        "wskey"
    ]
    private static let authenticationNames: Set<String> = [
        "pt_key",
        "thor",
        "wskey"
    ]
    private static let stableIdentityNames: Set<String> = [
        "pt_pin",
        "pin",
        "pwdt_id"
    ]

    static func scopedHeader(from cookieHeader: String?) -> String? {
        guard let cookieHeader else { return nil }
        var seenNames = Set<String>()
        let pairs = cookieHeader.split(separator: ";").compactMap { segment -> String? in
            let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = name.lowercased()
            guard forwardedNames.contains(normalizedName),
                  !value.isEmpty,
                  seenNames.insert(normalizedName).inserted
            else {
                return nil
            }
            return "\(name)=\(value)"
        }
        let header = pairs.joined(separator: "; ")
        return hasAuthenticationCookie(header) ? header : nil
    }

    static func scopedHeader(from cookies: [HTTPCookie], now: Date = .now) -> String? {
        let rootDomainCookies = cookies.filter { cookie in
            let domain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            guard domain == "jd.com" else { return false }
            guard cookie.path == "/" else { return false }
            if let expiresDate = cookie.expiresDate, expiresDate <= now { return false }
            return true
        }
        let rawHeader = rootDomainCookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return scopedHeader(from: rawHeader)
    }

    static func preferredScopedHeader(
        webKitCookies: [HTTPCookie],
        sharedCookies: [HTTPCookie],
        now: Date = .now
    ) -> String? {
        for cookies in [webKitCookies, sharedCookies] {
            guard let header = scopedHeader(from: cookies, now: now),
                  isSynchronizableHeader(header)
            else {
                continue
            }
            return header
        }
        return nil
    }

    static func hasAuthenticationCookie(_ cookieHeader: String?) -> Bool {
        !cookieNamesWithValues(in: cookieHeader).isDisjoint(with: authenticationNames)
    }

    static func hasStableIdentityCookie(_ cookieHeader: String?) -> Bool {
        !cookieNamesWithValues(in: cookieHeader).isDisjoint(with: stableIdentityNames)
    }

    static func isSynchronizableHeader(_ cookieHeader: String?) -> Bool {
        hasAuthenticationCookie(cookieHeader) && hasStableIdentityCookie(cookieHeader)
    }

    private static func cookieNamesWithValues(in cookieHeader: String?) -> Set<String> {
        guard let cookieHeader else { return [] }
        let names = Set(cookieHeader.split(separator: ";").compactMap { segment -> String? in
            let parts = segment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        return names
    }
}

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
                let header = JDFinanceCookieHeaderFilter.preferredScopedHeader(
                    webKitCookies: cookies,
                    sharedCookies: HTTPCookieStorage.shared.cookies ?? []
                )
                let resolvedHeader = header ?? cachedCookieHeader
                if JDFinanceCookieHeaderFilter.isSynchronizableHeader(resolvedHeader) {
                    cachedCookieHeader = resolvedHeader
                    continuation.resume(returning: resolvedHeader)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func rememberCookieHeader(_ cookieHeader: String?) {
        guard let scopedHeader = JDFinanceCookieHeaderFilter.scopedHeader(from: cookieHeader),
              JDFinanceCookieHeaderFilter.isSynchronizableHeader(scopedHeader)
        else { return }
        cachedCookieHeader = scopedHeader
    }

    static func clearSession() async {
        cachedCookieHeader = nil
        clearJDCookies(in: HTTPCookieStorage.shared)
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

    static func clearJDCookies(in cookieStorage: any JDFinanceCookieStorage) {
        for cookie in cookieStorage.cookies ?? [] where isJDDomain(cookie.domain) {
            cookieStorage.deleteCookie(cookie)
        }
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

    static func isJDDomain(_ domain: String) -> Bool {
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
