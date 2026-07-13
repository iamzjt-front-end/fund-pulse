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
private let statusBarUpdateLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.iamzjt.frontend.fund-pulse.swift",
    category: "AppUpdate"
)

private final class ContextMenuUpdateCheckResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: AppUpdateCheckCompletion?

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

private struct ContextMenuUpdateCheck {
    var id: UUID
    var request: AppUpdateCheckRequest
    var resultBox: ContextMenuUpdateCheckResultBox
    var task: Task<Void, Never>
}

private extension AppAppearanceMode {
    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

private final class AppearanceTransitionOverlayView: NSView {
    private let gradientLayer = CAGradientLayer()

    init(appearance: NSAppearance) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = gradientLayer
        configure(for: appearance)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func configure(for appearance: NSAppearance) {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let leading = isDark
            ? NSColor(red: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 0.96)
            : NSColor(red: 251 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.94)
        let trailing = isDark
            ? NSColor(red: 29 / 255, green: 33 / 255, blue: 42 / 255, alpha: 0.86)
            : NSColor(red: 242 / 255, green: 238 / 255, blue: 229 / 255, alpha: 0.80)
        gradientLayer.colors = [leading.cgColor, trailing.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }
}

private enum StatusItemPresentation {
    static let height: CGFloat = 24
    static let iconSize: CGFloat = 16

    static func visualLength(
        for text: String,
        attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        return ceil(iconSize + textWidth)
    }
}

private struct StatusTitlePresentation {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let visualLength: CGFloat
}

private func makeStatusPulseImage(size: NSSize, tintColor: NSColor? = nil) -> NSImage {
    let image = NSImage(size: size, flipped: false) { rect in
        let color = tintColor ?? .labelColor
        color.setStroke()
        color.setFill()

        let path = NSBezierPath()
        path.lineWidth = tintColor == nil ? 1.8 : 2.05
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX + 1.6, y: rect.minY + 8.0))
        path.line(to: NSPoint(x: rect.minX + 4.6, y: rect.minY + 8.0))
        path.line(to: NSPoint(x: rect.minX + 6.4, y: rect.minY + 13.0))
        path.line(to: NSPoint(x: rect.minX + 9.5, y: rect.minY + 4.0))
        path.line(to: NSPoint(x: rect.minX + 11.5, y: rect.minY + 10.0))
        path.line(to: NSPoint(x: rect.minX + 14.4, y: rect.minY + 10.0))
        path.stroke()

        NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + 12.0,
                y: rect.minY + 12.5,
                width: 2.8,
                height: 2.8
            )
        ).fill()
        return true
    }
    image.isTemplate = tintColor == nil
    return image
}

enum PopoverLayout {
    static let mainWidth: CGFloat = 360
    static let jdFinanceLoginWidth: CGFloat = 1040
    static let jdFinancePreviewWidth: CGFloat = 430
    static let jdFinanceSyncHeight: CGFloat = 720
    static let settingsWidth: CGFloat = 320
    static let editorWidth: CGFloat = 360
    static let editorHeight: CGFloat = 600
    static let tradeEditorHeight: CGFloat = 660
    static let fundDetailHeight: CGFloat = 660
    static let tradeRecordsHeight: CGFloat = 520
    static let portfolioBreakdownWidth: CGFloat = 392
    static let portfolioBreakdownHeight: CGFloat = 600
    static let todayIncomeRankingWidth: CGFloat = 392
    static let todayIncomeRankingHeight: CGFloat = 600
    static let fundDailyIncomeWidth: CGFloat = 392
    static let fundDailyIncomeHeight: CGFloat = 600
    static let height: CGFloat = CGFloat(AppSettings.defaultMainPanelHeight)
    static let arrowHeight: CGFloat = 10
    static let arrowWidth: CGFloat = 22
    static let cornerRadius: CGFloat = 16
    static let panelGap: CGFloat = 3

