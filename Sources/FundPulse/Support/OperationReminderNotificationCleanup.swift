import Foundation

struct OperationReminderNotificationCandidate: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

enum OperationReminderNotificationContent {
    static let title = "基金操作提醒"
    static let body = "现在可以检查基金估值，按计划处理加仓、减仓或继续持有。"
}
