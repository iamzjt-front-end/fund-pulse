import Foundation

enum OnboardingEligibility {
    static func shouldPresent(
        settings: AppSettings,
        settingsLoadOrigin: AppSettingsStore.LoadOrigin,
        portfolioLoadState: PortfolioStore.LoadState
    ) -> Bool {
        guard settingsLoadOrigin != .recoveredInvalid else { return false }
        guard (settings.completedOnboardingVersion ?? 0) < AppSettings.currentOnboardingVersion else {
            return false
        }

        guard case let .missingPlainData(hasLegacyStore) = portfolioLoadState else {
            return false
        }
        return !hasLegacyStore
    }
}
