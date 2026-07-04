import Foundation

struct AppUpdateInfo: Codable, Equatable, Sendable {
    var version: String
    var releaseName: String
    var releaseNotes: String
    var publishedAt: Date?
    var htmlURL: URL
    var downloadURL: URL?
}

struct AppUpdatePackage: Equatable, Sendable {
    var localURL: URL
    var stagedAppURL: URL
    var downloadedAt: Date
}

enum AppUpdateCheckMode: Equatable, Sendable {
    case background
    case interactive
}

enum AppUpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case available(AppUpdateInfo)
    case downloading(AppUpdateInfo)
    case downloaded(AppUpdateInfo, AppUpdatePackage)
    case installing(AppUpdateInfo)
    case upToDate(Date)
    case failed(String)

    var updateInfo: AppUpdateInfo? {
        switch self {
        case .available(let info),
             .downloading(let info),
             .downloaded(let info, _),
             .installing(let info):
            return info
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }
}
