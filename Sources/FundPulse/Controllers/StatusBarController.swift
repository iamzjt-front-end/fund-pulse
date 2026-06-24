import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import UserNotifications

private let operationReminderNotificationID = "fund-pulse.operation-reminder"

private enum StatusItemPresentation {
    static let height: CGFloat = 24
    static let iconSize: CGFloat = 16
    static let hiddenLength: CGFloat = iconSize

    static func visualLength(
        for text: String,
        attributes: [NSAttributedString.Key: Any],
        isHidden: Bool
    ) -> CGFloat {
        if isHidden {
            return hiddenLength
        }

        let textWidth = (text as NSString).size(withAttributes: attributes).width
        return ceil(iconSize + textWidth)
    }
}

private struct StatusTitlePresentation {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let isHidden: Bool
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
    static let settingsWidth: CGFloat = 320
    static let editorWidth: CGFloat = 360
    static let editorHeight: CGFloat = 600
    static let tradeEditorHeight: CGFloat = 514
    static let fundDetailHeight: CGFloat = 660
    static let tradeRecordsHeight: CGFloat = 520
    static let height: CGFloat = CGFloat(AppSettings.defaultMainPanelHeight)
    static let arrowHeight: CGFloat = 10
    static let arrowWidth: CGFloat = 22
    static let cornerRadius: CGFloat = 16
    static let panelGap: CGFloat = 3

    static let mainSize = mainContentSize(forHeight: height)
    static let windowHeight: CGFloat = mainWindowHeight(forHeight: height)
    static let mainWindowSize = mainWindowFrameSize(forHeight: height)
    static let settingsSize = NSSize(width: settingsWidth, height: height)
    static let editorSize = NSSize(width: editorWidth, height: editorHeight)
    static let tradeEditorSize = NSSize(width: editorWidth, height: tradeEditorHeight)
    static let fundDetailSize = NSSize(width: editorWidth, height: fundDetailHeight)
    static let tradeRecordsSize = NSSize(width: editorWidth, height: tradeRecordsHeight)

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

private enum ChildPanelKind {
    case settings
    case addFund
    case fundDetail(FundPosition)
    case tradeRecords(FundPosition)
    case buyFund(FundPosition)
    case sellFund(FundPosition)
    case editTradeRecord(FundPosition, FundTradeRecord)
    case editFund(FundPosition)

    var selectedFundCode: String? {
        switch self {
        case .fundDetail(let fund), .tradeRecords(let fund), .buyFund(let fund), .sellFund(let fund), .editTradeRecord(let fund, _), .editFund(let fund):
            fund.code
        case .settings, .addFund:
            nil
        }
    }
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
        contentView.appearance = NSApp.effectiveAppearance
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
        hostedContentView.appearance = NSApp.effectiveAppearance
    }

    private func updateAppearanceColors() {
        let appearance = NSApp.effectiveAppearance
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
    private let updateStore: AppUpdateStore
    private let appVersion: String
    private let popoverState = PopoverUIState()
    private lazy var statusPulseImage = makeStatusPulseImage(
        size: NSSize(width: StatusItemPresentation.iconSize, height: StatusItemPresentation.iconSize)
    )
    private let onCheckUpdate: () async -> Void
    private let onOpenUpdate: () -> Void

    private var mainPanelWindow: FundPulsePanel?
    private var childPanelWindow: FundPulsePanel?
    private var mainPanelHostingView: NSHostingView<MainPanelWindowView>?
    private var activeChildPanel: ChildPanelKind?
    private var selectedFundCode: String?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var amountPrivacyObserver: NSObjectProtocol?
    private var mainPanelAnchorFrame: NSRect?
    private var autoRefreshTimer: Timer?
    private var isRefreshingQuotes = false

    private var mainPanelHeight: CGFloat {
        PopoverLayout.clampedMainPanelHeight(CGFloat(settingsStore.settings.mainPanelHeight))
    }

    private var mainPanelWindowSize: NSSize {
        PopoverLayout.mainWindowFrameSize(forHeight: mainPanelHeight)
    }

    init(
        store: PortfolioStore,
        settingsStore: AppSettingsStore,
        updateStore: AppUpdateStore,
        appVersion: String,
        onCheckUpdate: @escaping () async -> Void,
        onOpenUpdate: @escaping () -> Void
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.updateStore = updateStore
        self.appVersion = appVersion
        self.onCheckUpdate = onCheckUpdate
        self.onOpenUpdate = onOpenUpdate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configureAmountPrivacyObserver()
        updateStatusTitle()
        configureAutoRefreshTimer()
        configureOperationReminder()
        refreshQuotesAndStatusTitle()
    }

    func invalidate() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        removeEventMonitors()
        if let amountPrivacyObserver {
            NotificationCenter.default.removeObserver(amountPrivacyObserver)
            self.amountPrivacyObserver = nil
        }
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
        statusItem.length = StatusItemPresentation.hiddenLength
    }

