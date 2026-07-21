import Foundation

enum AppExternalLinks {
    static let privacyPolicyURL = URL(
        string: "https://github.com/iamzjt-front-end/fund-pulse/blob/main/PRIVACY.md"
    )!
    static let issueChooserURL = URL(
        string: "https://github.com/iamzjt-front-end/fund-pulse/issues/new/choose"
    )!
    static let bugReportURL = URL(
        string: "https://github.com/iamzjt-front-end/fund-pulse/issues/new?template=issue_template_bug.md"
    )!
    static let featureRequestURL = URL(
        string: "https://github.com/iamzjt-front-end/fund-pulse/issues/new?template=issue_template_feature.md"
    )!
}

enum AppExternalLinkAction {
    enum Outcome: Equatable {
        case opened
        case copied(message: String)
    }

    static func perform(
        url: URL,
        fallbackText: String,
        failureMessage: String,
        open: (URL) -> Bool,
        copy: (String) -> Void
    ) -> Outcome {
        guard !open(url) else { return .opened }
        copy(fallbackText)
        return .copied(message: failureMessage)
    }
}
