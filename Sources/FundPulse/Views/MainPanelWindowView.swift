import AppKit
import SwiftUI

struct MainPanelWindowView: View {
    let accountsStore: PortfolioAccountsStore
    let settingsStore: AppSettingsStore
    let marketIndexStore: MarketIndexStore
    let updateStore: AppUpdateStore
    let uiState: PopoverUIState
    let selectedFundCode: String?
    let onSelectAccount: (PortfolioAccountSelection) -> Void
    let onManageAccounts: () -> Void
    let onRefresh: (() async -> Void)?
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    let onOpenPortfolioBreakdown: () -> Void
    let onOpenTodayIncomeRanking: () -> Void
    let onOpenTodayRateRanking: () -> Void
    let onOpenHoldingIncome: () -> Void
    let onOpenHoldingRate: () -> Void
    let onAddFund: () -> Void
    let onOpenFundDetail: (FundPosition) -> Void
    let onOpenTradeRecords: (FundPosition) -> Void
    let onOpenPendingActivity: (PendingTradeActivity) -> Void
    let onDeletePendingActivity: (PendingTradeActivity) async -> Void
    let onBuyFund: (FundPosition) -> Void
    let onSellFund: (FundPosition) -> Void
    let onEditFund: (FundPosition) -> Void
    let onDeleteFund: (FundPosition) async -> Void
    let onCheckUpdate: (() async -> Void)?
    let onOpenUpdate: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let contentHeight = mainPanelContentHeight(for: proxy.size.height)
            let windowHeight = contentHeight + PopoverLayout.arrowHeight

            ZStack(alignment: .top) {
                PopoverChromeShape(arrowX: uiState.arrowX)
                    .fill(popoverChromeFillColor)
                    .overlay(
                        PopoverChromeShape(arrowX: uiState.arrowX)
                            .stroke(panelBorderColor, lineWidth: 0.5)
                    )

                VStack(spacing: 0) {
                    if showsAccountBar {
                        PortfolioAccountTabBar(
                            accountsStore: accountsStore,
                            onSelect: onSelectAccount,
                            onManageAccounts: onManageAccounts,
                            onOpenSettings: onOpenSettings
                        )
                    }

                    selectedScopeContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: PopoverLayout.mainWidth, height: contentHeight)
                .clipShape(RoundedRectangle(cornerRadius: PopoverLayout.cornerRadius, style: .continuous))
                .offset(y: PopoverLayout.arrowHeight)

                MainPanelBottomResizeArea(settingsStore: settingsStore)
                    .frame(height: bottomResizeEdgeHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(10)
            }
            .frame(width: PopoverLayout.mainWidth, height: windowHeight, alignment: .top)
        }
        .frame(width: PopoverLayout.mainWidth)
        .background(Color.clear)
    }

    @ViewBuilder
    private var selectedScopeContent: some View {
        if let store = selectedStoreForPresentation {
            PopoverContentView(
                store: store,
                settingsStore: settingsStore,
                marketIndexStore: marketIndexStore,
                updateStore: updateStore,
                selectedFundCode: selectedFundCode,
                onRefresh: onRefresh,
                onOpenPortfolioBreakdown: onOpenPortfolioBreakdown,
                onOpenTodayIncomeRanking: onOpenTodayIncomeRanking,
                onOpenTodayRateRanking: onOpenTodayRateRanking,
                onOpenHoldingIncome: onOpenHoldingIncome,
                onOpenHoldingRate: onOpenHoldingRate,
                onAddFund: onAddFund,
                onOpenFundDetail: onOpenFundDetail,
                onOpenTradeRecords: onOpenTradeRecords,
                onOpenPendingActivity: onOpenPendingActivity,
                onDeletePendingActivity: onDeletePendingActivity,
                onBuyFund: onBuyFund,
                onSellFund: onSellFund,
                onEditFund: onEditFund,
                onDeleteFund: onDeleteFund,
                onCheckUpdate: onCheckUpdate,
                onOpenUpdate: onOpenUpdate
            )
        } else {
            AllAccountsOverviewView(
                accountsStore: accountsStore,
                onSelectAccount: { accountID in
                    onSelectAccount(.account(accountID))
                },
                onRefresh: onRefresh
            )
        }
    }

    private var showsAccountBar: Bool {
        PortfolioAccountPresentation.showsAccountBar(accountCount: accountsStore.accounts.count)
    }

    private var selectedStoreForPresentation: PortfolioStore? {
        if accountsStore.accounts.count > 1 {
            return accountsStore.selectedStore
        }
        guard let firstAccount = accountsStore.accounts.first else { return nil }
        return accountsStore.store(for: firstAccount.id)
    }

    private func mainPanelContentHeight(for proposedWindowHeight: CGFloat) -> CGFloat {
        guard proposedWindowHeight > PopoverLayout.arrowHeight else {
            return PopoverLayout.clampedMainPanelHeight(CGFloat(settingsStore.settings.mainPanelHeight))
        }
        return PopoverLayout.clampedMainPanelHeight(proposedWindowHeight - PopoverLayout.arrowHeight)
    }

    private var popoverChromeFillColor: Color {
        PanelDesign.panelChromeBackground
    }

    private var bottomResizeEdgeHeight: CGFloat {
        12
    }
}

