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
    let updateStore = AppUpdateStore()
    private var statusBarController: StatusBarController?

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        portfolioStore.load()
        statusBarController = StatusBarController(
            store: portfolioStore,
            settingsStore: settingsStore,
            updateStore: updateStore,
            appVersion: appVersion,
            onCheckUpdate: { [weak self] in
                await self?.checkForUpdates()
            },
            onOpenUpdate: { [weak self] in
                self?.updateStore.openUpdate()
            }
        )
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
        refreshStatusTitle()
    }

    func checkForUpdates() async {
        await updateStore.check(currentVersion: appVersion)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