    static let mainSize = mainContentSize(forHeight: height)
    static let windowHeight: CGFloat = mainWindowHeight(forHeight: height)
    static let mainWindowSize = mainWindowFrameSize(forHeight: height)
    static let jdFinanceLoginSize = NSSize(width: jdFinanceLoginWidth, height: jdFinanceSyncHeight)
    static let jdFinanceNetworkProbeSize = NSSize(width: jdFinancePreviewWidth, height: jdFinanceSyncHeight)
    static let jdFinanceSyncSize = NSSize(width: jdFinancePreviewWidth, height: jdFinanceSyncHeight)
    static let settingsSize = NSSize(width: settingsWidth, height: height)
    static let editorSize = NSSize(width: editorWidth, height: editorHeight)
    static let tradeEditorSize = NSSize(width: editorWidth, height: tradeEditorHeight)
    static let fundDetailSize = NSSize(width: editorWidth, height: fundDetailHeight)
    static let tradeRecordsSize = NSSize(width: editorWidth, height: tradeRecordsHeight)
    static let portfolioBreakdownSize = NSSize(width: portfolioBreakdownWidth, height: portfolioBreakdownHeight)
    static let todayIncomeRankingSize = NSSize(width: todayIncomeRankingWidth, height: todayIncomeRankingHeight)
    static let fundDailyIncomeSize = NSSize(width: fundDailyIncomeWidth, height: fundDailyIncomeHeight)

    static func clampedMainPanelHeight(_ height: CGFloat) -> CGFloat {
        CGFloat(AppSettings.clampedMainPanelHeight(Int(height.rounded())))
    }

    static func mainContentSize(forHeight height: CGFloat) -> NSSize {
        NSSize(width: mainWidth, height: clampedMainPanelHeight(height))
    }

    static func mainWindowHeight(forHeight height: CGFloat) -> CGFloat {
        clampedMainPanelHeight(height) + arrowHeight
    }

    static func mainWindowFrameSize(forHeight height: CGFloat) -> NSSize {
        NSSize(width: mainWidth, height: mainWindowHeight(forHeight: height))
    }

}

@Observable
@MainActor
final class PopoverUIState {
    var arrowX: CGFloat = PopoverLayout.mainWidth / 2
}

private final class FundPulsePanel: NSPanel {
    var onOrderOut: (() -> Void)?
    var onClose: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func orderOut(_ sender: Any?) {
        let wasVisible = isVisible
        super.orderOut(sender)
        if wasVisible {
            onOrderOut?()
        }
    }

