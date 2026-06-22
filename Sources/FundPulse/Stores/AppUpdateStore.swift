import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppUpdateStore {
    private(set) var status: AppUpdateStatus = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var downloadProgress: Double = 0

    private let service: AppUpdateService

    init(service: AppUpdateService = AppUpdateService()) {
        self.service = service
    }

    func check(currentVersion: String) async {
        guard canCheckForUpdates else { return }
        status = .checking
        do {
            status = try await service.check(currentVersion: currentVersion)
            lastCheckedAt = .now
        } catch {
            status = .failed(error.localizedDescription)
            lastCheckedAt = .now
        }
    }

    private var canCheckForUpdates: Bool {
        switch status {
        case .checking, .downloading, .downloaded, .installing:
            return false
        case .idle, .available, .upToDate, .failed:
            return true
        }
    }

    func openUpdate() {
        switch status {
        case .available(let info):
            Task {
                await downloadUpdate(info)
            }
        case .downloaded(let info, let package):
            installUpdate(info: info, package: package)
        case .downloading, .installing, .checking, .idle, .upToDate, .failed:
            break
        }
    }

    private func downloadUpdate(_ info: AppUpdateInfo) async {
        downloadProgress = 0
        status = .downloading(info)
        do {
            let package = try await service.downloadPackage(for: info) { [weak self] progress in
                self?.downloadProgress = min(max(progress, 0), 1)
            }
            downloadProgress = 1
            status = .downloaded(info, package)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func installUpdate(info: AppUpdateInfo, package: AppUpdatePackage) {
        status = .installing(info)
        do {
            try service.installPackage(
                package,
                currentAppURL: Bundle.main.bundleURL,
                processIdentifier: ProcessInfo.processInfo.processIdentifier
            )
            NSApp.terminate(nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    var primaryActionTitle: String? {
        switch status {
        case .available:
            "下载更新"
        case .downloading:
            "正在下载 \(Int(downloadProgress * 100))%"
        case .downloaded:
            "现在更新"
        case .installing:
            "正在更新"
        case .idle, .checking, .upToDate, .failed:
            nil
        }
    }

    var primaryActionSystemImage: String {
        switch status {
        case .available:
            "arrow.down.circle"
        case .downloading:
            "arrow.down.circle.fill"
        case .downloaded:
            "arrow.triangle.2.circlepath.circle"
        case .installing:
            "arrow.triangle.2.circlepath"
        case .idle, .checking, .upToDate, .failed:
            "arrow.clockwise"
        }
    }

    var isPrimaryActionDisabled: Bool {
        switch status {
        case .downloading, .installing:
            true
        case .idle, .checking, .available, .downloaded, .upToDate, .failed:
            false
        }
    }

    var badgeTitle: String? {
        switch status {
        case .available(let info):
            "发现新版本 v\(info.version)，点击下载"
        case .downloading(let info):
            "正在下载 v\(info.version) · \(Int(downloadProgress * 100))%"
        case .downloaded(let info, _):
            "更新已下载，点击安装 v\(info.version)"
        case .installing:
            "正在更新，应用将自动重启"
        case .checking:
            "检查更新中"
        case .failed(let message):
            "更新检查失败：\(message)"
        case .upToDate:
            "已是最新版本"
        case .idle:
            nil
        }
    }

}
