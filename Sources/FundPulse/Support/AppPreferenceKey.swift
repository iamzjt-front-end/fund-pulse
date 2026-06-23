import Foundation

enum AppPreferenceKey {
    static let hideHeaderAmounts = "fundPulse.hideHeaderAmounts"
}

extension Notification.Name {
    static let fundPulseAmountPrivacyDidChange = Notification.Name("fundPulseAmountPrivacyDidChange")
}
