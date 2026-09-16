import AppKit
import Observation
import OSLog
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

private let operationReminderNotificationID = "fund-pulse.operation-reminder"
private let fundThresholdReminderLastSentDefaultsKey = "fund-pulse.threshold-reminder.last-sent-times"
private let operationReminderNotificationPrefix = "\(operationReminderNotificationID)."
private let appearanceTransitionOverlayIdentifier = NSUserInterfaceItemIdentifier("fund-pulse.appearance-transition-overlay")
let statusBarUpdateLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.iamzjt.frontend.fund-pulse.swift",
    category: "AppUpdate"
)

final class ContextMenuUpdateCheckResultBox: @unchecked Sendable {
    private let lock = NSLock()
    var completion: AppUpdateCheckCompletion?

    func set(_ completion: AppUpdateCheckCompletion) {
        lock.lock()
        defer { lock.unlock() }
        guard self.completion == nil else { return }
        self.completion = completion
    }

    func take() -> AppUpdateCheckCompletion? {
        lock.lock()
        defer { lock.unlock() }
        let completion = completion
        self.completion = nil
        return completion
    }
}

struct ContextMenuUpdateCheck {
    var id: UUID
    var request: AppUpdateCheckRequest
    var resultBox: ContextMenuUpdateCheckResultBox
    var task: Task<Void, Never>
}

@MainActor
final class StatusBarController: NSObject {
    let statusItem: NSStatusItem
    let accountsStore: PortfolioAccountsStore
    let settingsStore: AppSettingsStore
    private let marketIndexStore: MarketIndexStore
    let updateStore: AppUpdateStore
    let appVersion: String
    private let popoverState = PopoverUIState()
    private lazy var statusPulseImage = makeStatusPulseImage(
        size: NSSize(width: StatusItemPresentation.iconSize, height: StatusItemPresentation.iconSize)
    )
    let onCheckUpdate: (AppUpdateCheckMode) async -> Void
    let onOpenUpdate: () -> Void

    private var mainPanelWindow: FundPulsePanel?
    private var childPanelWindow: FundPulsePanel?
    private var jdFinanceLoginWindow: FundPulsePanel?
    private var mainPanelHostingView: NSHostingView<AnyView>?
    private var activeChildPanel: ChildPanelRoute?
    private var selectedFundCode: String?
    private var jdFinanceTargetAccountID: String?
    private var jdFinanceLoginCompletion: ((String?) -> Void)?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var mainPanelAnchorFrame: NSRect?
    private var autoRefreshTimer: Timer?
    weak var contextMenuUpdateItem: NSMenuItem?
    var contextMenuUpdateRefreshTimer: Timer?
    var contextMenuUpdateAnimationFrame = 2
    var contextMenuUpdateStatusOverride: AppUpdateStatus?
    var contextMenuUpdateCheck: ContextMenuUpdateCheck?
    private var fundThresholdReminderLastSentAt: [String: Date] = [:]
    private var pendingFundThresholdReminderKeys: Set<String> = []
    private let operationReminderScheduler: OperationReminderNotificationScheduler
    private var settingsSectionSession = SettingsSectionSession()
    private var onboardingResumeStep = 0
    private var holdingPerformancePage = HoldingPerformancePresentation.defaultPage
    private var holdingPerformanceMetric: IncomeRankingMetric = .amount
    private var holdingPerformanceRange = HoldingPerformancePresentation.defaultRange
    private var holdingPerformanceMonth: Date?
#if DEBUG
    private var debugPerformanceStore: PortfolioPerformanceStore?
#endif

    private static func makeOperationReminderScheduler() -> OperationReminderNotificationScheduler {
        let center = UNUserNotificationCenter.current()
        return OperationReminderNotificationScheduler(
            maximumRemovalAttempts: 40,
            pendingRequests: {
                await center.pendingNotificationRequests().map(
                    Self.operationReminderNotificationCandidate(from:)
                )
            },
            removePendingRequests: {
                center.removePendingNotificationRequests(withIdentifiers: $0)
            },
            deliveredNotifications: {
                await center.deliveredNotifications().map {
                    Self.operationReminderNotificationCandidate(from: $0.request)
                }
            },
            removeDeliveredNotifications: {
                center.removeDeliveredNotifications(withIdentifiers: $0)
            },
            requestAuthorization: {
                try await center.requestAuthorization(options: [.alert, .sound])
            },
            addRequest: { request in
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .default

                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: TradingCalendar.notificationDateComponents(from: request.fireDate),
                    repeats: false
                )
                try await center.add(
                    UNNotificationRequest(
                        identifier: request.identifier,
                        content: content,
                        trigger: trigger
                    )
                )
            },
            waitAfterRemovalAttempt: {
                try? await Task<Never, Never>.sleep(nanoseconds: 50_000_000)
            }
        )
    }

    private var mainPanelHeight: CGFloat {
        PopoverLayout.clampedMainPanelHeight(CGFloat(settingsStore.settings.mainPanelHeight))
    }

    private var store: PortfolioStore {
        accountsStore.focusedStore
    }

    private var allowsAllAccountsView: Bool {
        accountsStore.accounts.count > 1
    }

    private var mainPanelWindowSize: NSSize {
        PopoverLayout.mainWindowFrameSize(forHeight: mainPanelHeight)
    }

    private var panelAppearance: NSAppearance? {
        settingsStore.settings.appearanceMode.nsAppearance
    }

    private var performanceStoreForPresentation: PortfolioPerformanceStore {
#if DEBUG
        debugPerformanceStore ?? store.performanceStore
#else
        store.performanceStore
#endif
    }

    init(
        accountsStore: PortfolioAccountsStore,
        settingsStore: AppSettingsStore,
        marketIndexStore: MarketIndexStore,
        updateStore: AppUpdateStore,
        appVersion: String,
        onCheckUpdate: @escaping (AppUpdateCheckMode) async -> Void,
        onOpenUpdate: @escaping () -> Void
    ) {
        self.accountsStore = accountsStore
        self.settingsStore = settingsStore
        self.marketIndexStore = marketIndexStore
        self.updateStore = updateStore
        self.appVersion = appVersion
        self.onCheckUpdate = onCheckUpdate
        self.onOpenUpdate = onOpenUpdate
        self.operationReminderScheduler = Self.makeOperationReminderScheduler()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        normalizeAccountSelectionForAccountCount()
        fundThresholdReminderLastSentAt = Self.loadFundThresholdReminderLastSentAt()
        configureStatusItem()
        updateStatusTitle()
        configureAutoRefreshTimer()
        configureOperationReminder()
        sendFundThresholdRemindersIfNeeded()
        refreshQuotesAndStatusTitle()
    }

    func invalidate() {
        hideJDFinanceLoginPanel(reportCancellation: true)
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        stopContextMenuUpdateRefresh(cancelPendingCheck: true)
        operationReminderScheduler.invalidate()
        removeEventMonitors()
    }

    func presentInitialExperienceIfNeeded() {
        guard OnboardingEligibility.shouldPresent(
            settings: settingsStore.settings,
            settingsLoadOrigin: settingsStore.loadOrigin,
            portfolioLoadState: store.loadState
        ) else { return }

        onboardingResumeStep = 0
        NSApp.activate(ignoringOtherApps: true)
        showMainPanel()
        showChildPanel(.onboarding(origin: .firstLaunch))
    }

