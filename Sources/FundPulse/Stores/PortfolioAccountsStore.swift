import Foundation
import Observation

struct PortfolioAccountsRegistry: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var accounts: [PortfolioAccount]
    /// `nil` means the read-only "all accounts" overview is selected.
    var selectedAccountID: String?
    /// Retains an account context for account-scoped commands while the overview is selected.
    var lastSelectedAccountID: String?
}

enum PortfolioAccountsStoreError: LocalizedError, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidRegistry(String)
    case unreadableRegistry(String)
    case invalidName
    case duplicateName
    case accountNotFound
    case cannotArchiveDefaultAccount
    case accountIsRefreshing

    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion(let version):
            "账户配置来自更高版本（v\(version)），当前版本不会覆盖它"
        case .invalidRegistry(let reason):
            "账户配置无效，当前版本不会覆盖它：\(reason)"
        case .unreadableRegistry(let reason):
            "账户配置暂时无法读取，当前版本不会覆盖它：\(reason)"
        case .invalidName:
            "请输入账户名称"
        case .duplicateName:
            "已经存在同名账户"
        case .accountNotFound:
            "未找到这个账户"
        case .cannotArchiveDefaultAccount:
            "默认账户保存着升级前的数据，不能移除；可以清空其中的持仓"
        case .accountIsRefreshing:
            "账户正在刷新，请稍后再移除"
        }
    }
}

@Observable
@MainActor
final class PortfolioAccountsStore {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var accounts: [PortfolioAccount]
    private(set) var selection: PortfolioAccountSelection
    private(set) var loadState: LoadState = .loading
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    let dataDirectory: URL
    private let legacyStore: PortfolioStore
    private var storesByID: [String: PortfolioStore]
    private var lastSelectedAccountID: String
    private var refreshOperationCount = 0
    private let nowProvider: () -> Date

    init(
        dataDirectory: URL = AppDataPaths.sharedDataDirectory,
        legacyStore: PortfolioStore? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        let defaultAccount = PortfolioAccount.defaultAccount(createdAt: now())
        self.dataDirectory = dataDirectory
        self.legacyStore = legacyStore ?? PortfolioStore(dataDirectory: dataDirectory, now: now)
        self.accounts = [defaultAccount]
        self.selection = .account(defaultAccount.id)
        self.storesByID = [defaultAccount.id: self.legacyStore]
        self.lastSelectedAccountID = defaultAccount.id
        self.nowProvider = now
    }

    var registryFileURL: URL {
        dataDirectory.appending(path: "accounts.json")
    }

    var accountsDataDirectory: URL {
        dataDirectory.appending(path: "accounts", directoryHint: .isDirectory)
    }

    var focusedAccount: PortfolioAccount {
        account(id: lastSelectedAccountID) ?? accounts[0]
    }

    var focusedStore: PortfolioStore {
        store(for: focusedAccount.id) ?? legacyStore
    }

    var selectedAccount: PortfolioAccount? {
        guard let id = selection.accountID else { return nil }
        return account(id: id)
    }

    var selectedStore: PortfolioStore? {
        guard let id = selection.accountID else { return nil }
        return store(for: id)
    }

    var defaultStore: PortfolioStore {
        legacyStore
    }

    var summary: PortfolioAccountsSummary {
        PortfolioAccountsSummary.aggregating(accounts.compactMap { store(for: $0.id)?.snapshot })
    }

    func account(id: String) -> PortfolioAccount? {
        accounts.first { $0.id == id }
    }

    func store(for accountID: String) -> PortfolioStore? {
        storesByID[accountID]
    }

    func dataDirectory(for account: PortfolioAccount) -> URL {
        guard let directoryName = account.directoryName else { return dataDirectory }
        return accountsDataDirectory.appending(path: directoryName, directoryHint: .isDirectory)
    }

