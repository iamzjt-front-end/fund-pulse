import Foundation

enum SupportAuthorCopy {
    static let motivation =
        "Fund Pulse 免费、开源且无广告。您的支持，是我持续更新、修复问题和适配新版 macOS 的最大动力。感谢您的认可与鼓励。"

    static let paymentBoundary =
        "支持完全自愿，不会解锁额外功能。支付由微信或支付宝处理，Fund Pulse 不读取、上传或保存支付信息。"
}

enum SupportAuthorAsset: String, CaseIterable, Identifiable {
    case wechat = "wechat-support"
    case alipay = "alipay-support"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wechat:
            "微信支付"
        case .alipay:
            "支付宝"
        }
    }
}

enum SupportAuthorResources {
    static func url(
        for asset: SupportAuthorAsset,
        bundle: Bundle = .module
    ) -> URL? {
        bundle.url(forResource: asset.rawValue, withExtension: "png")
            ?? bundle.url(
                forResource: asset.rawValue,
                withExtension: "png",
                subdirectory: "Support"
            )
    }
}
