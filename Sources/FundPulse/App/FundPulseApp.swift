import AppKit
import SwiftUI
import UserNotifications

@main
struct FundPulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
                .frame(width: 0, height: 0)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let portfolioStore = PortfolioStore()
    let settingsStore = AppSettingsStore()
    let marketIndexStore = MarketIndexStore()
    let updateStore = AppUpdateStore()
    nonisolated private let operationReminderPresentationGate = OperationReminderNotificationPresentationGate()
    private var statusBarController: StatusBarController?

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
#if DEBUG
#else
        JDFinanceDebugArtifacts.removePersistedFiles()
#endif
        portfolioStore.load()
        statusBarController = StatusBarController(
            store: portfolioStore,
            settingsStore: settingsStore,
            marketIndexStore: marketIndexStore,
            updateStore: updateStore,
            appVersion: appVersion,
            onCheckUpdate: { [weak self] mode in
                await self?.checkForUpdates(mode: mode)
            },
            onOpenUpdate: { [weak self] in
                self?.updateStore.openUpdate()
            }
        )
        statusBarController?.presentInitialExperienceIfNeeded()
#if DEBUG
        statusBarController?.presentDebugPanelIfRequested()
#endif
        Task {
            await checkForUpdates()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.invalidate()
        statusBarController = nil
    }

    func refreshStatusTitle() {
        statusBarController?.updateStatusTitle()
    }

    func refreshPortfolioAndStatusTitle() async {
        await portfolioStore.refreshQuotes()
        if settingsStore.settings.showsMarketIndexes {
            await marketIndexStore.refresh()
        }
        refreshStatusTitle()
    }

    func checkForUpdates(mode: AppUpdateCheckMode = .background) async {
        await updateStore.check(currentVersion: appVersion, mode: mode)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let request = notification.request
        let candidate = OperationReminderNotificationCandidate(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body
        )
        guard await operationReminderPresentationGate.shouldPresent(candidate) else {
            return []
        }
        return [.banner, .sound]
    }
}
