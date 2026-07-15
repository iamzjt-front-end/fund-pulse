enum OnboardingOrigin: Equatable {
    case firstLaunch
    case settings
}

enum PrivacyDisclaimerOrigin: Equatable {
    case settings
    case onboarding(OnboardingOrigin)
}

enum ChildPanelRoute: Equatable {
    case settings
    case privacyDisclaimer(origin: PrivacyDisclaimerOrigin)
    case onboarding(origin: OnboardingOrigin)
    case sampleExperience(origin: OnboardingOrigin)
    case portfolioPerformance
    case jdFinancePerformanceSync
    case jdFinanceSync
    case portfolioBreakdown
    case todayIncomeRanking(IncomeRankingMetric)
    case addFund
    case onboardingAddFund(origin: OnboardingOrigin)
    case fundDetail(fundCode: String)
    case fundDailyIncome(fundCode: String)
    case tradeRecords(fundCode: String)
    case buyFund(fundCode: String)
    case sellFund(fundCode: String)
    case convertFund(fundCode: String)
    case editTradeRecord(fundCode: String, recordID: String)
    case editConversion(sourceFundCode: String, recordID: String, returnFundCode: String)
    case editPendingTradeRecord(fundCode: String, recordID: String)
    case editPendingConversion(fundCode: String, recordID: String)
    case editFund(fundCode: String)

    var selectedFundCode: String? {
        switch self {
        case .fundDetail(let fundCode),
             .fundDailyIncome(let fundCode),
             .tradeRecords(let fundCode),
             .buyFund(let fundCode),
             .sellFund(let fundCode),
             .convertFund(let fundCode),
             .editTradeRecord(let fundCode, _),
             .editPendingTradeRecord(let fundCode, _),
             .editPendingConversion(let fundCode, _),
             .editFund(let fundCode):
            fundCode
        case .editConversion(let sourceFundCode, _, _):
            sourceFundCode
        case .settings, .privacyDisclaimer, .onboarding, .sampleExperience,
             .portfolioPerformance, .jdFinancePerformanceSync, .jdFinanceSync, .portfolioBreakdown,
             .todayIncomeRanking, .addFund, .onboardingAddFund:
            nil
        }
    }

    var ownsJDFinanceLoginPanel: Bool {
        switch self {
        case .jdFinanceSync, .jdFinancePerformanceSync:
            true
        default:
            false
        }
    }
}

enum ChildPanelRouteDisposition: Equatable {
    case available
    case redirect(ChildPanelRoute)
    case close
}

enum ChildPanelRouteResolver {
    static func fund(for route: ChildPanelRoute, in snapshot: PortfolioSnapshot) -> FundPosition? {
        guard let code = route.selectedFundCode else { return nil }
        return snapshot.funds.first { $0.code == code }
    }

    static func record(for route: ChildPanelRoute, in snapshot: PortfolioSnapshot) -> FundTradeRecord? {
        guard let recordID = recordID(for: route) else { return nil }
        return snapshot.tradeRecords?.first { $0.id == recordID }
    }

    static func tradeRecords(
        for route: ChildPanelRoute,
        in snapshot: PortfolioSnapshot
    ) -> [FundTradeRecord]? {
        guard case .tradeRecords(let fundCode) = route else { return nil }
        return (snapshot.tradeRecords ?? []).filter { $0.code == fundCode }
    }

    static func disposition(
        for route: ChildPanelRoute,
        in snapshot: PortfolioSnapshot
    ) -> ChildPanelRouteDisposition {
        if let fundCode = route.selectedFundCode,
           !snapshot.funds.contains(where: { $0.code == fundCode }) {
            return .close
        }

        if case .editConversion(_, _, let returnFundCode) = route,
           !snapshot.funds.contains(where: { $0.code == returnFundCode }) {
            return .close
        }

        if let recordID = recordID(for: route),
           !((snapshot.tradeRecords ?? []).contains { $0.id == recordID }) {
            guard let returnFundCode = returnFundCode(for: route) else {
                return .close
            }
            return .redirect(.tradeRecords(fundCode: returnFundCode))
        }

        return .available
    }

    private static func recordID(for route: ChildPanelRoute) -> String? {
        switch route {
        case .editTradeRecord(_, let recordID),
             .editPendingTradeRecord(_, let recordID),
             .editPendingConversion(_, let recordID):
            recordID
        case .editConversion(_, let recordID, _):
            recordID
        case .settings, .privacyDisclaimer, .onboarding, .sampleExperience,
             .portfolioPerformance, .jdFinancePerformanceSync, .jdFinanceSync, .portfolioBreakdown,
             .todayIncomeRanking, .addFund, .onboardingAddFund,
             .fundDetail, .fundDailyIncome, .tradeRecords, .buyFund, .sellFund,
             .convertFund, .editFund:
            nil
        }
    }

    private static func returnFundCode(for route: ChildPanelRoute) -> String? {
        switch route {
        case .editTradeRecord(let fundCode, _),
             .editPendingTradeRecord(let fundCode, _),
             .editPendingConversion(let fundCode, _):
            fundCode
        case .editConversion(_, _, let returnFundCode):
            returnFundCode
        case .settings, .privacyDisclaimer, .onboarding, .sampleExperience,
             .portfolioPerformance, .jdFinancePerformanceSync, .jdFinanceSync, .portfolioBreakdown,
             .todayIncomeRanking, .addFund, .onboardingAddFund,
             .fundDetail, .fundDailyIncome, .tradeRecords, .buyFund, .sellFund,
             .convertFund, .editFund:
            nil
        }
    }
}
