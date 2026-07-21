import Foundation

struct OperationReminderNotificationCandidate: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

struct OperationReminderNotificationRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
}

enum OperationReminderNotificationContent {
    static let legacyIdentifier = "fund-pulse.operation-reminder"
    static let identifierPrefix = "\(legacyIdentifier)."
    static let title = "基金操作提醒"
    static let body = "现在可以检查基金估值，按计划处理加仓、减仓或继续持仓。"
}

enum OperationReminderNotificationCleanup {
    static func isOperationReminder(_ candidate: OperationReminderNotificationCandidate) -> Bool {
        candidate.identifier == OperationReminderNotificationContent.legacyIdentifier
            || candidate.identifier.hasPrefix(OperationReminderNotificationContent.identifierPrefix)
            || (
                candidate.title == OperationReminderNotificationContent.title
                    && candidate.body == OperationReminderNotificationContent.body
            )
    }

    static func matchingIdentifiers(
        in candidates: [OperationReminderNotificationCandidate]
    ) -> [String] {
        Set(
            candidates.filter(isOperationReminder).map(\.identifier)
        ).sorted()
    }
}

actor OperationReminderNotificationPresentationGate {
    private let duplicateWindow: TimeInterval
    private var lastPresentedAt: Date?

    init(duplicateWindow: TimeInterval = 60) {
        self.duplicateWindow = max(duplicateWindow, 0)
    }

    func shouldPresent(
        _ candidate: OperationReminderNotificationCandidate,
        at date: Date = .now
    ) -> Bool {
        guard OperationReminderNotificationCleanup.isOperationReminder(candidate) else {
            return true
        }

        if let lastPresentedAt,
           date.timeIntervalSince(lastPresentedAt) < duplicateWindow {
            return false
        }

        lastPresentedAt = date
        return true
    }
}

@MainActor
final class OperationReminderNotificationScheduler {
    private let maximumRemovalAttempts: Int
    private let pendingRequests: @MainActor () async -> [OperationReminderNotificationCandidate]
    private let removePendingRequests: @MainActor ([String]) -> Void
    private let deliveredNotifications: @MainActor () async -> [OperationReminderNotificationCandidate]
    private let removeDeliveredNotifications: @MainActor ([String]) -> Void
    private let requestAuthorization: @MainActor () async throws -> Bool
    private let addRequest: @MainActor (OperationReminderNotificationRequest) async throws -> Void
    private let waitAfterRemovalAttempt: @MainActor () async -> Void

    private var configurationTask: Task<Void, Never>?

    init(
        maximumRemovalAttempts: Int,
        pendingRequests: @escaping @MainActor () async -> [OperationReminderNotificationCandidate],
        removePendingRequests: @escaping @MainActor ([String]) -> Void,
        deliveredNotifications: @escaping @MainActor () async -> [OperationReminderNotificationCandidate],
        removeDeliveredNotifications: @escaping @MainActor ([String]) -> Void,
        requestAuthorization: @escaping @MainActor () async throws -> Bool,
        addRequest: @escaping @MainActor (OperationReminderNotificationRequest) async throws -> Void,
        waitAfterRemovalAttempt: @escaping @MainActor () async -> Void
    ) {
        self.maximumRemovalAttempts = max(maximumRemovalAttempts, 1)
        self.pendingRequests = pendingRequests
        self.removePendingRequests = removePendingRequests
        self.deliveredNotifications = deliveredNotifications
        self.removeDeliveredNotifications = removeDeliveredNotifications
        self.requestAuthorization = requestAuthorization
        self.addRequest = addRequest
        self.waitAfterRemovalAttempt = waitAfterRemovalAttempt
    }

    func configure(isEnabled: Bool, requests: [OperationReminderNotificationRequest]) {
        let previousTask = configurationTask
        previousTask?.cancel()

        configurationTask = Task { [weak self, previousTask] in
            if let previousTask {
                await previousTask.value
            }
            guard let self, !Task.isCancelled else { return }
            await rebuild(isEnabled: isEnabled, requests: requests)
        }
    }

    func invalidate() {
        configurationTask?.cancel()
        configurationTask = nil
    }

    func waitUntilIdle() async {
        let task = configurationTask
        await task?.value
    }

    private func rebuild(
        isEnabled: Bool,
        requests: [OperationReminderNotificationRequest]
    ) async {
        guard await removePendingOperationReminders(), !Task.isCancelled else { return }

        let deliveredCandidates = await deliveredNotifications()
        guard !Task.isCancelled else { return }
        let deliveredIdentifiers = OperationReminderNotificationCleanup.matchingIdentifiers(
            in: deliveredCandidates
        )
        if !deliveredIdentifiers.isEmpty {
            removeDeliveredNotifications(deliveredIdentifiers)
        }

        guard isEnabled, !requests.isEmpty, !Task.isCancelled else { return }
        guard (try? await requestAuthorization()) == true, !Task.isCancelled else { return }

        var addedIdentifiers: Set<String> = []
        for request in requests where addedIdentifiers.insert(request.identifier).inserted {
            guard !Task.isCancelled else { return }
            try? await addRequest(request)
        }
    }

    private func removePendingOperationReminders() async -> Bool {
        for _ in 0..<maximumRemovalAttempts {
            guard !Task.isCancelled else { return false }

            let candidates = await pendingRequests()
            guard !Task.isCancelled else { return false }
            let identifiers = OperationReminderNotificationCleanup.matchingIdentifiers(in: candidates)
            guard !identifiers.isEmpty else { return true }

            removePendingRequests(identifiers)
            await waitAfterRemovalAttempt()
        }

        guard !Task.isCancelled else { return false }
        let remainingCandidates = await pendingRequests()
        return OperationReminderNotificationCleanup.matchingIdentifiers(in: remainingCandidates).isEmpty
    }
}