private struct MainPanelBottomResizeArea: NSViewRepresentable {
    let settingsStore: AppSettingsStore

    func makeNSView(context: Context) -> MainPanelBottomResizeView {
        MainPanelBottomResizeView(settingsStore: settingsStore)
    }

    func updateNSView(_ view: MainPanelBottomResizeView, context: Context) {
        view.settingsStore = settingsStore
    }
}

private final class MainPanelBottomResizeView: NSView {
    var settingsStore: AppSettingsStore
    private var dragStartFrame: NSRect?
    private var dragStartMouseLocation: NSPoint?

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartFrame = window?.frame
        dragStartMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let dragStartFrame,
              let dragStartMouseLocation
        else { return }

        let currentMouseLocation = NSEvent.mouseLocation
        let minWindowHeight = PopoverLayout.mainWindowHeight(forHeight: CGFloat(AppSettings.minMainPanelHeight))
        let maxWindowHeight = PopoverLayout.mainWindowHeight(forHeight: CGFloat(AppSettings.maxMainPanelHeight))
        let proposedHeight = dragStartFrame.height + dragStartMouseLocation.y - currentMouseLocation.y
        let nextHeight = min(max(proposedHeight, minWindowHeight), maxWindowHeight)
        let nextFrame = NSRect(
            x: dragStartFrame.minX,
            y: dragStartFrame.maxY - nextHeight,
            width: PopoverLayout.mainWidth,
            height: nextHeight
        )
        window.setFrame(nextFrame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStartFrame = nil
            dragStartMouseLocation = nil
        }

        guard let window else { return }
        let contentHeight = PopoverLayout.clampedMainPanelHeight(window.frame.height - PopoverLayout.arrowHeight)
        settingsStore.setMainPanelHeight(Int(contentHeight.rounded()))
    }
}

private struct PopoverChromeShape: Shape {
    let arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = PopoverLayout.cornerRadius
        let panelY = PopoverLayout.arrowHeight
        let arrowHalf = PopoverLayout.arrowWidth / 2
        let x = min(max(arrowX, radius + arrowHalf), rect.width - radius - arrowHalf)

        var path = Path()
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x + arrowHalf, y: panelY))
        path.addLine(to: CGPoint(x: rect.width - radius, y: panelY))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: panelY + radius), control: CGPoint(x: rect.width, y: panelY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.height - radius), control: CGPoint(x: rect.minX, y: rect.height))
        path.addLine(to: CGPoint(x: rect.minX, y: panelY + radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: panelY), control: CGPoint(x: rect.minX, y: panelY))
        path.addLine(to: CGPoint(x: x - arrowHalf, y: panelY))
        path.closeSubpath()
        return path
    }
}