    override func close() {
        let wasVisible = isVisible
        super.close()
        if wasVisible {
            onClose?()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class PanelCardContainerView: NSView {
    let hostedContentView: NSView

    init(contentView: NSView, cornerRadius: CGFloat = PopoverLayout.cornerRadius) {
        hostedContentView = contentView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        updateAppearanceColors()
        translatesAutoresizingMaskIntoConstraints = false

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize {
        hostedContentView.fittingSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceColors()
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        self.appearance = appearance
        hostedContentView.appearance = appearance
        updateAppearanceColors()
    }

    private func updateAppearanceColors() {
        let appearance = effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (isDark
            ? NSColor(red: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 0.98)
            : NSColor(red: 251 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.99)
        ).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = (isDark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.06)
        ).cgColor
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: PortfolioStore
    private let settingsStore: AppSettingsStore
    private let marketIndexStore: MarketIndexStore
    private let updateStore: AppUpdateStore
    private let appVersion: String
    private let popoverState = PopoverUIState()
    private lazy var statusPulseImage = makeStatusPulseImage(
        size: NSSize(width: StatusItemPresentation.iconSize, height: StatusItemPresentation.iconSize)
    )
    private let onCheckUpdate: (AppUpdateCheckMode) async -> Void
    private let onOpenUpdate: () -> Void

    private var mainPanelWindow: FundPulsePanel?
    private var childPanelWindow: FundPulsePanel?
    private var jdFinanceLoginWindow: FundPulsePanel?
    private var mainPanelHostingView: NSHostingView<MainPanelWindowView>?
    private var activeChildPanel: ChildPanelRoute?
    private var selectedFundCode: String?
    private var jdFinanceLoginCompletion: ((String?) -> Void)?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var mainPanelAnchorFrame: NSRect?
    private var autoRefreshTimer: Timer?
    private weak var contextMenuUpdateItem: NSMenuItem?
    private var contextMenuUpdateRefreshTimer: Timer?
    private var contextMenuUpdateAnimationFrame = 2
    private var contextMenuUpdateStatusOverride: AppUpdateStatus?
    private var contextMenuUpdateCheck: ContextMenuUpdateCheck?
    private var fundThresholdReminderLastSentAt: [String: Date] = [:]
    private var pendingFundThresholdReminderKeys: Set<String> = []

    private lazy var operationReminderScheduler: OperationReminderNotificationScheduler = {
        let center = UNUserNotificationCenter.current()
        return OperationReminderNotificationScheduler(
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
            }
        )
    }()

    private var mainPanelHeight: CGFloat {
        PopoverLayout.clampedMainPanelHeight(CGFloat(settingsStore.settings.mainPanelHeight))
    }

    private var mainPanelWindowSize: NSSize {
        PopoverLayout.mainWindowFrameSize(forHeight: mainPanelHeight)
    }

    private var panelAppearance: NSAppearance? {
        settingsStore.settings.appearanceMode.nsAppearance
    }

    init(
        store: PortfolioStore,
        settingsStore: AppSettingsStore,
        marketIndexStore: MarketIndexStore,
        updateStore: AppUpdateStore,
        appVersion: String,
        onCheckUpdate: @escaping (AppUpdateCheckMode) async -> Void,
        onOpenUpdate: @escaping () -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.marketIndexStore = marketIndexStore
        self.updateStore = updateStore
        self.appVersion = appVersion
        self.onCheckUpdate = onCheckUpdate
        self.onOpenUpdate = onOpenUpdate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

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
        let amountValue = store.snapshot.todayIncome
        let rateValue = store.snapshot.todayIncomeRate
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

        store.load()
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

        let hostingView = NSHostingView(rootView: makeMainPanelRootView())
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
        mainPanelHostingView?.rootView = makeMainPanelRootView()
    }

    private func makeMainPanelRootView() -> MainPanelWindowView {
        MainPanelWindowView(
            store: store,
            settingsStore: settingsStore,
            marketIndexStore: marketIndexStore,
            updateStore: updateStore,
            uiState: popoverState,
            selectedFundCode: selectedFundCode,
            onRefresh: { [weak self] in
                await self?.refreshQuotesAndStatusTitleAsync()
            },
            onOpenSettings: { [weak self] in
                self?.showChildPanel(.settings)
            },
            onClose: { [weak self] in
                self?.closeAllPanels()
            },
            onOpenPortfolioBreakdown: { [weak self] in
                self?.showChildPanel(.portfolioBreakdown)
            },
            onOpenTodayIncomeRanking: { [weak self] in
                self?.showChildPanel(.incomeRanking(.today, .amount))
            },
            onOpenTodayRateRanking: { [weak self] in
                self?.showChildPanel(.incomeRanking(.today, .rate))
            },
            onOpenHoldingIncomeRanking: { [weak self] in
                self?.showChildPanel(.incomeRanking(.holding, .amount))
            },
            onOpenHoldingRateRanking: { [weak self] in
                self?.showChildPanel(.incomeRanking(.holding, .rate))
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

    private func showChildPanel(_ route: ChildPanelRoute) {
        if mainPanelWindow?.isVisible != true {
            showMainPanel()
        }

        if case .jdFinanceSync = activeChildPanel,
           case .jdFinanceSync = route {
        } else if case .jdFinanceSync = activeChildPanel {
            hideJDFinanceLoginPanel(reportCancellation: true)
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
        showChildPanel(.jdFinanceSync)
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
        let container = PanelCardContainerView(contentView: NSHostingView(rootView: AnyView(view)))
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
        let container = PanelCardContainerView(contentView: NSHostingView(rootView: AnyView(view)))
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
        case .settings:
            let view = SettingsView(
                store: store,
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
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.settingsSize)

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
                    self?.handleStoreSnapshotChanged()
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.jdFinanceSyncSize)

        case .portfolioBreakdown:
            let view = PortfolioAllocationPanelView(
                store: store,
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.portfolioBreakdownSize)

        case .incomeRanking(let kind, let metric):
            let view = TodayIncomeRankingPanelView(
                store: store,
                kind: kind,
                metric: metric,
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.todayIncomeRankingSize)

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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.editorSize)

        case .fundDetail(let fundCode):
            let view = FundDetailView(
                store: store,
                fundCode: fundCode,
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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.fundDetailSize)

        case .fundDailyIncome(let fundCode):
            let view = FundDailyIncomePanelView(
                store: store,
                fundCode: fundCode,
                onClose: { [weak self] in
                    self?.showChildPanel(.fundDetail(fundCode: fundCode))
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.fundDailyIncomeSize)

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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeRecordsSize)

        case .buyFund(let fundCode):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }) else { return nil }
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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

        case .sellFund(let fundCode):
            guard let fund = store.snapshot.funds.first(where: { $0.code == fundCode }) else { return nil }
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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

        case .convertFund(let fundCode):
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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

        case .editTradeRecord(let fundCode, let recordID):
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
                        self?.showChildPanel(.tradeRecords(fundCode: fundCode))
                    }
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.tradeRecords(fundCode: fundCode))
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

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
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.editorSize)
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
        if case .jdFinanceSync = activeChildPanel {
            hideJDFinanceLoginPanel(reportCancellation: true)
        }
        childPanelWindow?.orderOut(nil)
        clearChildPanelState()
    }

