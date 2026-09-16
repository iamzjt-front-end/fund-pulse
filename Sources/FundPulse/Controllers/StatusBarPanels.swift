import AppKit
import SwiftUI

extension AppAppearanceMode {
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

final class AppearanceTransitionOverlayView: NSView {
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

    func configure(for appearance: NSAppearance) {
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

enum StatusItemPresentation {
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

struct StatusTitlePresentation {
    let text: String
    let attributes: [NSAttributedString.Key: Any]
    let visualLength: CGFloat
}

func makeStatusPulseImage(size: NSSize, tintColor: NSColor? = nil) -> NSImage {
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
    static let jdFinanceSyncWidth: CGFloat = 500
    static let jdFinanceSyncHeight: CGFloat = 720
    static let standardChildPanelWidth: CGFloat = 360
    static let settingsWidth: CGFloat = standardChildPanelWidth
    static let editorWidth: CGFloat = standardChildPanelWidth
    static let standardChildPanelHeight: CGFloat = 660
    static let editorHeight: CGFloat = 600
    static let tradeRecordsHeight: CGFloat = standardChildPanelHeight
    static let settingsHeight: CGFloat = 750
    static let portfolioBreakdownWidth: CGFloat = standardChildPanelWidth
    static let todayIncomeRankingWidth: CGFloat = standardChildPanelWidth
    static let fundDailyIncomeWidth: CGFloat = standardChildPanelWidth
    static let fundDailyIncomeHeight: CGFloat = 600
    static let onboardingWidth: CGFloat = standardChildPanelWidth
    static let privacyDisclaimerWidth: CGFloat = onboardingWidth
    static let sampleExperienceWidth: CGFloat = 430
    static let portfolioPerformanceWidth: CGFloat = 430
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
    static let jdFinanceSyncSize = NSSize(width: jdFinanceSyncWidth, height: jdFinanceSyncHeight)
    static let settingsSize = NSSize(width: settingsWidth, height: settingsHeight)
    static let editorSize = NSSize(width: editorWidth, height: editorHeight)
    static let tradeEditorSize = NSSize(width: editorWidth, height: standardChildPanelHeight)
    static let fundDetailSize = NSSize(width: editorWidth, height: standardChildPanelHeight)
    static let tradeRecordsSize = NSSize(width: editorWidth, height: tradeRecordsHeight)
    static let portfolioBreakdownSize = NSSize(width: portfolioBreakdownWidth, height: standardChildPanelHeight)
    static let todayIncomeRankingSize = NSSize(width: todayIncomeRankingWidth, height: standardChildPanelHeight)
    static let fundDailyIncomeSize = NSSize(width: fundDailyIncomeWidth, height: fundDailyIncomeHeight)
    static let onboardingSize = NSSize(width: onboardingWidth, height: standardChildPanelHeight)
    static let sampleExperienceSize = NSSize(width: sampleExperienceWidth, height: standardChildPanelHeight)
    static let privacyDisclaimerSize = NSSize(width: privacyDisclaimerWidth, height: standardChildPanelHeight)
    static let portfolioPerformanceSize = NSSize(width: portfolioPerformanceWidth, height: standardChildPanelHeight)
    static let jdFinancePerformanceSyncSize = portfolioPerformanceSize
    static let accountEditorSize = NSSize(width: editorWidth, height: 520)
    static let accountManagementSize = NSSize(width: standardChildPanelWidth, height: 620)
    static let exchangeReconciliationSize = NSSize(width: editorWidth, height: 600)

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

final class FundPulsePanel: NSPanel {
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

final class PanelCardContainerView: NSView {
    let hostedContentView: NSView

    init(contentView: NSView, cornerRadius: CGFloat = PopoverLayout.cornerRadius) {
        hostedContentView = contentView
        super.init(frame: .zero)

        if let hostingView = contentView as? NSHostingView<AnyView> {
            hostingView.sizingOptions = []
        }

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        updateAppearanceColors()

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
final class OnboardingAddFlowState {
    var didSave = false
}

