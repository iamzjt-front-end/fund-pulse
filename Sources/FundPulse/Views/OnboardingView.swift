import SwiftUI

struct OnboardingStepState: Equatable {
    private(set) var step: Int

    init(initialStep: Int = 0) {
        step = Self.clamped(initialStep)
    }

    mutating func select(_ step: Int) {
        self.step = Self.clamped(step)
    }

    mutating func advance() {
        select(step + 1)
    }

    mutating func retreat() {
        select(step - 1)
    }

    private static func clamped(_ step: Int) -> Int {
        min(max(step, 0), 2)
    }
}

struct OnboardingView: View {
    let onAddFund: () -> Void
    let onImportPortfolio: () -> Void
    let onOpenSample: () -> Void
    let onStartEmpty: () -> Void
    let onOpenPrivacy: () -> Void
    let onClose: () -> Void

    @State private var stepState: OnboardingStepState

    init(
        initialStep: Int = 0,
        onAddFund: @escaping () -> Void = {},
        onImportPortfolio: @escaping () -> Void = {},
        onOpenSample: @escaping () -> Void = {},
        onStartEmpty: @escaping () -> Void = {},
        onOpenPrivacy: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        _stepState = State(initialValue: OnboardingStepState(initialStep: initialStep))
        self.onAddFund = onAddFund
        self.onImportPortfolio = onImportPortfolio
        self.onOpenSample = onOpenSample
        self.onStartEmpty = onStartEmpty
        self.onOpenPrivacy = onOpenPrivacy
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "wave.3.right.circle.fill",
                title: "欢迎使用 Fund Pulse",
                subtitle: "首次设置 · 第 \(step + 1) / 3 步",
                accessoryText: "本地优先",
                accessoryColor: .green,
                onClose: onClose
            )

            VStack(spacing: 14) {
                progress

                Group {
                    switch step {
                    case 0:
                        welcomeStep
                    case 1:
                        privacyStep
                    default:
                        dataStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(PanelDesign.panelBackground)
    }

    private var step: Int {
        stepState.step
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< 3, id: \.self) { index in
                Button {
                    stepState.select(index)
                } label: {
                    Capsule()
                        .fill(index <= step ? PanelDesign.accent : Color.secondary.opacity(0.18))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("切换到第 \(index + 1) 步")
                .accessibilityLabel("第 \(index + 1) 步")
                .accessibilityValue(index == step ? "当前步骤" : "可切换")
            }
        }
        .accessibilityLabel("引导进度，第 \(step + 1) 步，共 3 步")
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("把持仓变化看清楚")
                    .font(.system(size: 22, weight: .bold))
                Text("记录基金持仓、查看实时估值，并在持仓收益中通过排行、曲线和日历回顾表现。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 9) {
                featureRow(icon: "chart.line.uptrend.xyaxis", title: "持仓收益", detail: "通过收益排行、曲线和日历查看持仓表现")
                featureRow(icon: "calendar", title: "每日盈亏", detail: "按日期查看变化，不再依赖零散截图")
                featureRow(icon: "bell.badge", title: "自定义提醒", detail: "在你设定的时间和阈值触发系统通知")
            }
        }
    }

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("你的数据由你掌控")
                    .font(.system(size: 22, weight: .bold))
                Text("持仓、交易记录与设置保存在这台 Mac。本页仅作说明，不要求勾选同意。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PanelSection(title: "开始前请了解") {
                VStack(alignment: .leading, spacing: 9) {
                    noticeRow(icon: "externaldrive", text: "真实持仓数据默认保存在本机应用数据目录")
                    noticeRow(icon: "network", text: "查询行情时会向第三方行情服务发送基金代码")
                    noticeRow(icon: "exclamationmark.triangle", text: "估值可能延迟或有误，仅供参考，不构成投资建议")
                }
            }

            Button(action: onOpenPrivacy) {
                HStack {
                    Image(systemName: "hand.raised")
                    Text("查看完整隐私说明与免责声明")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PanelDesign.accent)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(PanelDesign.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(PanelDesign.accent.opacity(0.2), lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
        }
    }

    private var dataStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("从哪里开始？")
                    .font(.system(size: 22, weight: .bold))
                Text("你可以立即录入、导入已有备份，或先用完全离线的示例体验。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            onboardingAction(
                icon: "plus.circle.fill",
                title: "添加第一只基金",
                detail: "录入真实持仓，开始跟踪",
                tint: PanelDesign.accent,
                action: onAddFund
            )
            onboardingAction(
                icon: "square.and.arrow.down",
                title: "导入备份",
                detail: "从 Fund Pulse JSON 备份恢复",
                tint: .blue,
                action: onImportPortfolio
            )
            onboardingAction(
                icon: "sparkles.rectangle.stack",
                title: "体验示例数据",
                detail: "3 只虚构基金与近 90 个自然日的示例收益；不联网、不写入真实数据",
                tint: .orange,
                badge: "临时",
                action: onOpenSample
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button("上一步") {
                    stepState.retreat()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            if step < 2 {
                Button("继续") {
                    stepState.advance()
                }
                .buttonStyle(.borderedProminent)
                .tint(PanelDesign.accent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("暂不添加，空白开始", action: onStartEmpty)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(height: 30)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PanelDesign.accent)
                .frame(width: 34, height: 34)
                .background(PanelDesign.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private func noticeRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingAction(
        icon: String,
        title: String,
        detail: String,
        tint: Color,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(tint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.1), in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(PanelDesign.border(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }
}
