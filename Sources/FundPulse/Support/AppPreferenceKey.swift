import Foundation

enum AppPreferenceKey {
    static let hideHeaderAmounts = "fundPulse.hideHeaderAmounts"
    static let dismissedPendingActivityNoticeIDs = "fundPulse.dismissedPendingActivityNoticeIDs"
}

extension Notification.Name {
    static let fundPulseAmountPrivacyDidChange = Notification.Name("fundPulseAmountPrivacyDidChange")
}
