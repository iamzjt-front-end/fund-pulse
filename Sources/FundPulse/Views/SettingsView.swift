import AppKit
import SwiftUI

private struct FocuslessSwitch: NSViewRepresentable {
    @Binding var isOn: Bool

    func makeNSView(context: Context) -> NoFocusSwitch {
        let control = NoFocusSwitch()
        control.target = context.coordinator
        control.action = #selector(Coordinator.valueChanged(_:))
        control.state = isOn ? .on : .off
        return control
    }

    func updateNSView(_ control: NoFocusSwitch, context: Context) {
        context.coordinator.isOn = $isOn
        control.state = isOn ? .on : .off
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
        }

        @MainActor
        @objc func valueChanged(_ sender: NSSwitch) {
            isOn.wrappedValue = sender.state == .on
        }
    }
}

private final class NoFocusSwitch: NSSwitch {
    override var acceptsFirstResponder: Bool { false }
}

struct SettingsView: View {
    let store: PortfolioStore
    let settingsStore: AppSettingsStore
    let updateStore: AppUpdateStore
    let appVersion: String
    let onSettingsChanged: (() -> Void)?
    let onRefresh: (() async -> Void)?
    let onCheckUpdate: (() async -> Void)?
    let onClose: (() -> Void)?

    @State private var message: String?
    @State private var selectedAutoRefreshInterval: AutoRefreshInterval
    @State private var mainPanelHeightText: String
    @FocusState private var isMainPanelHeightFocused: Bool

    init(
        store: PortfolioStore,
        settingsStore: AppSettingsStore,
        updateStore: AppUpdateStore,
        appVersion: String,
        onSettingsChanged: (() -> Void)?,
        onRefresh: (() async -> Void)?,
        onCheckUpdate: (() async -> Void)?,
        onClose: (() -> Void)?
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.updateStore = updateStore
        self.appVersion = appVersion
        self.onSettingsChanged = onSettingsChanged
        self.onRefresh = onRefresh
        self.onCheckUpdate = onCheckUpdate
        self.onClose = onClose
        _selectedAutoRefreshInterval = State(initialValue: settingsStore.settings.autoRefreshInterval)
        _mainPanelHeightText = State(initialValue: "\(settingsStore.settings.mainPanelHeight)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .layoutPriority(1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    PanelSection(title: "基金操作提醒") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("开启每日提醒")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("到点发送系统通知，提醒检查估值并决定加仓或减仓。")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                FocuslessSwitch(isOn: operationReminderEnabledBinding)
                                    .frame(width: 54, height: 30)
                            }

                            HStack {
                                Text("提醒时间")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                PanelNativeTimePicker(
                                    selection: operationReminderDateBinding,
                                    isEnabled: settingsStore.settings.operationReminderEnabled
                                )
                                .frame(width: 98, height: 24)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(PanelDesign.border(cornerRadius: 9))
                            .opacity(settingsStore.settings.operationReminderEnabled ? 1 : 0.58)
                        }
                    }

                    PanelSection(title: "自动刷新") {
                        PanelSegmentedPicker(
                            values: Array(AutoRefreshInterval.allCases),
                            selection: Binding(
                                get: { selectedAutoRefreshInterval },
                                set: { interval in
                                    selectedAutoRefreshInterval = interval
                                    settingsStore.setAutoRefreshInterval(interval)
                                    onSettingsChanged?()
                                }
                            ),
                            title: { $0.title }
                        )

                        Text(selectedAutoRefreshInterval.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(PanelDesign.border(cornerRadius: 9))
                    }

                    PanelSection(title: "主弹窗") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("高度")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                mainPanelHeightInput
                            }