    func load() {
        loadState = .loading
        do {
            let registry = try loadOrCreateRegistry()
            try validate(registry)
            let normalized = normalizedRegistry(registry)
            apply(normalized)
            loadState = .loaded
            lastError = nil
        } catch {
            // Keep the original root portfolio available without rewriting a damaged registry.
            let fallback = PortfolioAccount.defaultAccount(createdAt: nowProvider())
            accounts = [fallback]
            selection = .account(fallback.id)
            lastSelectedAccountID = fallback.id
            storesByID = [fallback.id: legacyStore]
            legacyStore.load()
            loadState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func select(_ nextSelection: PortfolioAccountSelection) {
        let normalized: PortfolioAccountSelection
        switch nextSelection {
        case .all:
            normalized = .all
        case .account(let id):
            guard account(id: id) != nil else { return }
            normalized = .account(id)
            lastSelectedAccountID = id
        }

        guard normalized != selection else { return }
        selection = normalized
        persistCurrentRegistryWithoutThrowing()
    }

    @discardableResult
    func createAccount(name: String, kind: PortfolioAccountKind) throws -> PortfolioAccount {
        try ensureRegistryIsWritable()
        let normalizedName = try validatedName(name, excludingAccountID: nil)
        let id = UUID().uuidString.lowercased()
        let account = PortfolioAccount(
            id: id,
            name: normalizedName,
            kind: kind,
            createdAt: nowProvider(),
            directoryName: id
        )
        let accountDirectory = dataDirectory(for: account)
        let repository = JSONPortfolioRepository(dataDirectory: accountDirectory)
        var emptySnapshot = PortfolioSnapshot.empty
        emptySnapshot.updateTime = nowProvider()

        try repository.save(emptySnapshot)
        let nextAccounts = accounts + [account]
        let nextRegistry = makeRegistry(
            accounts: nextAccounts,
            selection: .account(account.id),
            lastSelectedAccountID: account.id
        )

        do {
            try persist(nextRegistry)
        } catch {
            try? FileManager.default.removeItem(at: accountDirectory)
            throw error
        }

        let store = PortfolioStore(
            dataDirectory: accountDirectory,
            accountKind: account.kind,
            now: nowProvider
        )
        store.load()
        accounts = nextAccounts
        storesByID[account.id] = store
        selection = .account(account.id)
        lastSelectedAccountID = account.id
        lastError = nil
        return account
    }

    func renameAccount(id: String, name: String) throws {
        try ensureRegistryIsWritable()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw PortfolioAccountsStoreError.accountNotFound
        }
        let normalizedName = try validatedName(name, excludingAccountID: id)
        var nextAccounts = accounts
        nextAccounts[index].name = normalizedName
        try persist(makeRegistry(accounts: nextAccounts))
        accounts = nextAccounts
        lastError = nil
    }

    func moveAccount(id: String, by offset: Int) throws {
        try ensureRegistryIsWritable()
        guard offset != 0,
              let sourceIndex = accounts.firstIndex(where: { $0.id == id })
        else { return }
        let destinationIndex = sourceIndex + offset
        guard accounts.indices.contains(destinationIndex) else { return }

        var nextAccounts = accounts
        let moved = nextAccounts.remove(at: sourceIndex)
        nextAccounts.insert(moved, at: destinationIndex)
        try persist(makeRegistry(accounts: nextAccounts))
        accounts = nextAccounts
        lastError = nil
    }

    /// Removes a non-default account from the active list and moves its directory into
    /// "Archived Accounts" so the operation remains recoverable.
    func archiveAccount(id: String) throws {
        try ensureRegistryIsWritable()
        guard refreshOperationCount == 0 else {
            throw PortfolioAccountsStoreError.accountIsRefreshing
        }
        guard id != PortfolioAccount.defaultAccountID else {
            throw PortfolioAccountsStoreError.cannotArchiveDefaultAccount
        }
        guard let account = account(id: id), let directoryName = account.directoryName else {
            throw PortfolioAccountsStoreError.accountNotFound
        }

        let sourceURL = dataDirectory(for: account)
        let archiveRoot = dataDirectory.appending(path: "Archived Accounts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        let timestamp = Int(nowProvider().timeIntervalSince1970)
        var destinationURL = archiveRoot.appending(path: "\(directoryName)-\(timestamp)", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = archiveRoot.appending(path: "\(directoryName)-\(timestamp)-\(UUID().uuidString.lowercased())")
        }

        let sourceExists = FileManager.default.fileExists(atPath: sourceURL.path)
        if sourceExists {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }

        let nextAccounts = accounts.filter { $0.id != id }
        let nextLastSelectedID = nextAccounts.contains { $0.id == lastSelectedAccountID }
            ? lastSelectedAccountID
            : (nextAccounts.first?.id ?? PortfolioAccount.defaultAccountID)
        let nextSelection: PortfolioAccountSelection = {
            guard selection.accountID == id else { return selection }
            return .account(nextLastSelectedID)
        }()
        let nextRegistry = makeRegistry(
            accounts: nextAccounts,
            selection: nextSelection,
            lastSelectedAccountID: nextLastSelectedID
        )

        do {
            try persist(nextRegistry)
        } catch {
            if sourceExists {
                try? FileManager.default.moveItem(at: destinationURL, to: sourceURL)
            }
            throw error
        }

        accounts = nextAccounts
        storesByID.removeValue(forKey: id)
        lastSelectedAccountID = nextLastSelectedID
        selection = nextSelection
        lastError = nil
    }

    func refreshQuotes() async {
        refreshOperationCount += 1
        isRefreshing = true
        defer {
            refreshOperationCount -= 1
            isRefreshing = refreshOperationCount > 0
        }
        for account in accounts {
            await store(for: account.id)?.refreshQuotes()
        }
    }

    private func loadOrCreateRegistry() throws -> PortfolioAccountsRegistry {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: registryFileURL.path) else {
            let defaultAccount = PortfolioAccount.defaultAccount(createdAt: nowProvider())
            let registry = PortfolioAccountsRegistry(
                accounts: [defaultAccount],
                selectedAccountID: defaultAccount.id,
                lastSelectedAccountID: defaultAccount.id
            )
            try persist(registry)
            return registry
        }

        do {
            let data = try Data(contentsOf: registryFileURL)
            return try Self.decoder.decode(PortfolioAccountsRegistry.self, from: data)
        } catch let error as PortfolioAccountsStoreError {
            throw error
        } catch {
            throw PortfolioAccountsStoreError.unreadableRegistry(error.localizedDescription)
        }
    }

    private func validate(_ registry: PortfolioAccountsRegistry) throws {
        guard registry.schemaVersion <= PortfolioAccountsRegistry.currentSchemaVersion else {
            throw PortfolioAccountsStoreError.unsupportedSchemaVersion(registry.schemaVersion)
        }
        guard !registry.accounts.isEmpty else {
            throw PortfolioAccountsStoreError.invalidRegistry("至少需要一个账户")
        }
        guard Set(registry.accounts.map(\.id)).count == registry.accounts.count else {
            throw PortfolioAccountsStoreError.invalidRegistry("存在重复账户标识")
        }
        guard registry.accounts.contains(where: { $0.id == PortfolioAccount.defaultAccountID }) else {
            throw PortfolioAccountsStoreError.invalidRegistry("缺少默认账户")
        }
        guard registry.accounts.first(where: { $0.id == PortfolioAccount.defaultAccountID })?.directoryName == nil else {
            throw PortfolioAccountsStoreError.invalidRegistry("默认账户目录位置不正确")
        }
        guard registry.accounts.first(where: { $0.id == PortfolioAccount.defaultAccountID })?.kind == .offExchange else {
            throw PortfolioAccountsStoreError.invalidRegistry("默认账户类型不正确")
        }

        let directoryNames = registry.accounts.compactMap(\.directoryName)
        guard Set(directoryNames).count == directoryNames.count else {
            throw PortfolioAccountsStoreError.invalidRegistry("存在重复账户目录")
        }
        guard directoryNames.allSatisfy(Self.isSafeDirectoryName) else {
            throw PortfolioAccountsStoreError.invalidRegistry("账户目录名称不安全")
        }
        guard registry.accounts.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw PortfolioAccountsStoreError.invalidRegistry("存在空账户名称")
        }
        let normalizedNames = registry.accounts.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
        }
        guard Set(normalizedNames).count == normalizedNames.count else {
            throw PortfolioAccountsStoreError.invalidRegistry("存在重复账户名称")
        }
    }

    private func normalizedRegistry(_ registry: PortfolioAccountsRegistry) -> PortfolioAccountsRegistry {
        let accountIDs = Set(registry.accounts.map(\.id))
        let fallbackID = registry.lastSelectedAccountID.flatMap { accountIDs.contains($0) ? $0 : nil }
            ?? PortfolioAccount.defaultAccountID
        let selectedID = registry.selectedAccountID.flatMap { accountIDs.contains($0) ? $0 : nil }
        return PortfolioAccountsRegistry(
            accounts: registry.accounts,
            selectedAccountID: registry.selectedAccountID == nil ? nil : (selectedID ?? fallbackID),
            lastSelectedAccountID: fallbackID
        )
    }

    private func apply(_ registry: PortfolioAccountsRegistry) {
        var nextStores: [String: PortfolioStore] = [:]
        for account in registry.accounts {
            let store: PortfolioStore
            if account.isDefault {
                store = legacyStore
            } else {
                store = PortfolioStore(
                    dataDirectory: dataDirectory(for: account),
                    accountKind: account.kind,
                    now: nowProvider
                )
            }
            store.load()
            nextStores[account.id] = store
        }

        accounts = registry.accounts
        storesByID = nextStores
        lastSelectedAccountID = registry.lastSelectedAccountID ?? PortfolioAccount.defaultAccountID
        selection = registry.selectedAccountID.map(PortfolioAccountSelection.account) ?? .all
    }

    private func validatedName(_ rawName: String, excludingAccountID: String?) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PortfolioAccountsStoreError.invalidName }
        guard !accounts.contains(where: {
            $0.id != excludingAccountID && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw PortfolioAccountsStoreError.duplicateName
        }
        return name
    }

    private func ensureRegistryIsWritable() throws {
        if case .failed(let reason) = loadState {
            throw PortfolioAccountsStoreError.unreadableRegistry(reason)
        }
    }

    private func makeRegistry(
        accounts: [PortfolioAccount]? = nil,
        selection: PortfolioAccountSelection? = nil,
        lastSelectedAccountID: String? = nil
    ) -> PortfolioAccountsRegistry {
        let resolvedSelection = selection ?? self.selection
        return PortfolioAccountsRegistry(
            accounts: accounts ?? self.accounts,
            selectedAccountID: resolvedSelection.accountID,
            lastSelectedAccountID: lastSelectedAccountID ?? self.lastSelectedAccountID
        )
    }

    private func persistCurrentRegistryWithoutThrowing() {
        do {
            try ensureRegistryIsWritable()
            try persist(makeRegistry())
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persist(_ registry: PortfolioAccountsRegistry) throws {
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Self.encoder.encode(registry).write(to: registryFileURL, options: .atomic)
    }

    private static func isSafeDirectoryName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains(":")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
