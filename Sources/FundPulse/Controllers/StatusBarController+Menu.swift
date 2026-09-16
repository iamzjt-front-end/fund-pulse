import AppKit
import SwiftUI
import OSLog

extension StatusBarController {
    func showContextMenu(relativeTo sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.delegate = self

        menu.addItem(disabledMenuItem("fund-pulse v\(appVersion)"))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "刷新基金数据", action: #selector(refreshFromMenu), keyEquivalent: "r"))
        menu.addItem(.separator())

        addUpdateMenuItems(to: menu)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettingsFromMenu), keyEquivalent: ","))
        addMenuBarConfigurationMenuItems(to: menu)
        menu.addItem(NSMenuItem(title: "导入基金配置", action: #selector(importFundConfigurationFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出基金配置", action: #selector(exportFundConfigurationFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "备份全部账户", action: #selector(exportAllAccountsFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "恢复全部账户", action: #selector(restoreAllAccountsFromMenu), keyEquivalent: ""))
        if accountsStore.latestBackupURL != nil {
            menu.addItem(NSMenuItem(title: "撤销最近一次账户恢复", action: #selector(restoreLatestAccountsFromMenu), keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitFromMenu), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        closeAllPanels()
        startContextMenuUpdateRefresh()
        let startedUpdateCheck = checkForUpdatesFromContextMenu()
        if startedUpdateCheck {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.popUpContextMenu(menu)
            }
            return
        }
        popUpContextMenu(menu)
    }

    private func popUpContextMenu(_ menu: NSMenu) {
        let popUpMenuSelector = NSSelectorFromString("popUpStatusItemMenu:")
        _ = statusItem.perform(popUpMenuSelector, with: menu)
    }

    private func addMenuBarConfigurationMenuItems(to menu: NSMenu) {
        let contentItem = NSMenuItem(title: "显示内容", action: nil, keyEquivalent: "")
        contentItem.submenu = makeMenuBarContentModeMenu()
        contentItem.isEnabled = true
        menu.addItem(contentItem)

        let displayItem = NSMenuItem(title: "涨跌颜色", action: nil, keyEquivalent: "")
        displayItem.submenu = makeMenuBarDisplayModeMenu()
        displayItem.isEnabled = true
        menu.addItem(displayItem)
    }

    private func makeMenuBarContentModeMenu() -> NSMenu {
        let submenu = NSMenu(title: "显示内容")
        for mode in MenuBarContentMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectMenuBarContentModeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settingsStore.settings.menuBarContentMode == mode ? .on : .off
            item.toolTip = mode.detail
            submenu.addItem(item)
        }
        return submenu
    }

    private func makeMenuBarDisplayModeMenu() -> NSMenu {
        let submenu = NSMenu(title: "涨跌颜色")
        for mode in MenuBarDisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectMenuBarDisplayModeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settingsStore.settings.menuBarDisplayMode == mode ? .on : .off
            item.toolTip = mode.detail
            submenu.addItem(item)
        }
        return submenu
    }

    private func addUpdateMenuItems(to menu: NSMenu) {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        applyUpdateMenuPresentation(to: item)
        contextMenuUpdateItem = item
        menu.addItem(item)
    }

    private func applyUpdateMenuPresentation(to item: NSMenuItem) {
        let presentation = AppUpdateMenuItemPresentation(
            status: contextMenuUpdateStatusOverride ?? updateStore.status,
            downloadProgress: updateStore.downloadProgress,
            activityFrame: contextMenuUpdateAnimationFrame
        )
        item.view = nil
        item.title = presentation.title
        item.action = updateMenuActionSelector(for: presentation.action)
        item.isEnabled = presentation.isEnabled
        item.toolTip = presentation.toolTip
        item.menu?.itemChanged(item)
    }

    private func startContextMenuUpdateRefresh() {
        contextMenuUpdateRefreshTimer?.invalidate()
        contextMenuUpdateRefreshTimer = nil
        contextMenuUpdateStatusOverride = nil
        contextMenuUpdateAnimationFrame = 2
        refreshContextMenuUpdateItem()

        let timer = Timer(
            timeInterval: 0.35,
            target: self,
            selector: #selector(contextMenuUpdateRefreshTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        contextMenuUpdateRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    @objc private func contextMenuUpdateRefreshTimerFired(_ timer: Timer) {
        finishContextMenuUpdateCheckIfReady()
        refreshContextMenuUpdateItem()
    }

    private func refreshContextMenuUpdateItem() {
        guard let contextMenuUpdateItem else {
            if contextMenuUpdateCheck == nil {
                stopContextMenuUpdateRefresh()
            }
            return
        }
        applyUpdateMenuPresentation(to: contextMenuUpdateItem)
        contextMenuUpdateAnimationFrame += 1
    }

    func stopContextMenuUpdateRefresh(cancelPendingCheck: Bool = false) {
        if cancelPendingCheck {
            contextMenuUpdateCheck?.task.cancel()
            contextMenuUpdateCheck = nil
        }
        if contextMenuUpdateCheck == nil {
            contextMenuUpdateRefreshTimer?.invalidate()
            contextMenuUpdateRefreshTimer = nil
        }
        contextMenuUpdateItem = nil
        contextMenuUpdateStatusOverride = nil
    }

    func checkForUpdatesFromContextMenu() -> Bool {
        finishContextMenuUpdateCheckIfReady()
        if contextMenuUpdateCheck != nil {
            contextMenuUpdateStatusOverride = .checking
            refreshContextMenuUpdateItem()
            return true
        }
        guard updateStore.status.shouldCheckWhenOpeningContextMenu else { return false }
        guard let request = updateStore.startCheck(currentVersion: appVersion, mode: .interactive) else { return false }
        let checkID = UUID()
        let resultBox = ContextMenuUpdateCheckResultBox()
        let task = Task.detached(priority: .userInitiated) { [request, resultBox] in
            let completion: AppUpdateCheckCompletion
            do {
                let status = try await request.service.check(
                    currentVersion: request.currentVersion,
                    mode: request.mode
                )
                completion = .success(status)
            } catch {
                completion = .failure(error.localizedDescription)
            }
            resultBox.set(completion)
        }
        contextMenuUpdateCheck = ContextMenuUpdateCheck(
            id: checkID,
            request: request,
            resultBox: resultBox,
            task: task
        )
        contextMenuUpdateStatusOverride = .checking
        refreshContextMenuUpdateItem()
        statusBarUpdateLogger.info("Start context menu update check generation=\(request.generation, privacy: .public)")
        return true
    }

    @discardableResult
    private func finishContextMenuUpdateCheckIfReady(id: UUID? = nil) -> Bool {
        guard let check = contextMenuUpdateCheck,
              id == nil || id == check.id,
              let completion = check.resultBox.take()
        else { return false }

        contextMenuUpdateCheck = nil
        contextMenuUpdateStatusOverride = nil
        updateStore.finishCheck(check.request, completion: completion)
        statusBarUpdateLogger.info("Finish context menu update check generation=\(check.request.generation, privacy: .public)")
        return true
    }

    private func updateMenuActionSelector(for action: AppUpdateMenuItemAction?) -> Selector? {
        switch action {
        case .checkForUpdates:
            #selector(checkUpdateFromMenu)
        case .openUpdate:
            #selector(openUpdateFromMenu)
        case nil:
            nil
        }
    }

    private func disabledMenuItem(_ title: String, toolTip: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = toolTip
        return item
    }

    func checkForUpdates() {
        Task { [weak self] in
            await self?.onCheckUpdate(.interactive)
        }
    }

    @objc private func refreshFromMenu() {
        refreshQuotesAndStatusTitle()
    }

    @objc private func checkUpdateFromMenu() {
        checkForUpdates()
    }

    @objc private func openUpdateFromMenu() {
        onOpenUpdate()
    }

    @objc private func openSettingsFromMenu() {
        openSettingsForFocusedAccount()
    }

    @objc private func selectMenuBarContentModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = MenuBarContentMode(rawValue: rawValue)
        else { return }
        settingsStore.setMenuBarContentMode(mode)
        handleSettingsChanged()
    }

    @objc private func selectMenuBarDisplayModeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = MenuBarDisplayMode(rawValue: rawValue)
        else { return }
        settingsStore.setMenuBarDisplayMode(mode)
        handleSettingsChanged()
    }

}
