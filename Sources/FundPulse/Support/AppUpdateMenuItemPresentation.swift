import Foundation

enum AppUpdateMenuItemAction: Equatable {
    case checkForUpdates
    case openUpdate
}

extension AppUpdateStatus {
    var shouldCheckWhenOpeningContextMenu: Bool {
        switch self {
        case .idle, .checking, .available, .upToDate, .failed:
            return true
        case .downloading, .downloaded, .installing:
            return false
        }
    }
}

struct AppUpdateMenuItemPresentation: Equatable {
    var title: String
    var action: AppUpdateMenuItemAction?
    var toolTip: String?
    var isActiveStatus: Bool

    var isEnabled: Bool {
        action != nil
    }

    init(status: AppUpdateStatus, downloadProgress: Double, activityFrame: Int = 2) {
        switch status {
        case .idle:
            title = "检查更新"
            action = .checkForUpdates
            toolTip = nil
            isActiveStatus = false
        case .checking:
            title = "正在检查更新\(Self.animatedEllipsis(activityFrame))"
            action = nil
            toolTip = nil
            isActiveStatus = true
        case .available(let info):
            title = "检测到新版本"
            action = .openUpdate
            toolTip = "v\(info.version) · 点击下载"
            isActiveStatus = false
        case .downloading(let info):
            title = "正在下载 v\(info.version) · \(Self.progressPercent(downloadProgress))%"
            action = nil
            toolTip = nil
            isActiveStatus = true
        case .downloaded(let info, _):
            title = "现在更新 v\(info.version)"
            action = .openUpdate
            toolTip = "更新已下载，点击安装"
            isActiveStatus = false
        case .installing:
            title = "正在更新，应用将自动重启"
            action = nil
            toolTip = nil
            isActiveStatus = true
        case .upToDate(let date):
            title = "已是最新版本"
            action = nil
            toolTip = "上次检查：\(date.formatted(date: .omitted, time: .shortened))"
            isActiveStatus = false
        case .failed(let reason):
            title = "重新检查更新"
            action = .checkForUpdates
            toolTip = reason
            isActiveStatus = false
        }
    }

    private static func progressPercent(_ progress: Double) -> Int {
        Int(min(max(progress, 0), 1) * 100)
    }

    private static func animatedEllipsis(_ frame: Int) -> String {
        String(repeating: ".", count: max(0, frame % 3) + 1)
    }
}