#if DEBUG
    func presentDebugPanelIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard let flagIndex = arguments.firstIndex(of: "--debug-panel"),
              arguments.indices.contains(flagIndex + 1)
        else { return }

        if arguments[flagIndex + 1] == "main" {
            NSApp.activate(ignoringOtherApps: true)
            showMainPanel()
            return
        }

        let route: ChildPanelRoute
        switch arguments[flagIndex + 1] {
        case "onboarding":
            route = .onboarding(origin: .settings)
        case "sample":
            route = .sampleExperience(origin: .settings)
        case "privacy":
            route = .privacyDisclaimer(origin: .settings)
        case "support":
            settingsSectionSession.select(.support)
            route = .settings
        case "performance":
            holdingPerformancePage = .calendar
            route = .portfolioPerformance
        case "performance-sample":
            debugPerformanceStore = makeDebugPerformanceStore()
            holdingPerformancePage = .calendar
            route = .portfolioPerformance
        case "performance-calendar-sample":
            debugPerformanceStore = makeDebugPerformanceStore()
            holdingPerformancePage = .calendar
            route = .portfolioPerformance
        case "performance-sync":
            holdingPerformancePage = .calendar
            route = .jdFinancePerformanceSync
        case "settings":
            route = .settings
        case "accounts":
            route = .manageAccounts
        default:
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        showMainPanel()
        showChildPanel(route)
    }

    private func makeDebugPerformanceStore() -> PortfolioPerformanceStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "fund-pulse-performance-preview-\(UUID().uuidString)")
        let previewStore = PortfolioPerformanceStore(dataDirectory: directory)
        let sample = SampleExperienceFactory.make()
        let days = sample.dailyPerformance.enumerated().map { index, item in
            PortfolioPerformanceDay(
                date: DateOnlyFormatter.string(from: item.date),
                profit: item.dailyIncome,
                returnRate: item.dailyIncomeRate,
                status: index == sample.dailyPerformance.count - 1 ? .estimated : .confirmed,
                updatedAt: sample.generatedAt
            )
        }
        try? previewStore.replace(
            PortfolioPerformanceSnapshot(
                trackingStartDate: days.first?.date,
                days: days
            )
        )
        return previewStore
    }