                            Slider(
                                value: mainPanelHeightBinding,
                                in: Double(AppSettings.minMainPanelHeight)...Double(AppSettings.maxMainPanelHeight)
                            )
                            .controlSize(.small)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(PanelDesign.border(cornerRadius: 9))
                    }

                    if let message {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(PanelDesign.border(cornerRadius: 9))
                    }

                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)

            bottomActions
        }
        .frame(width: PopoverLayout.settingsWidth, height: PopoverLayout.height, alignment: .top)
        .background(PanelDesign.panelBackground)
        .onAppear {
            selectedAutoRefreshInterval = settingsStore.settings.autoRefreshInterval
            syncMainPanelHeightText()
        }
        .onChange(of: settingsStore.settings.mainPanelHeight) { _, _ in
            if !isMainPanelHeightFocused {
                syncMainPanelHeightText()
            }
        }
    }

    private var header: some View {
        PanelHeader(
            systemImage: "gearshape",
            title: "设置",
            subtitle: "v\(appVersion)",
            tint: Color(nsColor: .systemGray),
            onClose: { onClose?() }
        )
    }

    private var bottomActions: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.45)

            plainTextButton("退出", systemImage: "power", role: .destructive) {
                NSApp.terminate(nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(PanelDesign.panelBackground)
    }

    private var isUpdateBusy: Bool {
        switch updateStore.status {
        case .checking, .downloading, .installing:
            return true
        case .idle, .available, .downloaded, .upToDate, .failed:
            return false
        }
    }

    private var operationReminderEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.operationReminderEnabled },
            set: { isEnabled in
                settingsStore.setOperationReminderEnabled(isEnabled)
                onSettingsChanged?()
            }
        )
    }

    private var mainPanelHeightBinding: Binding<Double> {
        Binding(
            get: { Double(settingsStore.settings.mainPanelHeight) },
            set: { height in
                settingsStore.setMainPanelHeight(Int(height.rounded()))
                syncMainPanelHeightText()
                onSettingsChanged?()
            }
        )
    }

    private var mainPanelHeightInput: some View {
        HStack(spacing: 4) {
            TextField("", text: $mainPanelHeightText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .focused($isMainPanelHeightFocused)
                .onSubmit {
                    commitMainPanelHeightText()
                }
                .onChange(of: mainPanelHeightText) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        mainPanelHeightText = filtered
                    }
                }
                .onChange(of: isMainPanelHeightFocused) { _, isFocused in
                    if !isFocused {
                        commitMainPanelHeightText()
                    }
                }

            Text("px")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(width: 84, height: 26)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 7))
    }

    private func commitMainPanelHeightText() {
        guard let height = Int(mainPanelHeightText) else {
            syncMainPanelHeightText()
            return
        }

        let previousHeight = settingsStore.settings.mainPanelHeight
        settingsStore.setMainPanelHeight(height)
        syncMainPanelHeightText()

        if settingsStore.settings.mainPanelHeight != previousHeight {
            onSettingsChanged?()
        }
    }

    private func syncMainPanelHeightText() {
        mainPanelHeightText = "\(settingsStore.settings.mainPanelHeight)"
    }

    private var operationReminderDateBinding: Binding<Date> {
        Binding(
            get: {
                dateForReminderMinutes(settingsStore.settings.operationReminderTimeMinutes)
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (components.hour ?? 14) * 60 + (components.minute ?? 30)
                settingsStore.setOperationReminderTimeMinutes(minutes)
                onSettingsChanged?()
            }
        )
    }

    private func dateForReminderMinutes(_ minutes: Int) -> Date {
        let clampedMinutes = AppSettings.clampedReminderTimeMinutes(minutes)
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = clampedMinutes / 60
        components.minute = clampedMinutes % 60
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateStore.status {
        case .idle:
            statusText("尚未检查更新")
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检查更新")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        case .available(let info):
            VStack(alignment: .leading, spacing: 4) {
                Text("发现新版本 v\(info.version)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                if !info.releaseName.isEmpty {
                    Text(info.releaseName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 0.6)
            )
        case .downloading(let info):
            HStack(spacing: 8) {
                UpdateProgressRing(progress: updateStore.downloadProgress)
                    .frame(width: 22, height: 22)
                Text("正在下载 v\(info.version) · \(Int(updateStore.downloadProgress * 100))%")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        case .downloaded(let info, let package):
            VStack(alignment: .leading, spacing: 4) {
                Text("更新已下载")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text("v\(info.version) · \(package.downloadedAt.formatted(date: .omitted, time: .shortened)) · 点击“现在更新”后会自动重启")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.green.opacity(0.18), lineWidth: 0.6)
            )
        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在更新，完成后会自动重启")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
        case .upToDate(let date):
            statusText("已是最新版本 · \(date.formatted(date: .omitted, time: .shortened))")
        case .failed(let reason):
            Text("检查失败：\(reason)")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 0.6)
                )
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func dataSourceRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .medium))
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(.primary)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 9))
    }

    private func plainTextButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            PanelButtonLabel(
                title: title,
                systemImage: systemImage,
                style: role == .destructive ? .destructive : .secondary
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func checkUpdate() {
        Task {
            await onCheckUpdate?()
        }
    }
}
