import AppKit
import SwiftUI

struct SupportAuthorSection: View {
    @State private var selectedAsset: SupportAuthorAsset

    init(initialAsset: SupportAuthorAsset = .wechat) {
        _selectedAsset = State(initialValue: initialAsset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(SupportAuthorCopy.motivation)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PanelSegmentedPicker(
                values: SupportAuthorAsset.allCases,
                selection: $selectedAsset,
                title: \SupportAuthorAsset.title,
                tint: selectedAsset.tint,
                accessibilityLabelText: "支付方式"
            )

            SupportQRCodeImage(asset: selectedAsset)
                .id(selectedAsset)
                .frame(maxWidth: .infinity, maxHeight: 424)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.16), value: selectedAsset)

            Text(SupportAuthorCopy.paymentBoundary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

private struct SupportQRCodeImage: View {
    let asset: SupportAuthorAsset

    var body: some View {
        Group {
            if let url = SupportAuthorResources.url(for: asset),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                ContentUnavailableView(
                    "收款码不可用",
                    systemImage: "qrcode",
                    description: Text("请重新安装应用后再试。")
                )
            }
        }
        .accessibilityLabel("\(asset.title)收款码")
    }
}

private extension SupportAuthorAsset {
    var tint: Color {
        switch self {
        case .wechat:
            Color(red: 0.02, green: 0.72, blue: 0.36)
        case .alipay:
            Color(red: 0.05, green: 0.46, blue: 0.96)
        }
    }

}

#Preview("支持作者 - 微信") {
    SupportAuthorSection()
        .frame(width: 312)
        .padding()
}

#Preview("支持作者 - 支付宝") {
    SupportAuthorSection(initialAsset: .alipay)
        .frame(width: 312)
        .padding()
}