#endif

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = statusPulseImage
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleStatusItemAction(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        statusItem.length = StatusItemPresentation.iconSize
    }

    func updateStatusTitle(animated: Bool = false) {
        let presentation = currentStatusTitlePresentation()
        guard let button = statusItem.button else { return }
        button.toolTip = "fund-pulse"
        button.image = statusPulseImage
        button.imagePosition = .imageLeft
        button.attributedTitle = NSAttributedString(
            string: presentation.text,
            attributes: presentation.attributes
        )
        setStatusItemLength(for: presentation)
    }

    private func currentStatusTitlePresentation() -> StatusTitlePresentation {
        let contentMode = settingsStore.settings.menuBarContentMode
        let amountValue: Double
        let rateValue: Double
        if accountsStore.selection == .all {
            amountValue = accountsStore.summary.todayIncome
            rateValue = accountsStore.summary.todayIncomeRate
        } else {
            amountValue = store.snapshot.todayIncome
            rateValue = store.snapshot.todayIncomeRate
        }
        let font = statusTitleFont()
        let statusText = MenuBarStatusFormatter.text(
            amount: amountValue,
            rate: rateValue,
            mode: contentMode
        )
        let toneValue = statusTitleToneValue(rate: rateValue)
        let attributes = statusTitleAttributes(for: toneValue, font: font)
        let visualLength = StatusItemPresentation.visualLength(
            for: statusText,
            attributes: attributes
        )

        return StatusTitlePresentation(
            text: statusText,
            attributes: attributes,
            visualLength: visualLength
        )
    }

    private func setStatusItemLength(for presentation: StatusTitlePresentation) {
        let systemButtonPadding: CGFloat = 10
        statusItem.length = ceil(presentation.visualLength + systemButtonPadding)
    }

    private func statusTitleFont() -> NSFont {
        return .systemFont(ofSize: NSFont.systemFontSize)
    }

    private func statusTitleToneValue(rate: Double) -> Double {
        rate
    }

    private func statusTitleAttributes(
        for value: Double,
        font: NSFont
    ) -> [NSAttributedString.Key: Any] {
        let color = statusTitleColor(for: value)
        return [
            .font: font,
            .foregroundColor: color
        ]
    }

    private func statusTitleColor(for value: Double) -> NSColor {
        guard settingsStore.settings.menuBarDisplayMode.usesGrowthColor else {
            return .labelColor
        }

        if value > 0 { return .systemRed }
        if value < 0 { return .systemGreen }
        return .secondaryLabelColor
    }

    private func toggleMainPanelFromStatusItem() {
        if let mainPanelWindow, mainPanelWindow.isVisible {
            closeAllPanels()
        } else {
            showMainPanel()
        }
    }

    @objc private func handleStatusItemAction(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu(relativeTo: sender)
            return
        }

        toggleMainPanelFromStatusItem()
    }

    private func showMainPanel() {
        let window = mainPanelWindow ?? createMainPanelWindow()
        applyPanelAppearance(to: window)
        setStatusItemHighlighted(true)

        if case .loading = accountsStore.loadState {
            accountsStore.load()
        }
        normalizeAccountSelectionForAccountCount()
        updateStatusTitle()
        sendFundThresholdRemindersIfNeeded()
        updateMainPanelRootView()
        mainPanelAnchorFrame = currentStatusButtonFrame()

        let size = mainPanelWindowSize
        window.setContentSize(size)
        positionMainPanel(window: window, size: size)
        window.orderFrontRegardless()
        window.makeKey()
        installEventMonitorsIfNeeded()

        refreshQuotesAndStatusTitle()
        checkForUpdates()
    }

    private func createMainPanelWindow() -> FundPulsePanel {
        let window = FundPulsePanel()
        window.acceptsMouseMovedEvents = true
        window.onOrderOut = { [weak self] in
            self?.handleMainPanelDidHide()
        }
        window.onClose = { [weak self] in
            self?.handleMainPanelDidHide()
        }
        window.onCancel = { [weak self] in
            self?.closeAllPanels()
        }

        let hostingView = PanelFocusAppearance.hostingView(makeMainPanelRootView())
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.appearance = panelAppearance
        mainPanelHostingView = hostingView
        window.contentView = hostingView
        mainPanelWindow = window
        applyPanelAppearance(to: window)
        return window
    }

    private func updateMainPanelRootView() {
        mainPanelHostingView?.rootView = PanelFocusAppearance.suppressedRoot(
            makeMainPanelRootView()
        )
    }

    private func makeMainPanelRootView() -> MainPanelWindowView {
        MainPanelWindowView(
            accountsStore: accountsStore,
            settingsStore: settingsStore,
            marketIndexStore: marketIndexStore,
            updateStore: updateStore,
            uiState: popoverState,
            selectedFundCode: selectedFundCode,
            onSelectAccount: { [weak self] selection in
                self?.selectAccount(selection)
            },
            onManageAccounts: { [weak self] in
                self?.showChildPanel(.manageAccounts)
            },
            onRefresh: { [weak self] in
                await self?.refreshQuotesAndStatusTitleAsync()
            },
            onOpenSettings: { [weak self] in
                self?.openSettingsForFocusedAccount()
            },
            onClose: { [weak self] in
                self?.closeAllPanels()
            },
            onOpenPortfolioBreakdown: { [weak self] in
                self?.showChildPanel(.portfolioBreakdown)
            },
            onOpenTodayIncomeRanking: { [weak self] in
                self?.showChildPanel(.todayIncomeRanking(.amount))
            },
            onOpenTodayRateRanking: { [weak self] in
                self?.showChildPanel(.todayIncomeRanking(.rate))
            },
            onOpenHoldingIncome: { [weak self] in
                self?.openHoldingPerformance(rankingMetric: .amount)
            },
            onOpenHoldingRate: { [weak self] in
                self?.openHoldingPerformance(rankingMetric: .rate)
            },
            onAddFund: { [weak self] in
                self?.showChildPanel(.addFund)
            },
            onOpenFundDetail: { [weak self] fund in
                self?.showChildPanel(.fundDetail(fundCode: fund.code))
            },
            onOpenTradeRecords: { [weak self] fund in
                self?.showChildPanel(.tradeRecords(fundCode: fund.code))
            },
            onOpenPendingActivity: { [weak self] activity in
                self?.showPendingActivity(activity)
            },
            onDeletePendingActivity: { [weak self] activity in
                await self?.deletePendingActivity(activity)
            },
            onBuyFund: { [weak self] fund in
                self?.showChildPanel(.buyFund(fundCode: fund.code))
            },
            onSellFund: { [weak self] fund in
                self?.showChildPanel(.sellFund(fundCode: fund.code))
            },
            onEditFund: { [weak self] fund in
                self?.showChildPanel(.editFund(fundCode: fund.code))
            },
            onDeleteFund: { [weak self] fund in
                await self?.deleteFund(fund)
            },
            onCheckUpdate: { [weak self] in
                await self?.onCheckUpdate(.interactive)
            },
            onOpenUpdate: { [weak self] in
                self?.onOpenUpdate()
            }
        )
    }

    private func openHoldingPerformance(rankingMetric: IncomeRankingMetric) {
        let entry = HoldingPerformancePresentation.defaultEntry(rankingMetric: rankingMetric)
        holdingPerformancePage = entry.page
        holdingPerformanceMetric = entry.rankingMetric
        holdingPerformanceRange = entry.range
        holdingPerformanceMonth = nil
        showChildPanel(.portfolioPerformance)
    }

    @discardableResult
    private func normalizeAccountSelectionForAccountCount(hidePanels: Bool = true) -> Bool {
        guard let firstAccount = accountsStore.accounts.first else { return false }
        guard !allowsAllAccountsView, accountsStore.selection != .account(firstAccount.id) else {
            return false
        }

        if hidePanels {
            hideJDFinanceLoginPanel(reportCancellation: true)
            hideChildPanel()
        }
        selectedFundCode = nil
        accountsStore.select(.account(firstAccount.id))
        return true
    }

    private func selectAccount(_ selection: PortfolioAccountSelection) {
        if selection == .all, !allowsAllAccountsView {
            normalizeAccountSelectionForAccountCount()
            return
        }

        guard selection != accountsStore.selection else { return }
        hideJDFinanceLoginPanel(reportCancellation: true)
        hideChildPanel()
        selectedFundCode = nil
        accountsStore.select(selection)
        updateStatusTitle()
        updateMainPanelRootView()
        sendFundThresholdRemindersIfNeeded()
    }

    private func showChildPanel(_ route: ChildPanelRoute) {
        if mainPanelWindow?.isVisible != true {
            showMainPanel()
        }

        if route.ownsJDFinanceLoginPanel,
           accountsStore.focusedAccount.kind != .offExchange {
            presentAccountActionUnavailable(
                title: "此账户不支持京东同步",
                message: "京东金融同步只适用于场外基金账户。请先切换到场外账户。"
            )
            return
        }

        if let activeChildPanel,
           activeChildPanel.ownsJDFinanceLoginPanel,
           activeChildPanel != route {
            hideJDFinanceLoginPanel(reportCancellation: false)
        }

        switch ChildPanelRouteResolver.disposition(for: route, in: store.snapshot) {
        case .available:
            break
        case .redirect(let fallbackRoute):
            showChildPanel(fallbackRoute)
            return
        case .close:
            hideChildPanel()
            return
        }

        guard let (contentView, size) = makeChildPanelContent(for: route) else { return }
        activeChildPanel = route
        selectedFundCode = route.selectedFundCode
        updateMainPanelRootView()

        let window = childPanelWindow ?? createChildPanelWindow()
        let container = PanelCardContainerView(contentView: contentView)
        container.frame = NSRect(origin: .zero, size: size)
        container.applyAppearance(panelAppearance)
        window.contentView = container
        applyPanelAppearance(to: window)
        window.setContentSize(size)
        positionChildPanel(window: window, size: size)
        window.orderFrontRegardless()
        window.makeKey()
        installEventMonitorsIfNeeded()
    }

    private func showJDFinanceSyncPanel() {
        guard !jdFinanceTargetCandidates.isEmpty else {
            showChildPanel(.addAccount)
            return
        }
        guard let target = jdFinanceTargetAccount else {
            return
        }

        if accountsStore.selection != .account(target.id) {
            selectAccount(.account(target.id))
        }
        showChildPanel(.jdFinanceSync)
    }

    private var jdFinanceTargetCandidates: [PortfolioAccount] {
        accountsStore.accounts.filter { $0.kind == .offExchange }
    }

    private var jdFinanceTargetAccount: PortfolioAccount? {
        let boundAccountIDs = Set<String>(
            jdFinanceTargetCandidates.compactMap { account in
                guard accountsStore.store(for: account.id)?.snapshot.jdFinanceSyncState?.accountKey?.isEmpty == false else {
                    return nil
                }
                return account.id
            }
        )
        return JDFinanceTargetResolver.resolve(
            accounts: accountsStore.accounts,
            focusedAccountID: accountsStore.focusedAccount.id,
            preferredAccountID: jdFinanceTargetAccountID,
            boundAccountIDs: boundAccountIDs
        )
    }

    private func selectJDFinanceTargetAccount(_ accountID: String) {
        guard jdFinanceTargetCandidates.contains(where: { $0.id == accountID }) else { return }
        jdFinanceTargetAccountID = accountID
        showChildPanel(.settings)
    }

    private func presentAccountActionUnavailable(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func createChildPanelWindow() -> FundPulsePanel {
        let window = FundPulsePanel()
        window.acceptsMouseMovedEvents = true
        window.onOrderOut = { [weak self] in
            self?.clearChildPanelState()
        }
        window.onClose = { [weak self] in
            self?.clearChildPanelState()
        }
        window.onCancel = { [weak self] in
            self?.handleChildPanelCancel()
        }
        childPanelWindow = window
        return window
    }

    private func showJDFinanceLoginPanel(onLoggedIn: @escaping (String?) -> Void) {
        jdFinanceLoginCompletion = onLoggedIn

        let window = jdFinanceLoginWindow ?? createJDFinanceLoginWindow()
        let view = JDFinanceLoginPanelView(
            onLoggedIn: { [weak self] cookieHeader in
                self?.completeJDFinanceLogin(cookieHeader: cookieHeader)
            },
            onClose: { [weak self] in
                self?.hideJDFinanceLoginPanel(reportCancellation: true)
            }
        )
        let size = PopoverLayout.jdFinanceLoginSize
        let container = PanelCardContainerView(contentView: PanelFocusAppearance.hostingView(view))
        container.frame = NSRect(origin: .zero, size: size)
        container.applyAppearance(panelAppearance)
        window.contentView = container
        applyPanelAppearance(to: window)
        window.setContentSize(size)
        positionJDFinanceLoginPanel(window: window, size: size)
        window.orderFrontRegardless()
        window.makeKey()
        installEventMonitorsIfNeeded()
    }

    private func showJDFinanceNetworkProbePanel(networkProbe: JDFinanceNetworkProbe) {
        jdFinanceLoginCompletion = nil

        let window = jdFinanceLoginWindow ?? createJDFinanceLoginWindow()
        let view = JDFinanceLoginPanelView(
            title: "京东金融网页调试",
            initialURL: JDFinanceWebSession.tradeOrderURL,
            reloadButtonTitle: "刷新网页",
            autoCompleteLogin: false,
            networkProbe: networkProbe,
            onLoggedIn: { _ in },
            onClose: { [weak self, weak networkProbe] in
                networkProbe?.clear()
                self?.hideJDFinanceLoginPanel(reportCancellation: false)
            }
        )
        let size = PopoverLayout.jdFinanceNetworkProbeSize
        let container = PanelCardContainerView(contentView: PanelFocusAppearance.hostingView(view))
        container.frame = NSRect(origin: .zero, size: size)
        container.applyAppearance(panelAppearance)
        window.contentView = container
        applyPanelAppearance(to: window)
        window.setContentSize(size)
        positionJDFinanceLoginPanel(window: window, size: size)
        window.orderFrontRegardless()
        window.makeKey()
        installEventMonitorsIfNeeded()
    }

    private func createJDFinanceLoginWindow() -> FundPulsePanel {
        let window = FundPulsePanel()
        window.acceptsMouseMovedEvents = true
        window.onOrderOut = { [weak self] in
            self?.jdFinanceLoginCompletion = nil
        }
        window.onClose = { [weak self] in
            self?.hideJDFinanceLoginPanel(reportCancellation: true)
        }
        window.onCancel = { [weak self] in
            self?.hideJDFinanceLoginPanel(reportCancellation: true)
        }
        jdFinanceLoginWindow = window
        return window
    }

    private func completeJDFinanceLogin(cookieHeader: String) {
        let completion = jdFinanceLoginCompletion
        jdFinanceLoginCompletion = nil
        jdFinanceLoginWindow?.orderOut(nil)
        completion?(cookieHeader)
    }

    private func hideJDFinanceLoginPanel(reportCancellation: Bool = false) {
        let completion = jdFinanceLoginCompletion
        jdFinanceLoginCompletion = nil
        jdFinanceLoginWindow?.orderOut(nil)
        if reportCancellation {
            completion?(nil)
        }
    }

    private func makeChildPanelContent(for route: ChildPanelRoute) -> (NSView, NSSize)? {
        switch route {
        case .privacyDisclaimer(let origin):
            let view = PrivacyDisclaimerView(
                onBack: { [weak self] in
                    self?.returnFromPrivacyDisclaimer(origin)
                },
                onOpenURL: { url in
                    NSWorkspace.shared.open(url)
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.privacyDisclaimerSize)

        case .onboarding(let origin):
            let view = OnboardingView(
                initialStep: onboardingResumeStep,
                onAddFund: { [weak self] in
                    self?.showChildPanel(.onboardingAddFund(origin: origin))
                },
                onImportPortfolio: { [weak self] in
                    guard let self, importFundConfiguration() else { return }
                    finishOnboarding(origin)
                },
                onOpenSample: { [weak self] in
                    self?.showChildPanel(.sampleExperience(origin: origin))
                },
                onStartEmpty: { [weak self] in
                    self?.finishOnboarding(origin)
                },
                onOpenPrivacy: { [weak self] in
                    self?.onboardingResumeStep = 1
                    self?.showChildPanel(.privacyDisclaimer(origin: .onboarding(origin)))
                },
                onClose: { [weak self] in
                    self?.closeOnboarding(origin)
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.onboardingSize)

        case .sampleExperience(let origin):
            let view = SampleExperienceView(
                onClose: { [weak self] in
                    self?.onboardingResumeStep = 2
                    self?.showChildPanel(.onboarding(origin: origin))
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.sampleExperienceSize)

        case .portfolioPerformance:
            let view = PortfolioPerformanceView(
                portfolioStore: store,
                store: performanceStoreForPresentation,
                initialPage: holdingPerformancePage,
                initialRankingMetric: holdingPerformanceMetric,
                initialRange: holdingPerformanceRange,
                initialDisplayedMonth: holdingPerformanceMonth,
                betaFeaturesEnabled: settingsStore.settings.betaFeaturesEnabled,
                onOpenJDFinanceSync: { [weak self] in
                    self?.showChildPanel(.jdFinancePerformanceSync)
                },
                onNavigationChange: { [weak self] page, metric, range, month in
                    self?.holdingPerformancePage = page
                    self?.holdingPerformanceMetric = metric
                    self?.holdingPerformanceRange = range
                    self?.holdingPerformanceMonth = month
                },
                onBack: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.portfolioPerformanceSize)

        case .jdFinancePerformanceSync:
            let view = JDFinancePerformanceSyncView(
                portfolioStore: store,
                performanceStore: performanceStoreForPresentation,
                onRequestLogin: { [weak self] completion in
                    self?.showJDFinanceLoginPanel(onLoggedIn: completion)
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.portfolioPerformance)
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.jdFinancePerformanceSyncSize)

        case .addAccount:
            let view = PortfolioAccountEditorView(
                accountsStore: accountsStore,
                onSaved: { [weak self] _ in
                    guard let self else { return }
                    hideChildPanel()
                    normalizeAccountSelectionForAccountCount()
                    selectedFundCode = nil
                    updateStatusTitle()
                    updateMainPanelRootView()
                    sendFundThresholdRemindersIfNeeded()
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.accountEditorSize)

        case .manageAccounts:
            let view = PortfolioAccountManagementView(
                accountsStore: accountsStore,
                onAddAccount: { [weak self] in
                    self?.showChildPanel(.addAccount)
                },
                onSelected: { [weak self] accountID in
                    guard let self else { return }
                    hideChildPanel()
                    selectAccount(.account(accountID))
                    updateMainPanelRootView()
                },
                onAccountsChanged: { [weak self] in
                    guard let self else { return }
                    normalizeAccountSelectionForAccountCount(hidePanels: false)
                    updateStatusTitle()
                    updateMainPanelRootView()
                    reconcileActiveChildPanelRoute()
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.accountManagementSize)

        case .settings:
            let view = SettingsView(
                store: store,
                account: accountsStore.focusedAccount,
                jdFinanceTargetAccount: jdFinanceTargetAccount,
                jdFinanceTargetCandidates: jdFinanceTargetCandidates,
                settingsStore: settingsStore,
                updateStore: updateStore,
                appVersion: appVersion,
                onSettingsChanged: { [weak self] in
                    self?.handleSettingsChanged()
                },
                onRefresh: { [weak self] in
                    await self?.refreshQuotesAndStatusTitleAsync()
                },
                onCheckUpdate: { [weak self] in
                    await self?.onCheckUpdate(.interactive)
                },
                onOpenJDFinanceSync: { [weak self] in
                    self?.showJDFinanceSyncPanel()
                },
                onSelectJDFinanceTarget: { [weak self] accountID in
                    self?.selectJDFinanceTargetAccount(accountID)
                },
                onCreateOffExchangeAccount: { [weak self] in
                    self?.showChildPanel(.addAccount)
                },
                onOpenPrivacyDisclaimer: { [weak self] in
                    self?.showChildPanel(.privacyDisclaimer(origin: .settings))
                },
                onOpenOnboarding: { [weak self] in
                    self?.showChildPanel(.onboarding(origin: .settings))
                },
                onOpenExternalURL: { url in
                    NSWorkspace.shared.open(url)
                },
                initialSection: settingsSectionSession.selectedSection,
                onSectionChanged: { [weak self] section in
                    self?.settingsSectionSession.select(section)
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.settingsSize)

        case .jdFinanceSync:
            let view = JDFinanceHoldingsSyncView(
                portfolioStore: store,
                onRequestLogin: { [weak self] completion in
                    self?.showJDFinanceLoginPanel(onLoggedIn: completion)
                },
                onRequestNetworkProbe: { [weak self] networkProbe in
                    self?.showJDFinanceNetworkProbePanel(networkProbe: networkProbe)
                },
                onMainPanelRefreshNeeded: { [weak self] in
                    self?.refreshQuotesAndStatusTitle()
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.jdFinanceSyncSize)

        case .portfolioBreakdown:
            let view = PortfolioAllocationPanelView(
                store: store,
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.portfolioBreakdownSize)

        case .todayIncomeRanking(let metric):
            let view = TodayIncomeRankingPanelView(
                store: store,
                kind: .today,
                metric: metric,
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.todayIncomeRankingSize)

        case .addFund:
            let view = FundPositionEditorView(
                store: store,
                fund: nil,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.editorSize)

        case .onboardingAddFund(let origin):
            let flowState = OnboardingAddFlowState()
            let view = FundPositionEditorView(
                store: store,
                fund: nil,
                onSaved: { [weak self, flowState] in
                    await MainActor.run {
                        flowState.didSave = true
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                    }
                },
                onClose: { [weak self, flowState] in
                    guard let self else { return }
                    if flowState.didSave {
                        finishOnboarding(origin)
                    } else {
                        onboardingResumeStep = 2
                        showChildPanel(.onboarding(origin: origin))
                    }
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.editorSize)

        case .fundDetail(let fundCode):
            let view = FundDetailView(
                store: store,
                fundCode: fundCode,
                allowsConversion: store.accountKind == .offExchange,
                onBuy: { [weak self] fund in
                    self?.showChildPanel(.buyFund(fundCode: fund.code))
                },
                onSell: { [weak self] fund in
                    self?.showChildPanel(.sellFund(fundCode: fund.code))
                },
                onConvert: { [weak self] fund in
                    self?.showChildPanel(.convertFund(fundCode: fund.code))
                },
                onEdit: { [weak self] fund in
                    self?.showChildPanel(.editFund(fundCode: fund.code))
                },
                onOpenTradeRecords: { [weak self] fund in
                    self?.showChildPanel(.tradeRecords(fundCode: fund.code))
                },
                onOpenDailyIncome: { [weak self] fund in
                    self?.showChildPanel(.fundDailyIncome(fundCode: fund.code))
                },
                onDelete: { [weak self] fund in
                    await self?.deleteFund(fund)
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.fundDetailSize)

        case .fundDailyIncome(let fundCode):
            let view = FundDailyIncomePanelView(
                store: store,
                fundCode: fundCode,
                onClose: { [weak self] in
                    self?.showChildPanel(.fundDetail(fundCode: fundCode))
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.fundDailyIncomeSize)

        case .tradeRecords(let fundCode):
            let view = FundTradeRecordsPanelView(
                store: store,
                fundCode: fundCode,
                onEdit: { [weak self] record in
                    if record.kind == .conversionOut || record.kind == .conversionIn {
                        let sourceCode = record.kind == .conversionOut ? record.code : (record.linkedCode ?? fundCode)
                        self?.showChildPanel(
                            .editConversion(
                                sourceFundCode: sourceCode,
                                recordID: record.id,
                                returnFundCode: fundCode
                            )
                        )
                    } else {
                        self?.showChildPanel(.editTradeRecord(fundCode: fundCode, recordID: record.id))
                    }
                },
                onDelete: { [weak self] record in
                    await self?.deleteTradeRecord(record, returningToFundCode: fundCode)
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.fundDetail(fundCode: fundCode))
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeRecordsSize)

        case .buyFund(let fundCode):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }) else { return nil }
            if store.accountKind == .onExchange {
                let view = ExchangeFundTradeEditorView(
                    store: store,
                    fund: fund,
                    action: .buy,
                    onSaved: { [weak self] in
                        await MainActor.run {
                            self?.updateStatusTitle()
                            self?.sendFundThresholdRemindersIfNeeded()
                        }
                    },
                    onClose: { [weak self] in
                        self?.hideChildPanel()
                    }
                )
                return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)
            }
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: .buy,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .sellFund(let fundCode):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }) else { return nil }
            if store.accountKind == .onExchange {
                let view = ExchangeFundTradeEditorView(
                    store: store,
                    fund: fund,
                    action: .sell,
                    onSaved: { [weak self] in
                        await MainActor.run {
                            self?.updateStatusTitle()
                            self?.sendFundThresholdRemindersIfNeeded()
                        }
                    },
                    onClose: { [weak self] in
                        self?.hideChildPanel()
                    }
                )
                return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)
            }
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: .sell,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .convertFund(let fundCode):
            guard store.accountKind == .offExchange else {
                presentAccountActionUnavailable(
                    title: "场内基金无需转换",
                    message: "场内基金请按实际成交价记录买入或卖出；基金转换仅适用于场外账户。"
                )
                return nil
            }
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }) else { return nil }
            let view = FundConversionEditorView(
                store: store,
                sourceFund: fund,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .editTradeRecord(let fundCode, let recordID):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }),
                  let record = store.snapshot.tradeRecords?.first(where: { $0.id == recordID })
            else { return nil }
            let action: FundTradeAction = record.kind == .sell ? .sell : .buy
            if store.accountKind == .onExchange {
                let view = ExchangeFundTradeEditorView(
                    store: store,
                    fund: fund,
                    action: action,
                    editingRecord: record,
                    onSaved: { [weak self] in
                        await MainActor.run {
                            self?.updateStatusTitle()
                            self?.sendFundThresholdRemindersIfNeeded()
                            self?.showChildPanel(.tradeRecords(fundCode: fundCode))
                        }
                    },
                    onClose: { [weak self] in
                        self?.showChildPanel(.tradeRecords(fundCode: fundCode))
                    }
                )
                return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)
            }
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: action,
                editingRecord: record,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                        self?.showChildPanel(.tradeRecords(fundCode: fundCode))
                    }
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.tradeRecords(fundCode: fundCode))
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .editConversion(let sourceFundCode, let recordID, let returnFundCode):
            guard let fund = store.snapshot.funds.first(where: { $0.code == sourceFundCode }),
                  let record = store.snapshot.tradeRecords?.first(where: { $0.id == recordID })
            else { return nil }
            let view = FundConversionEditorView(
                store: store,
                sourceFund: fund,
                editingRecord: record,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                        self?.showChildPanel(.tradeRecords(fundCode: returnFundCode))
                    }
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.tradeRecords(fundCode: returnFundCode))
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .editPendingTradeRecord(let fundCode, let recordID):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }),
                  let record = store.snapshot.tradeRecords?.first(where: { $0.id == recordID })
            else { return nil }
            let action: FundTradeAction = record.kind == .sell ? .sell : .buy
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: action,
                editingRecord: record,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                        self?.hideChildPanel()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .editPendingConversion(let fundCode, let recordID):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }),
                  let record = store.snapshot.tradeRecords?.first(where: { $0.id == recordID })
            else { return nil }
            let view = FundConversionEditorView(
                store: store,
                sourceFund: fund,
                editingRecord: record,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                        self?.hideChildPanel()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.tradeEditorSize)

        case .editFund(let fundCode):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }) else { return nil }
            let view = FundPositionEditorView(
                store: store,
                fund: fund,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.sendFundThresholdRemindersIfNeeded()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (PanelFocusAppearance.hostingView(view), PopoverLayout.editorSize)
        }
    }

    private func showPendingActivity(_ activity: PendingTradeActivity) {
        let records = store.snapshot.tradeRecords ?? []
        let matchingRecord = pendingActivityRecord(activity, records: records)
        let matchingFund = activity.fund ?? store.snapshot.funds.first { $0.code == activity.code }

        if let record = matchingRecord {
            if record.kind == .conversionOut || record.kind == .conversionIn {
                let sourceCode = record.kind == .conversionOut ? record.code : (record.linkedCode ?? activity.code)
                guard store.snapshot.funds.contains(where: { $0.code == sourceCode }) || matchingFund?.code == sourceCode else {
                    return
                }
                showChildPanel(.editPendingConversion(fundCode: sourceCode, recordID: record.id))
            } else if let fund = store.snapshot.funds.first(where: { $0.code == record.code }) ?? matchingFund {
                showChildPanel(.editPendingTradeRecord(fundCode: fund.code, recordID: record.id))
            }
            return
        }

        guard let fund = matchingFund else { return }
        switch activity.kind {
        case .sell:
            showChildPanel(.sellFund(fundCode: fund.code))
        case .conversionOut, .conversionIn:
            showChildPanel(.convertFund(fundCode: fund.code))
        case .newFund:
            showChildPanel(.editFund(fundCode: fund.code))
        case .buy:
            showChildPanel(.buyFund(fundCode: fund.code))
        }
    }

    private func pendingActivityRecord(
        _ activity: PendingTradeActivity,
        records: [FundTradeRecord]
    ) -> FundTradeRecord? {
        if let recordID = activity.recordID,
           let record = records.first(where: { $0.id == recordID }) {
            return record
        }

        if let conversionID = activity.conversionID,
           let record = records.first(where: { $0.conversionID == conversionID && $0.kind == .conversionOut })
                ?? records.first(where: { $0.conversionID == conversionID }) {
            return record
        }

        return records.first {
            $0.status == .pending
                && $0.code == activity.code
                && $0.kind == activity.kind
                && $0.tradeDate == activity.tradeDate
                && $0.tradeTimeType == activity.tradeTimeType
        }
    }

    private func hideChildPanel() {
        if activeChildPanel?.ownsJDFinanceLoginPanel == true {
            hideJDFinanceLoginPanel(reportCancellation: false)
        }
        childPanelWindow?.orderOut(nil)
        clearChildPanelState()
    }

    private func returnFromPrivacyDisclaimer(_ origin: PrivacyDisclaimerOrigin) {
        switch origin {
        case .settings:
            showChildPanel(.settings)
        case .onboarding(let onboardingOrigin):
            showChildPanel(.onboarding(origin: onboardingOrigin))
        }
    }

    private func closeOnboarding(_ origin: OnboardingOrigin) {
        switch origin {
        case .firstLaunch:
            hideChildPanel()
        case .settings:
            showChildPanel(.settings)
        }
    }

    private func finishOnboarding(_ origin: OnboardingOrigin) {
        switch origin {
        case .firstLaunch:
            do {
                try settingsStore.completeOnboarding()
                onboardingResumeStep = 0
                hideChildPanel()
            } catch {
                presentConfigurationError(title: "保存首次设置失败", error: error)
            }
        case .settings:
            onboardingResumeStep = 0
            showChildPanel(.settings)
        }
    }

    private func handleChildPanelCancel() {
        if case .tradeRecords(let fundCode) = activeChildPanel {
            showChildPanel(.fundDetail(fundCode: fundCode))
        } else if case .fundDailyIncome(let fundCode) = activeChildPanel {
            showChildPanel(.fundDetail(fundCode: fundCode))
        } else if case .sampleExperience(let origin) = activeChildPanel {
            onboardingResumeStep = 2
            showChildPanel(.onboarding(origin: origin))
        } else if case .privacyDisclaimer(let origin) = activeChildPanel {
            returnFromPrivacyDisclaimer(origin)
        } else if case .onboardingAddFund(let origin) = activeChildPanel {
            onboardingResumeStep = 2
            showChildPanel(.onboarding(origin: origin))
        } else if case .onboarding(let origin) = activeChildPanel {
            closeOnboarding(origin)
        } else if case .jdFinancePerformanceSync = activeChildPanel {
            showChildPanel(.portfolioPerformance)
        } else {
            hideChildPanel()
        }
    }

    private func handleMainPanelDidHide() {
        hideJDFinanceLoginPanel(reportCancellation: true)
        childPanelWindow?.orderOut(nil)
        clearChildPanelState()
        mainPanelAnchorFrame = nil
        removeEventMonitors()
        setStatusItemHighlighted(false)
    }

    func closeAllPanels() {
        hideJDFinanceLoginPanel(reportCancellation: true)
        mainPanelWindow?.orderOut(nil)
        childPanelWindow?.orderOut(nil)
        clearChildPanelState()
        mainPanelAnchorFrame = nil
        removeEventMonitors()
        setStatusItemHighlighted(false)
    }

    private func clearChildPanelState() {
        let shouldRefreshMainPanel = activeChildPanel != nil || selectedFundCode != nil
        activeChildPanel = nil
        selectedFundCode = nil
        if shouldRefreshMainPanel {
            updateMainPanelRootView()
        }
    }

    private func refreshVisiblePanels() {
        refreshVisiblePanels(animatedAppearance: false)
    }

    private func handleStoreSnapshotChanged() {
        reconcileActiveChildPanelRoute()
        refreshVisiblePanels()
    }

    private func reconcileActiveChildPanelRoute() {
        guard let route = activeChildPanel else { return }
        switch ChildPanelRouteResolver.disposition(for: route, in: store.snapshot) {
        case .available:
            return
        case .redirect(let fallbackRoute):
            showChildPanel(fallbackRoute)
        case .close:
            hideChildPanel()
        }
    }

    private func refreshVisiblePanels(animatedAppearance: Bool) {
        guard let mainPanelWindow, mainPanelWindow.isVisible else { return }
        applyPanelAppearance(to: mainPanelWindow, animated: animatedAppearance)
        let mainSize = mainPanelWindowSize
        mainPanelWindow.setContentSize(mainSize)
        positionMainPanel(window: mainPanelWindow, size: mainSize)

        guard let childPanelWindow, childPanelWindow.isVisible else { return }
        applyPanelAppearance(to: childPanelWindow, animated: animatedAppearance)
        let size: NSSize
        switch activeChildPanel {
        case .settings:
            size = PopoverLayout.settingsSize
        case .privacyDisclaimer:
            size = PopoverLayout.privacyDisclaimerSize
        case .onboarding:
            size = PopoverLayout.onboardingSize
        case .sampleExperience:
            size = PopoverLayout.sampleExperienceSize
        case .portfolioPerformance:
            size = PopoverLayout.portfolioPerformanceSize
        case .jdFinancePerformanceSync:
            size = PopoverLayout.jdFinancePerformanceSyncSize
        case .jdFinanceSync:
            size = PopoverLayout.jdFinanceSyncSize
        case .portfolioBreakdown:
            size = PopoverLayout.portfolioBreakdownSize
        case .todayIncomeRanking:
            size = PopoverLayout.todayIncomeRankingSize
        case .addAccount:
            size = PopoverLayout.accountEditorSize
        case .manageAccounts:
            size = PopoverLayout.accountManagementSize
        case .fundDetail:
            size = PopoverLayout.fundDetailSize
        case .fundDailyIncome:
            size = PopoverLayout.fundDailyIncomeSize
        case .tradeRecords:
            size = PopoverLayout.tradeRecordsSize
        case .addFund, .onboardingAddFund, .editFund:
            size = PopoverLayout.editorSize
        case .buyFund, .sellFund, .convertFund, .editTradeRecord, .editConversion, .editPendingTradeRecord, .editPendingConversion:
            size = PopoverLayout.tradeEditorSize
        case nil:
            return
        }
        childPanelWindow.setContentSize(size)
        positionChildPanel(window: childPanelWindow, size: size)
    }

    private func resizeAndPositionMainPanel() {
        guard let mainPanelWindow, mainPanelWindow.isVisible else { return }
        let mainSize = mainPanelWindowSize
        mainPanelWindow.setContentSize(mainSize)
        positionMainPanel(window: mainPanelWindow, size: mainSize)
    }

    private func applyPanelAppearance(to window: FundPulsePanel) {
        applyPanelAppearance(to: window, animated: false)
    }

    private func applyPanelAppearance(to window: FundPulsePanel, animated: Bool) {
        if animated {
            installAppearanceTransitionOverlay(on: window)
        }

        let appearance = panelAppearance
        window.appearance = appearance
        window.contentView?.appearance = appearance
        mainPanelHostingView?.appearance = appearance
        if let container = window.contentView as? PanelCardContainerView {
            container.applyAppearance(appearance)
        }

        if animated {
            fadeOutAppearanceTransitionOverlay(on: window)
        }
    }

    private func installAppearanceTransitionOverlay(on window: FundPulsePanel) {
        guard let contentView = window.contentView else { return }
        contentView.subviews
            .filter { $0.identifier == appearanceTransitionOverlayIdentifier }
            .forEach { $0.removeFromSuperview() }

        let overlay = AppearanceTransitionOverlayView(appearance: window.effectiveAppearance)
        overlay.identifier = appearanceTransitionOverlayIdentifier
        overlay.frame = contentView.bounds
        overlay.autoresizingMask = [.width, .height]
        overlay.alphaValue = 1
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
    }

    private func fadeOutAppearanceTransitionOverlay(on window: FundPulsePanel) {
        guard let contentView = window.contentView else { return }
        let overlays = contentView.subviews.filter { $0.identifier == appearanceTransitionOverlayIdentifier }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlays.forEach { overlay in
                overlay.animator().alphaValue = 0
            }
        } completionHandler: {
            Task { @MainActor in
                overlays.forEach { $0.removeFromSuperview() }
            }
        }
    }

    private func installEventMonitorsIfNeeded() {
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                self?.handleLocalPanelEvent(event) ?? event
            }
        }

        if globalEventMonitor == nil {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                DispatchQueue.main.async {
                    self?.handlePanelEvent(event, screenLocation: event.locationInWindow)
                }
            }
        }

        if deactivateObserver == nil {
            deactivateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.closeAllPanels()
                }
            }
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let deactivateObserver {
            NotificationCenter.default.removeObserver(deactivateObserver)
            self.deactivateObserver = nil
        }
    }

    private func handleLocalPanelEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            closeAllPanels()
            return nil
        }

        guard event.type == .leftMouseDown || event.type == .rightMouseDown,
              let location = event.window?.convertPoint(toScreen: event.locationInWindow)
        else {
            return event
        }

        handlePanelEvent(event, screenLocation: location)
        return event
    }

    private func handlePanelEvent(_ event: NSEvent, screenLocation: NSPoint) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if PanelAuxiliaryPopoverRegistry.handlePanelMouseDown(at: screenLocation) {
                return
            }
            guard !pointIsInsideManagedPanels(screenLocation), !pointIsInsideStatusButton(screenLocation) else { return }
            closeAllPanels()
        default:
            break
        }
    }

    private func pointIsInsideManagedPanels(_ point: NSPoint) -> Bool {
        if let mainPanelWindow, mainPanelWindow.isVisible, mainPanelWindow.frame.contains(point) {
            return true
        }
        if let childPanelWindow, childPanelWindow.isVisible, childPanelWindow.frame.contains(point) {
            return true
        }
        if let jdFinanceLoginWindow, jdFinanceLoginWindow.isVisible, jdFinanceLoginWindow.frame.contains(point) {
            return true
        }
        if let mainPanelWindow,
           let childPanelWindow,
           mainPanelWindow.isVisible,
           childPanelWindow.isVisible {
            let mainFrame = mainPanelWindow.frame
            let childFrame = childPanelWindow.frame
            let corridorMinX = min(mainFrame.maxX, childFrame.maxX)
            let corridorMaxX = max(mainFrame.minX, childFrame.minX)
            let corridorMinY = min(mainFrame.minY, childFrame.minY)
            let corridorMaxY = max(mainFrame.maxY, childFrame.maxY)

            if corridorMaxX > corridorMinX {
                let corridor = NSRect(
                    x: corridorMinX,
                    y: corridorMinY,
                    width: corridorMaxX - corridorMinX,
                    height: corridorMaxY - corridorMinY
                )
                if corridor.contains(point) {
                    return true
                }
            }
        }
        return false
    }

    private func pointIsInsideStatusButton(_ point: NSPoint) -> Bool {
        guard let frame = currentStatusButtonFrame() else { return false }
        return frame.insetBy(dx: -4, dy: -4).contains(point)
    }

    private func positionMainPanel(window: NSWindow, size: NSSize) {
        guard let anchorFrame = mainPanelAnchorFrame ?? currentStatusButtonFrame() else { return }
        let visibleFrame = statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var originX = anchorFrame.midX - size.width / 2
        var originY = anchorFrame.minY - size.height - 5

        originX = min(max(originX, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        originY = max(visibleFrame.minY + 8, originY)

        popoverState.arrowX = anchorFrame.midX - originX
        window.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
    }

    private func positionChildPanel(window: NSWindow, size: NSSize) {
        guard let mainPanelWindow else { return }
        let visibleFrame = mainPanelWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        var originX = mainPanelWindow.frame.maxX + PopoverLayout.panelGap
        if originX + size.width > visibleFrame.maxX - 8 {
            originX = mainPanelWindow.frame.minX - PopoverLayout.panelGap - size.width
        }

        var originY = mainPanelWindow.frame.maxY - PopoverLayout.arrowHeight - size.height
        originY = min(originY, visibleFrame.maxY - size.height - 8)
        originY = max(originY, visibleFrame.minY + 8)

        window.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
    }

    private func positionJDFinanceLoginPanel(window: NSWindow, size: NSSize) {
        let visibleFrame = mainPanelWindow?.screen?.visibleFrame
            ?? statusItem.button?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero

        let originX = min(
            max(visibleFrame.midX - size.width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - size.width - 8
        )
        let originY = min(
            max(visibleFrame.midY - size.height / 2, visibleFrame.minY + 8),
            visibleFrame.maxY - size.height - 8
        )
        window.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
    }

    private func currentStatusButtonFrame() -> NSRect? {
        guard let button = statusItem.button,
              let window = button.window
        else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func setStatusItemHighlighted(_ isHighlighted: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.layer?.cornerRadius = min(button.bounds.width, button.bounds.height) / 2
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = isHighlighted
            ? statusItemHighlightColor().cgColor
            : NSColor.clear.cgColor
        button.needsDisplay = true
    }

    private func statusItemHighlightColor() -> NSColor {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.08)
    }

    @objc func exportAllAccountsFromMenu() {
        PortfolioBackupController.exportAll(accounts: accountsStore)
    }

    @objc func restoreAllAccountsFromMenu() { restoreAllAccounts(latest: false) }
    @objc func restoreLatestAccountsFromMenu() { restoreAllAccounts(latest: true) }

    private func restoreAllAccounts(latest: Bool) {
        guard PortfolioBackupController.restoreAll(accounts: accountsStore, latest: latest) else { return }
        selectedFundCode = nil
        closeAllPanels()
        updateStatusTitle()
        showMainPanel()
    }

    @objc func importFundConfigurationFromMenu() {
        _ = importFundConfiguration()
    }

    @discardableResult
    private func importFundConfiguration() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        ensureFocusedAccountIsSelected()

        let panel = NSOpenPanel()
        panel.title = "导入基金配置"
        panel.prompt = "导入"
        panel.message = "导入到“\(accountsStore.focusedAccount.name)”。选择 fund-pulse 导出的 JSON 配置文件。"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let preview = try store.previewPortfolioImport(from: url)
            let confirmation = NSAlert()
            confirmation.messageText = "替换“\(accountsStore.focusedAccount.name)”的持仓？"
            confirmation.informativeText = "当前 \(store.snapshot.funds.count) 只基金将替换为 \(preview.funds.count) 只基金、\(preview.tradeRecords?.count ?? 0) 条流水。现有数据会先备份到持仓目录的 Backups 文件夹，可通过导入恢复。"
            confirmation.addButton(withTitle: "备份并导入")
            confirmation.addButton(withTitle: "取消")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return false }
            try store.importPortfolio(preview)
            updateStatusTitle()
            sendFundThresholdRemindersIfNeeded()
            showMainPanel()
            return true
        } catch {
            presentConfigurationError(title: "导入基金配置失败", error: error)
            return false
        }
    }

    @objc func exportFundConfigurationFromMenu() {
        NSApp.activate(ignoringOtherApps: true)
        ensureFocusedAccountIsSelected()

        let panel = NSSavePanel()
        panel.title = "导出基金配置"
        panel.prompt = "导出"
        panel.message = "导出“\(accountsStore.focusedAccount.name)”中的基金、待确认交易和交易记录。"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultFundConfigurationFileName()

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportPortfolio(to: url)
        } catch {
            presentConfigurationError(title: "导出基金配置失败", error: error)
        }
    }

    @objc func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func defaultFundConfigurationFileName() -> String {
        let safeAccountName = accountsStore.focusedAccount.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "fund-pulse-\(safeAccountName)-\(DateOnlyFormatter.string(from: .now)).json"
    }

    func openSettingsForFocusedAccount() {
        ensureFocusedAccountIsSelected()
        showMainPanel()
        showChildPanel(.settings)
    }

    private func ensureFocusedAccountIsSelected() {
        guard accountsStore.selection == .all else { return }
        accountsStore.select(.account(accountsStore.focusedAccount.id))
        selectedFundCode = nil
        updateStatusTitle()
        updateMainPanelRootView()
    }

    private func presentConfigurationError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    func refreshQuotesAndStatusTitle() {
        Task { [weak self] in
            guard let self else { return }
            await refreshQuotesAndStatusTitleAsync()
        }
    }

    func handleSettingsChanged() {
        normalizeAccountSelectionForAccountCount()
        updateStatusTitle()
        updateMainPanelRootView()
        refreshVisiblePanels(animatedAppearance: true)
        configureAutoRefreshTimer()
        configureOperationReminder()
        sendFundThresholdRemindersIfNeeded()
        if settingsStore.settings.showsMarketIndexes {
            Task { [weak self] in
                await self?.refreshMarketIndexesIfNeeded(force: true)
            }
        }
    }

    private func refreshQuotesAndStatusTitleAsync() async {
        await accountsStore.refreshQuotes()
        await refreshMarketIndexesIfNeeded()
        updateStatusTitle()
        sendFundThresholdRemindersIfNeeded()
        handleStoreSnapshotChanged()
    }

    private func refreshMarketIndexesIfNeeded(force: Bool = false) async {
        guard settingsStore.settings.showsMarketIndexes else { return }
        await marketIndexStore.refresh(force: force)
    }

    private func configureAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil

        let interval = nextAutoRefreshInterval()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshQuotesAndStatusTitleAsync()
                self.configureAutoRefreshTimer()
            }
        }
        timer.tolerance = min(interval * 0.2, 5)
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    private func nextAutoRefreshInterval(now: Date = .now) -> TimeInterval {
        let interval = settingsStore.settings.effectiveAutoRefreshInterval(now: now).seconds

        guard let boundary = TradingCalendar.nextMarketSessionBoundary(after: now) else {
            return interval
        }

        let boundaryInterval = boundary.timeIntervalSince(now)
        guard boundaryInterval > 0 else { return interval }
        return min(interval, boundaryInterval)
    }

    private func configureOperationReminder() {
        let isEnabled = settingsStore.settings.operationReminderEnabled
        let reminderMinutes = settingsStore.settings.operationReminderTimeMinutes
        let clampedMinutes = AppSettings.clampedReminderTimeMinutes(reminderMinutes)
        let requests = TradingCalendar.nextMarketOpenReminderDates(minutes: clampedMinutes).map { reminderDate in
            OperationReminderNotificationRequest(
                identifier: "\(operationReminderNotificationPrefix)\(DateOnlyFormatter.string(from: reminderDate))",
                title: OperationReminderNotificationContent.title,
                body: OperationReminderNotificationContent.body,
                fireDate: reminderDate
            )
        }
        operationReminderScheduler.configure(isEnabled: isEnabled, requests: requests)
    }

    nonisolated static func operationReminderNotificationIdentifiersToClear(from identifiers: [String]) -> [String] {
        Set(identifiers.filter(isOperationReminderNotificationID) + [operationReminderNotificationID]).sorted()
    }

    nonisolated static func operationReminderNotificationIdentifiersToClear(
        from candidates: [OperationReminderNotificationCandidate]
    ) -> [String] {
        Set(
            candidates.filter { candidate in
                isOperationReminderNotificationID(candidate.identifier)
                    || isOperationReminderNotificationContent(title: candidate.title, body: candidate.body)
            }.map(\.identifier) + [operationReminderNotificationID]
        ).sorted()
    }

    nonisolated private static func isOperationReminderNotificationID(_ identifier: String) -> Bool {
        identifier == operationReminderNotificationID || identifier.hasPrefix(operationReminderNotificationPrefix)
    }

    nonisolated private static func isOperationReminderNotificationContent(title: String, body: String) -> Bool {
        title == OperationReminderNotificationContent.title && body == OperationReminderNotificationContent.body
    }

    nonisolated private static func operationReminderNotificationCandidate(
        from request: UNNotificationRequest
    ) -> OperationReminderNotificationCandidate {
        OperationReminderNotificationCandidate(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body
        )
    }

    private func sendFundThresholdRemindersIfNeeded() {
        let now = Date()
        let reminders = FundThresholdReminderEvaluator.eligibleReminders(
            in: store.snapshot,
            settings: settingsStore.settings,
            now: now,
            lastSentAt: fundThresholdReminderLastSentAt
        )
        let unsentReminders = reminders.filter {
            !pendingFundThresholdReminderKeys.contains($0.dedupeKey)
        }
        guard !unsentReminders.isEmpty else { return }

        pendingFundThresholdReminderKeys.formUnion(unsentReminders.map(\.dedupeKey))

        Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                await MainActor.run {
                    unsentReminders.forEach { self?.markFundThresholdReminderFinished($0.dedupeKey) }
                }
                return
            }

            for reminder in unsentReminders {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default

                let request = UNNotificationRequest(
                    identifier: "\(reminder.notificationIdentifier).\(Int(now.timeIntervalSince1970))",
                    content: content,
                    trigger: nil
                )

                do {
                    try await center.add(request)
                    await MainActor.run {
                        self?.markFundThresholdReminderSent(reminder.dedupeKey, at: now)
                    }
                } catch {
                    await MainActor.run {
                        self?.markFundThresholdReminderFinished(reminder.dedupeKey)
                    }
                    continue
                }
            }
        }
    }

    private func markFundThresholdReminderSent(_ key: String, at date: Date) {
        fundThresholdReminderLastSentAt[key] = date
        pendingFundThresholdReminderKeys.remove(key)
        saveFundThresholdReminderLastSentAt()
    }

    private func markFundThresholdReminderFinished(_ key: String) {
        pendingFundThresholdReminderKeys.remove(key)
    }

    private func saveFundThresholdReminderLastSentAt() {
        UserDefaults.standard.set(
            fundThresholdReminderLastSentAt.mapValues(\.timeIntervalSince1970),
            forKey: fundThresholdReminderLastSentDefaultsKey
        )
    }

    private static func loadFundThresholdReminderLastSentAt() -> [String: Date] {
        let rawValues = UserDefaults.standard.dictionary(forKey: fundThresholdReminderLastSentDefaultsKey) as? [String: Double] ?? [:]
        let earliestDate = Date().addingTimeInterval(-FundThresholdReminderInterval.oneDay.seconds)
        let values = rawValues.compactMapValues { timestamp -> Date? in
            let date = Date(timeIntervalSince1970: timestamp)
            return date >= earliestDate ? date : nil
        }
        UserDefaults.standard.set(
            values.mapValues(\.timeIntervalSince1970),
            forKey: fundThresholdReminderLastSentDefaultsKey
        )
        return values
    }

    private func deleteFund(_ fund: FundPosition) async {
        do {
            try await store.deleteFund(code: fund.code)
            updateStatusTitle()
            if activeChildPanel?.selectedFundCode == fund.code {
                hideChildPanel()
            } else {
                handleStoreSnapshotChanged()
            }
        } catch {
            // Keep the existing data visible; PortfolioStore.loadState will surface refresh failures.
        }
    }

    private func deletePendingActivity(_ activity: PendingTradeActivity) async {
        do {
            if let recordID = activity.recordID {
                try await store.deleteTradeRecord(id: recordID)
            } else {
                try await store.deleteFund(code: activity.code)
            }
            updateStatusTitle()
            handleStoreSnapshotChanged()
            updateMainPanelRootView()
        } catch {
            refreshVisiblePanels()
        }
    }

    private func deleteTradeRecord(_ record: FundTradeRecord, returningToFundCode fundCode: String) async {
        do {
            try await store.deleteTradeRecord(id: record.id)
            updateStatusTitle()
            showChildPanel(.tradeRecords(fundCode: fundCode))
            updateMainPanelRootView()
        } catch {
            refreshVisiblePanels()
        }
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        stopContextMenuUpdateRefresh()
    }
}