    func updateStatusTitle(animated: Bool = false) {
        let presentation = currentStatusTitlePresentation()
        guard let button = statusItem.button else { return }
        button.toolTip = presentation.isHidden ? "显示金额" : "隐藏金额"
        if presentation.isHidden {
            button.image = makeStatusPulseImage(
                size: NSSize(width: StatusItemPresentation.iconSize, height: StatusItemPresentation.iconSize),
                tintColor: StatusBarTone.menuBarColor(forRate: store.snapshot.todayIncomeRate).withAlphaComponent(0.96)
            )
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
        } else {
            button.image = statusPulseImage
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(
                string: presentation.text,
                attributes: presentation.attributes
            )
        }
        setStatusItemLength(for: presentation)
    }

    private func currentStatusTitlePresentation() -> StatusTitlePresentation {
        let value = store.snapshot.todayIncome
        let isHidden = UserDefaults.standard.bool(forKey: AppPreferenceKey.hideHeaderAmounts)
        let font = statusTitleFont(forHiddenState: isHidden)
        let text = statusTitleText(for: signedStatusText(value), isHidden: isHidden)
        let attributes = statusTitleAttributes(for: value, font: font, isHidden: isHidden)
        let visualLength = StatusItemPresentation.visualLength(
            for: text,
            attributes: attributes,
            isHidden: isHidden
        )

        return StatusTitlePresentation(
            text: text,
            attributes: attributes,
            isHidden: isHidden,
            visualLength: visualLength
        )
    }

    private func setStatusItemLength(for presentation: StatusTitlePresentation) {
        let systemButtonPadding: CGFloat = presentation.isHidden ? 8 : 10
        statusItem.length = ceil(presentation.visualLength + systemButtonPadding)
    }

    private func statusTitleFont(forHiddenState isHidden: Bool) -> NSFont {
        if isHidden {
            return .systemFont(ofSize: 12, weight: .semibold)
        }
        return .systemFont(ofSize: NSFont.systemFontSize)
    }

    private func statusTitleText(for amountText: String, isHidden: Bool) -> String {
        if isHidden {
            return ""
        }
        return amountText
    }

    private func statusTitleAttributes(
        for value: Double,
        font: NSFont,
        isHidden: Bool
    ) -> [NSAttributedString.Key: Any] {
        let color = statusTitleColor(for: value)
        return [
            .font: font,
            .foregroundColor: isHidden ? color.withAlphaComponent(0.86) : color
        ]
    }

