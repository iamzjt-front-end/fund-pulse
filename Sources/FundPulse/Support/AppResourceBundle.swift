import Foundation

enum AppResourceBundle {
    private final class Finder {}

    /// SwiftPM's command-line accessor can embed the developer's build path.
    /// Resolve the deployed app layout directly and let missing assets degrade
    /// to the existing placeholder instead of calling Bundle.module/fatalError.
    static let current: Bundle? = {
        let main = Bundle.main
        let code = Bundle(for: Finder.self)
        return resolve(resourceURL: main.resourceURL, bundleURL: main.bundleURL)
            ?? resolve(resourceURL: code.resourceURL, bundleURL: code.bundleURL)
            ?? resolve(resourceURL: main.executableURL?.deletingLastPathComponent(), bundleURL: main.bundleURL)
            ?? resolve(resourceURL: code.bundleURL.deletingLastPathComponent(), bundleURL: code.bundleURL)
    }()

    static func resolve(resourceURL: URL?, bundleURL: URL) -> Bundle? {
        for root in [resourceURL, bundleURL, bundleURL.appending(path: "Contents/Resources")].compactMap({ $0 }) {
            if let bundle = Bundle(url: root.appending(path: "FundPulse_FundPulse.bundle")) { return bundle }
        }
        return nil
    }
}
