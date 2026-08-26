import Foundation

enum FundUpdatePresentationPolicy {
    static func showsOfficialUpdateMarker(
        for fund: FundPosition,
        accountKind: PortfolioAccountKind
    ) -> Bool {
        accountKind == .offExchange && fund.isUpdated
    }
}