    private func handleChildPanelCancel() {
        if case .tradeRecords(let fundCode) = activeChildPanel {
            showChildPanel(.fundDetail(fundCode: fundCode))
        } else if case .fundDailyIncome(let fundCode) = activeChildPanel {
            showChildPanel(.fundDetail(fundCode: fundCode))
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

    private func closeAllPanels() {
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
        case .jdFinanceSync:
            size = PopoverLayout.jdFinanceSyncSize
        case .portfolioBreakdown:
            size = PopoverLayout.portfolioBreakdownSize
        case .incomeRanking:
            size = PopoverLayout.todayIncomeRankingSize
        case .fundDetail:
            size = PopoverLayout.fundDetailSize
        case .fundDailyIncome:
            size = PopoverLayout.fundDailyIncomeSize
        case .tradeRecords:
            size = PopoverLayout.tradeRecordsSize
        case .addFund, .editFund:
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

    private func showContextMenu(relativeTo sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(disabledMenuItem("fund-pulse v\(appVersion)"))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "刷新基金数据", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())

        addUpdateMenuItems(to: menu)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        addMenuBarConfigurationMenuItems(to: menu)
        menu.addItem(NSMenuItem(title: "导入基金配置", action: #selector(importFundConfigurationFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出基金配置", action: #selector(exportFundConfigurationFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        closeAllPanels()
        startContextMenuUpdateRefresh()
        let startedUpdateCheck = checkForUpdatesFromContextMenu()
        if startedUpdateCheck {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.popUpContextMenu(menu)
            }
            return
        }
        popUpContextMenu(menu)
    }

    private func popUpContextMenu(_ menu: NSMenu) {
        let popUpMenuSelector = NSSelectorFromString("popUpStatusItemMenu:")
        _ = statusItem.perform(popUpMenuSelector, with: menu)
    }

    private func addMenuBarConfigurationMenuItems(to menu: NSMenu) {
        let contentItem = NSMenuItem(title: "显示内容", action: nil, keyEquivalent: "")
        contentItem.submenu = makeMenuBarContentModeMenu()
        contentItem.isEnabled = true
        menu.addItem(contentItem)

        let displayItem = NSMenuItem(title: "涨跌颜色", action: nil, keyEquivalent: "")
        displayItem.submenu = makeMenuBarDisplayModeMenu()
        displayItem.isEnabled = true
        menu.addItem(displayItem)
    }

    private func makeMenuBarContentModeMenu() -> NSMenu {
        let submenu = NSMenu(title: "显示内容")
        for mode in MenuBarContentMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectMenuBarContentModeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settingsStore.settings.menuBarContentMode == mode ? .on : .off
            item.toolTip = mode.detail
            submenu.addItem(item)
        }
        return submenu
    }

    private func makeMenuBarDisplayModeMenu() -> NSMenu {
        let submenu = NSMenu(title: "涨跌颜色")
        for mode in MenuBarDisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectMenuBarDisplayModeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settingsStore.settings.menuBarDisplayMode == mode ? .on : .off
            item.toolTip = mode.detail
            submenu.addItem(item)
        }
        return submenu
    }

    private func addUpdateMenuItems(to menu: NSMenu) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        applyUpdateMenuPresentation(to: item)
        contextMenuUpdateItem = item
        menu.addItem(item)
    }

