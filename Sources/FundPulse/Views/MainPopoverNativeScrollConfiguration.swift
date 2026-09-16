import AppKit
import SwiftUI

struct MainPopoverNativeScrollConfiguration: NSViewRepresentable {
    @MainActor
    func makeNSView(context: Context) -> NativeScrollConfigurationView {
        NativeScrollConfigurationView(frame: .zero)
    }

    @MainActor
    func updateNSView(_ view: NativeScrollConfigurationView, context: Context) {
        view.configureEnclosingScrollView()
    }
}

@MainActor
final class NativeScrollConfigurationView: NSView {
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                scrollView.drawsBackground = false
                scrollView.hasVerticalScroller = true
                scrollView.hasHorizontalScroller = false
                scrollView.autohidesScrollers = true
                scrollView.scrollerStyle = .overlay
                scrollView.scrollerInsets = NSEdgeInsets(top: 7, left: 0, bottom: 7, right: 2)
                scrollView.verticalScroller?.controlSize = .small
                scrollView.verticalScroller?.knobStyle = .default
                return
            }
            ancestor = current.superview
        }
    }
}

private let refreshTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "MM-dd HH:mm:ss"
    return formatter
}()

func refreshTimeText(_ date: Date) -> String {
    refreshTimeFormatter.string(from: date)
}
