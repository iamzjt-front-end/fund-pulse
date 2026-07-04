import AppKit
import Foundation
import Observation
import OSLog

private let appUpdateStoreLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.iamzjt.frontend.fund-pulse.swift",
    category: "AppUpdate"
)

struct AppUpdateCheckRequest: Sendable, Equatable {
    var generation: Int
    var currentVersion: String
    var mode: AppUpdateCheckMode
    var service: AppUpdateService

    static func == (lhs: AppUpdateCheckRequest, rhs: AppUpdateCheckRequest) -> Bool {
        lhs.generation == rhs.generation &&
            lhs.currentVersion == rhs.currentVersion &&
            lhs.mode == rhs.mode
    }
}

enum AppUpdateCheckCompletion: Sendable, Equatable {
    case success(AppUpdateStatus)
    case failure(String)
}

@Observable
@MainActor
final class AppUpdateStore {
    private(set) var status: AppUpdateStatus = .idle
    private(set) var lastCheckedAt: Date?
    private(set) var downloadProgress: Double = 0

    private let service: AppUpdateService
    private var checkGeneration = 0
    private var currentCheckMode: AppUpdateCheckMode?

    init(service: AppUpdateService = AppUpdateService()) {
        self.service = service
    }

    func check(currentVersion: String, mode: AppUpdateCheckMode = .background) async {
        guard let request = startCheck(currentVersion: currentVersion, mode: mode) else { return }
        let completion: AppUpdateCheckCompletion
        do {
            let nextStatus = try await request.service.check(currentVersion: request.currentVersion, mode: request.mode)
            completion = .success(nextStatus)
        } catch {
            completion = .failure(error.localizedDescription)
        }
        finishCheck(request, completion: completion)
    }

    func startCheck(currentVersion: String, mode: AppUpdateCheckMode = .background) -> AppUpdateCheckRequest? {
        guard canCheckForUpdates(mode: mode) else {
            appUpdateStoreLogger.info("Skip update check mode=\(String(describing: mode), privacy: .public) status=\(String(describing: self.status), privacy: .public) currentMode=\(String(describing: self.currentCheckMode), privacy: .public)")
            return nil
        }
        checkGeneration += 1
        let generation = checkGeneration
        currentCheckMode = mode
        status = .checking
        appUpdateStoreLogger.info("Start update check mode=\(String(describing: mode), privacy: .public) generation=\(generation, privacy: .public) currentVersion=\(currentVersion, privacy: .public)")
        return AppUpdateCheckRequest(
            generation: generation,
            currentVersion: currentVersion,
            mode: mode,
            service: service
        )
    }

    func finishCheck(_ request: AppUpdateCheckRequest, completion: AppUpdateCheckCompletion) {
        guard isCurrentCheck(request.generation) else {
            appUpdateStoreLogger.info("Ignore stale update check mode=\(String(describing: request.mode), privacy: .public) generation=\(request.generation, privacy: .public)")
            return
        }

        switch completion {
        case .success(let nextStatus):
            status = nextStatus
        case .failure(let message):
            status = .failed(message)
        }
        currentCheckMode = nil
        lastCheckedAt = .now
        appUpdateStoreLogger.info("Finish update check mode=\(String(describing: request.mode), privacy: .public) generation=\(request.generation, privacy: .public) status=\(String(describing: self.status), privacy: .public)")
    }

    private func canCheckForUpdates(mode: AppUpdateCheckMode) -> Bool {
        switch status {
        case .checking:
            return mode == .interactive && currentCheckMode == .background
        case .downloading, .downloaded, .installing:
            return false
        case .idle, .available, .upToDate, .failed:
            return true
        }
    }

    private func isCurrentCheck(_ generation: Int) -> Bool {
        generation == checkGeneration
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