    private func applyUpdateMenuPresentation(to item: NSMenuItem) {
        let presentation = AppUpdateMenuItemPresentation(
            status: contextMenuUpdateStatusOverride ?? updateStore.status,
            downloadProgress: updateStore.downloadProgress,
            activityFrame: contextMenuUpdateAnimationFrame
        )
        item.view = nil
        item.title = presentation.title
        item.action = updateMenuActionSelector(for: presentation.action)
        item.isEnabled = presentation.isEnabled
        item.toolTip = presentation.toolTip
        item.menu?.itemChanged(item)
    }

    private func startContextMenuUpdateRefresh() {
        contextMenuUpdateRefreshTimer?.invalidate()
        contextMenuUpdateRefreshTimer = nil
        contextMenuUpdateStatusOverride = nil
        contextMenuUpdateAnimationFrame = 2
        refreshContextMenuUpdateItem()

        let timer = Timer(
            timeInterval: 0.35,
            target: self,
            selector: #selector(contextMenuUpdateRefreshTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        contextMenuUpdateRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    @objc private func contextMenuUpdateRefreshTimerFired(_ timer: Timer) {
        finishContextMenuUpdateCheckIfReady()
        refreshContextMenuUpdateItem()
    }

    private func refreshContextMenuUpdateItem() {
        guard let contextMenuUpdateItem else {
            if contextMenuUpdateCheck == nil {
                stopContextMenuUpdateRefresh()
            }
            return
        }
        applyUpdateMenuPresentation(to: contextMenuUpdateItem)
        contextMenuUpdateAnimationFrame += 1
    }

    private func stopContextMenuUpdateRefresh(cancelPendingCheck: Bool = false) {
        if cancelPendingCheck {
            contextMenuUpdateCheck?.task.cancel()
            contextMenuUpdateCheck = nil
        }
        if contextMenuUpdateCheck == nil {
            contextMenuUpdateRefreshTimer?.invalidate()
            contextMenuUpdateRefreshTimer = nil
        }
        contextMenuUpdateItem = nil
        contextMenuUpdateStatusOverride = nil
    }

    private func checkForUpdatesFromContextMenu() -> Bool {
        finishContextMenuUpdateCheckIfReady()
        if contextMenuUpdateCheck != nil {
            contextMenuUpdateStatusOverride = .checking
            refreshContextMenuUpdateItem()
            return true
        }
        guard updateStore.status.shouldCheckWhenOpeningContextMenu else { return false }
        guard let request = updateStore.startCheck(currentVersion: appVersion, mode: .interactive) else { return false }
        let checkID = UUID()
        let resultBox = ContextMenuUpdateCheckResultBox()
        let task = Task.detached(priority: .userInitiated) { [request, resultBox] in
            let completion: AppUpdateCheckCompletion
            do {
                let status = try await request.service.check(
                    currentVersion: request.currentVersion,
                    mode: request.mode
                )
                completion = .success(status)
            } catch {
                completion = .failure(error.localizedDescription)
            }
            resultBox.set(completion)
        }
        contextMenuUpdateCheck = ContextMenuUpdateCheck(
            id: checkID,
            request: request,
            resultBox: resultBox,
            task: task
        )
        contextMenuUpdateStatusOverride = .checking
        refreshContextMenuUpdateItem()
        statusBarUpdateLogger.info("Start context menu update check generation=\(request.generation, privacy: .public)")
        return true
    }

    @discardableResult
    private func finishContextMenuUpdateCheckIfReady(id: UUID? = nil) -> Bool {
        guard let check = contextMenuUpdateCheck,
              id == nil || id == check.id,
              let completion = check.resultBox.take()
        else { return false }

        contextMenuUpdateCheck = nil
        contextMenuUpdateStatusOverride = nil
        updateStore.finishCheck(check.request, completion: completion)
        statusBarUpdateLogger.info("Finish context menu update check generation=\(check.request.generation, privacy: .public)")
        return true
    }

    private func updateMenuActionSelector(for action: AppUpdateMenuItemAction?) -> Selector? {
        switch action {
        case .checkForUpdates:
            #selector(checkUpdateFromMenu)
        case .openUpdate:
            #selector(openUpdateFromMenu)
        case nil:
            nil
        }
    }

    private func disabledMenuItem(_ title: String, toolTip: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = toolTip
        return item
    }

    private func checkForUpdates() {
        Task { [weak self] in
            await self?.onCheckUpdate(.interactive)
        }
    }

    @objc private func refreshFromMenu() {
        refreshQuotesAndStatusTitle()
    }

    @objc private func checkUpdateFromMenu() {
        checkForUpdates()
    }

    @objc private func openUpdateFromMenu() {
        onOpenUpdate()
    }

    @objc private func openSettingsFromMenu() {
        showMainPanel()
        showChildPanel(.settings)
    }

    @objc private func selectMenuBarContentModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = MenuBarContentMode(rawValue: rawValue)
        else { return }
        settingsStore.setMenuBarContentMode(mode)
        handleSettingsChanged()
    }

