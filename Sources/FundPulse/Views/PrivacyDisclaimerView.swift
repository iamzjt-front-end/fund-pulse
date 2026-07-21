import SwiftUI

struct PrivacyDisclaimerView: View {
    let onBack: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(
                systemImage: "hand.raised.fill",
                title: LegalContent.title,
                subtitle: LegalContent.updatedAtText,
                tint: Color(nsColor: .systemIndigo),
                onClose: onBack
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    introductionCard

                    ForEach(LegalContent.sections) { section in
                        LegalSectionView(section: section)
                    }

                    linksSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelDesign.panelBackground)
    }

    private var introductionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text("本地优先")
                    .font(.system(size: 12, weight: .semibold))
            } icon: {
                Image(systemName: "internaldrive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PanelDesign.accent)
            }

            Text(LegalContent.introduction)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }

    private var linksSection: some View {
        PanelSection(title: "相关链接") {
            VStack(spacing: 7) {
                PanelLinkButton(
                    title: "在线隐私政策",
                    subtitle: "查看仓库中的最新版本",
                    systemImage: "doc.text",
                    action: {
                        onOpenURL(AppExternalLinks.privacyPolicyURL)
                    }
                )
                PanelLinkButton(
                    title: "问题反馈",
                    subtitle: "选择 GitHub Issue 模板",
                    systemImage: "questionmark.circle",
                    action: {
                        onOpenURL(AppExternalLinks.issueChooserURL)
                    }
                )
            }
        }
    }
}

private struct LegalSectionView: View {
    let section: LegalContent.Section

    var body: some View {
        PanelSection(title: section.title) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(PanelDesign.accent.opacity(0.72))
                            .frame(width: 4, height: 4)
                        Text(bullet)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

#Preview("隐私与免责声明") {
    PrivacyDisclaimerView(
        onBack: {},
        onOpenURL: { _ in }
    )
    .frame(
        width: PopoverLayout.privacyDisclaimerSize.width,
        height: PopoverLayout.privacyDisclaimerSize.height
    )
}
