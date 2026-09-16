import AppKit
import UniformTypeIdentifiers

@MainActor
enum PortfolioBackupController {
    static func exportAll(accounts: PortfolioAccountsStore) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "备份全部账户"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "fund-pulse-all-accounts-\(DateOnlyFormatter.string(from: .now)).json"
        panel.message = "保存所有账户、持仓、交易和收益历史。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try accounts.exportBackup(to: url) }
        catch { show(error, title: "备份失败") }
    }

    @discardableResult
    static func restoreAll(accounts: PortfolioAccountsStore, latest: Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let url: URL
        if latest {
            guard let saved = accounts.latestBackupURL else { return false }
            url = saved
        } else {
            let panel = NSOpenPanel()
            panel.title = "恢复全部账户"
            panel.allowedContentTypes = [.json]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let selected = panel.url else { return false }
            url = selected
        }
        do {
            let backup = try accounts.previewBackup(from: url)
            let confirmation = NSAlert()
            confirmation.messageText = "恢复全部账户？"
            let fundCount = backup.portfolios.values.reduce(0) { $0 + $1.funds.count }
            confirmation.informativeText = "将恢复 \(backup.registry.accounts.count) 个账户、\(fundCount) 只基金（备份时间：\(backup.createdAt.formatted())）。当前全部账户会先保存备份，可用“撤销最近一次账户恢复”找回。"
            confirmation.addButton(withTitle: "备份并恢复")
            confirmation.addButton(withTitle: "取消")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return false }
            try accounts.restoreBackup(backup)
            return true
        } catch {
            show(error, title: "恢复失败")
            return false
        }
    }

    private static func show(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