    private func signedStatusText(_ value: Double) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return "\(sign)\(abs(value).formatted(.number.precision(.fractionLength(2))))"
    }

    private func statusTitleColor(for value: Double) -> NSColor {
        if value > 0 { return .systemRed }
        if value < 0 { return .systemGreen }
        return .secondaryLabelColor
    }

    private func configureAmountPrivacyObserver() {
        amountPrivacyObserver = NotificationCenter.default.addObserver(
            forName: .fundPulseAmountPrivacyDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatusTitle(animated: true)
            }
        }
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
        window.appearance = NSApp.effectiveAppearance
        window.contentView?.appearance = NSApp.effectiveAppearance
        setStatusItemHighlighted(true)

        store.load()
        updateStatusTitle()
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
        mainPanelHostingView = hostingView
        window.contentView = hostingView
        mainPanelWindow = window
        return window
    }

    private func updateMainPanelRootView() {
        mainPanelHostingView?.rootView = makeMainPanelRootView()
    }

    private func makeMainPanelRootView() -> MainPanelWindowView {
        MainPanelWindowView(
            store: store,
            updateStore: updateStore,
            uiState: popoverState,
            mainPanelHeight: mainPanelHeight,
            selectedFundCode: selectedFundCode,
            onRefresh: { [weak self] in
                await self?.refreshQuotesAndStatusTitleAsync()
            },
            onOpenSettings: { [weak self] in
                self?.showChildPanel(.settings)
            },
            onAddFund: { [weak self] in
                self?.showChildPanel(.addFund)
            },
            onOpenFundDetail: { [weak self] fund in
                self?.showChildPanel(.fundDetail(fund))
            },
            onBuyFund: { [weak self] fund in
                self?.showChildPanel(.buyFund(fund))
            },
            onSellFund: { [weak self] fund in
                self?.showChildPanel(.sellFund(fund))
            },
            onEditFund: { [weak self] fund in
                self?.showChildPanel(.editFund(fund))
            },
            onDeleteFund: { [weak self] fund in
                await self?.deleteFund(fund)
            },
            onCheckUpdate: { [weak self] in
                await self?.onCheckUpdate()
            },
            onOpenUpdate: { [weak self] in
                self?.onOpenUpdate()
            }
        )
    }

    private func showChildPanel(_ kind: ChildPanelKind) {
        if mainPanelWindow?.isVisible != true {
            showMainPanel()
        }

        guard let (contentView, size) = makeChildPanelContent(for: kind) else { return }
        activeChildPanel = kind
        selectedFundCode = kind.selectedFundCode
        updateMainPanelRootView()

        let window = childPanelWindow ?? createChildPanelWindow()
        window.appearance = NSApp.effectiveAppearance
        let container = PanelCardContainerView(contentView: contentView)
        container.frame = NSRect(origin: .zero, size: size)
        container.appearance = NSApp.effectiveAppearance
        window.contentView = container
        window.setContentSize(size)
        positionChildPanel(window: window, size: size)
        window.orderFrontRegardless()
        window.makeKey()
        installEventMonitorsIfNeeded()
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

    private func makeChildPanelContent(for kind: ChildPanelKind) -> (NSView, NSSize)? {
        switch kind {
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
                    await self?.onCheckUpdate()
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.settingsSize)

        case .addFund:
            let view = FundPositionEditorView(
                store: store,
                fund: nil,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.editorSize)

        case .fundDetail(let fund):
            let view = FundDetailView(
                fund: fund,
                totalAmount: store.snapshot.totalAmount,
                pendingTradeCount: store.snapshot.pendingTrades?.filter { $0.code == fund.code }.count ?? 0,
                tradeRecords: store.snapshot.tradeRecords ?? [],
                onBuy: { [weak self] fund in
                    self?.showChildPanel(.buyFund(fund))
                },
                onSell: { [weak self] fund in
                    self?.showChildPanel(.sellFund(fund))
                },
                onEdit: { [weak self] fund in
                    self?.showChildPanel(.editFund(fund))
                },
                onOpenTradeRecords: { [weak self] fund in
                    self?.showChildPanel(.tradeRecords(fund))
                },
                onDelete: { [weak self] fund in
                    await self?.deleteFund(fund)
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.fundDetailSize)

        case .tradeRecords(let fund):
            let view = FundTradeRecordsPanelView(
                fund: fund,
                tradeRecords: store.snapshot.tradeRecords ?? [],
                onEdit: { [weak self] record in
                    self?.showChildPanel(.editTradeRecord(fund, record))
                },
                onDelete: { [weak self] record in
                    await self?.deleteTradeRecord(record, returningTo: fund)
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.fundDetail(fund))
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeRecordsSize)

        case .buyFund(let fund):
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: .buy,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

        case .sellFund(let fund):
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: .sell,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

        case .editTradeRecord(let fund, let record):
            let action: FundTradeAction = record.kind == .sell ? .sell : .buy
            let view = FundTradeEditorView(
                store: store,
                fund: fund,
                action: action,
                editingRecord: record,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                        self?.showChildPanel(.tradeRecords(fund))
                    }
                },
                onClose: { [weak self] in
                    self?.showChildPanel(.tradeRecords(fund))
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.tradeEditorSize)

        case .editFund(let fund):
            let view = FundPositionEditorView(
                store: store,
                fund: fund,
                onSaved: { [weak self] in
                    await MainActor.run {
                        self?.updateStatusTitle()
                    }
                },
                onClose: { [weak self] in
                    self?.hideChildPanel()
                }
            )
            return (NSHostingView(rootView: AnyView(view)), PopoverLayout.editorSize)
        }
    }

    private func hideChildPanel() {
        childPanelWindow?.orderOut(nil)
        clearChildPanelState()
    }

    private func handleChildPanelCancel() {
        if case .tradeRecords(let fund) = activeChildPanel {
            showChildPanel(.fundDetail(fund))
        } else {
            hideChildPanel()
        }
    }

    private func handleMainPanelDidHide() {
        childPanelWindow?.orderOut(nil)
        clearChildPanelState()
        mainPanelAnchorFrame = nil
        removeEventMonitors()
        setStatusItemHighlighted(false)
    }

    private func closeAllPanels() {
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
        guard let mainPanelWindow, mainPanelWindow.isVisible else { return }
        updateMainPanelRootView()
        let mainSize = mainPanelWindowSize
        mainPanelWindow.setContentSize(mainSize)
        positionMainPanel(window: mainPanelWindow, size: mainSize)

        guard let childPanelWindow, childPanelWindow.isVisible else { return }
        let size: NSSize
        switch activeChildPanel {
        case .settings:
            size = PopoverLayout.settingsSize
        case .fundDetail:
            size = PopoverLayout.fundDetailSize
        case .tradeRecords:
            size = PopoverLayout.tradeRecordsSize
        case .addFund, .editFund:
            size = PopoverLayout.editorSize
        case .buyFund, .sellFund, .editTradeRecord:
            size = PopoverLayout.tradeEditorSize
        case nil:
            return
        }
        childPanelWindow.setContentSize(size)
        positionChildPanel(window: childPanelWindow, size: size)
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

        menu.addItem(disabledMenuItem("fund-pulse v\(appVersion)"))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: amountPrivacyMenuTitle, action: #selector(toggleAmountPrivacyFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "刷新基金数据", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())

        addUpdateMenuItems(to: menu)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "导入基金配置", action: #selector(importFundConfigurationFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出基金配置", action: #selector(exportFundConfigurationFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        closeAllPanels()
        let popUpMenuSelector = NSSelectorFromString("popUpStatusItemMenu:")
        _ = statusItem.perform(popUpMenuSelector, with: menu)
    }

    private func addUpdateMenuItems(to menu: NSMenu) {
        switch updateStore.status {
        case .idle, .upToDate:
            menu.addItem(NSMenuItem(title: "检查更新", action: #selector(checkUpdateFromMenu), keyEquivalent: ""))
        case .available(let updateInfo):
            menu.addItem(NSMenuItem(title: "下载新版本 v\(updateInfo.version)", action: #selector(openUpdateFromMenu), keyEquivalent: ""))
        case .downloading(let updateInfo):
            menu.addItem(disabledMenuItem("正在下载 v\(updateInfo.version) · \(Int(updateStore.downloadProgress * 100))%"))
        case .downloaded(let updateInfo, _):
            menu.addItem(NSMenuItem(title: "现在更新 v\(updateInfo.version)", action: #selector(openUpdateFromMenu), keyEquivalent: ""))
        case .installing:
            menu.addItem(disabledMenuItem("正在更新，应用将自动重启"))
        case .checking:
            menu.addItem(disabledMenuItem("正在检查更新"))
        case .failed(let reason):
            let retryItem = NSMenuItem(title: "重新检查更新", action: #selector(checkUpdateFromMenu), keyEquivalent: "")
            retryItem.toolTip = reason
            menu.addItem(retryItem)
        }
    }

    private func disabledMenuItem(_ title: String, toolTip: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = toolTip
        return item
    }

    private var amountPrivacyMenuTitle: String {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.hideHeaderAmounts)
            ? "显示金额"
            : "隐藏金额"
    }

    private func checkForUpdates() {
        Task { [weak self] in
            await self?.onCheckUpdate()
        }
    }

    @objc private func toggleAmountPrivacyFromMenu() {
        let defaults = UserDefaults.standard
        let shouldHideAmounts = !defaults.bool(forKey: AppPreferenceKey.hideHeaderAmounts)
        defaults.set(shouldHideAmounts, forKey: AppPreferenceKey.hideHeaderAmounts)
        NotificationCenter.default.post(name: .fundPulseAmountPrivacyDidChange, object: nil)
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
        refreshVisiblePanels()
        configureAutoRefreshTimer()
        configureOperationReminder()
    }

    private func refreshQuotesAndStatusTitleAsync() async {
        guard !isRefreshingQuotes else { return }
        isRefreshingQuotes = true
        defer { isRefreshingQuotes = false }

        await store.refreshQuotes()
        updateStatusTitle()
        refreshVisiblePanels()
    }

    private func configureAutoRefreshTimer() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil

        let interval = settingsStore.settings.autoRefreshInterval.seconds
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshQuotesAndStatusTitleAsync()
            }
        }
        timer.tolerance = min(interval * 0.2, 5)
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }

    private func configureOperationReminder() {
        let center = UNUserNotificationCenter.current()
        let isEnabled = settingsStore.settings.operationReminderEnabled
        let reminderMinutes = settingsStore.settings.operationReminderTimeMinutes

        center.removePendingNotificationRequests(withIdentifiers: [operationReminderNotificationID])

        guard isEnabled else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            let clampedMinutes = AppSettings.clampedReminderTimeMinutes(reminderMinutes)
            var dateComponents = DateComponents()
            dateComponents.calendar = Calendar.current
            dateComponents.hour = clampedMinutes / 60
            dateComponents.minute = clampedMinutes % 60

            let content = UNMutableNotificationContent()
            content.title = "基金操作提醒"
            content.body = "现在可以检查基金估值，按计划处理加仓、减仓或继续持有。"
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(
                identifier: operationReminderNotificationID,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func deleteFund(_ fund: FundPosition) async {
        do {
            try await store.deleteFund(code: fund.code)
            updateStatusTitle()
            refreshVisiblePanels()
        } catch {
            // Keep the existing data visible; PortfolioStore.loadState will surface refresh failures.
        }
    }

    private func deleteTradeRecord(_ record: FundTradeRecord, returningTo fund: FundPosition) async {
        do {
            try await store.deleteTradeRecord(id: record.id)
            updateStatusTitle()
            showChildPanel(.tradeRecords(fund))
            updateMainPanelRootView()
        } catch {
            refreshVisiblePanels()
        }
    }
}
