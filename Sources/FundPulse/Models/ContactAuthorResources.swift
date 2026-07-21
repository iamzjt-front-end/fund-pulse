import Foundation

enum ContactAuthorResources {
    static func wechatQRCodeURL(bundle: Bundle = .module) -> URL? {
        bundle.url(forResource: "wechat-contact", withExtension: "png")
            ?? bundle.url(
                forResource: "wechat-contact",
                withExtension: "png",
                subdirectory: "Contact"
            )
    }
}