    @objc private func selectMenuBarDisplayModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = MenuBarDisplayMode(rawValue: rawValue)
        else { return }
        settingsStore.setMenuBarDisplayMode(mode)
        handleSettingsChanged()
    }

    @objc private func importFundConfigurationFromMenu() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "导入基金配置"
        panel.prompt = "导入"
        panel.message = "选择 fund-pulse 导出的 JSON 配置文件。"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.importPortfolio(from: url)
            updateStatusTitle()
            sendFundThresholdRemindersIfNeeded()
            showMainPanel()
        } catch {
            presentConfigurationError(title: "导入基金配置失败", error: error)
        }
    }

    @objc private func exportFundConfigurationFromMenu() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "导出基金配置"
        panel.prompt = "导出"
        panel.message = "导出当前录入的基金、持仓日期、待确认交易和交易记录。"
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

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func defaultFundConfigurationFileName() -> String {
        "fund-pulse-portfolio-\(DateOnlyFormatter.string(from: .now)).json"
    }

    private func presentConfigurationError(title: String, error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func refreshQuotesAndStatusTitle() {
        Task { [weak self] in
            guard let self else { return }
            await refreshQuotesAndStatusTitleAsync()
        }
    }

    private func handleSettingsChanged() {
        updateStatusTitle()
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
        await store.refreshQuotes()
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
