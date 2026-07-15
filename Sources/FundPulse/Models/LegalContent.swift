import Foundation

enum LegalContent {
    struct Section: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let paragraphs: [String]
        let bullets: [String]

        init(
            id: String,
            title: String,
            paragraphs: [String] = [],
            bullets: [String] = []
        ) {
            self.id = id
            self.title = title
            self.paragraphs = paragraphs
            self.bullets = bullets
        }
    }

    static let title = "隐私与免责声明"
    static let subtitle = "数据使用、第三方服务与风险说明"
    static let updatedAtText = "更新日期：2026 年 7 月 15 日"
    static let introduction = "Fund Pulse 是一款本地优先的基金持仓与行情查看工具。请在使用前阅读并理解以下说明。"

    static let privacyPolicyURL = URL(
        string: "https://github.com/iamzjt-front-end/fund-pulse/blob/main/PRIVACY.md"
    )!
    static let supportURL = URL(
        string: "https://github.com/iamzjt-front-end/fund-pulse/issues"
    )!

    static let sections: [Section] = [
        Section(
            id: "local-data",
            title: "本地保存的数据",
            paragraphs: [
                "Fund Pulse 没有自有账号系统。你的持仓与偏好默认保存在当前 Mac 的 Application Support/fund-pulse 目录中，不会上传到 Fund Pulse 自有服务器。"
            ],
            bullets: [
                "portfolio.json：基金持仓、金额或份额、成本与收益、待确认操作、交易记录及京东同步状态等。",
                "settings.json：外观、刷新频率、提醒与功能开关等应用设置。",
                "portfolio-performance.json：组合历史收益、每日盈亏、京东同步范围与不可逆账号指纹，用于生成曲线和日历及避免混入不同账号数据。"
            ]
        ),
        Section(
            id: "market-providers",
            title: "行情与公开市场数据",
            paragraphs: [
                "为展示基金净值、估值、基金资料、股票涨跌、指数和市场涨跌分布，应用会直接请求第三方公开数据服务。"
            ],
            bullets: [
                "东方财富：发送基金代码、基金搜索词或公开市场标识，以获取基金和市场数据。",
                "腾讯：发送公开股票代码，以获取基金披露持仓所对应的股票行情。",
                "同花顺：请求全市场涨跌分布等公开市场数据。",
                "这些服务可能按各自规则记录 IP 地址、请求时间、设备或网络信息；其处理方式由相应第三方的隐私政策约束。"
            ]
        ),
        Section(
            id: "jd-finance",
            title: "可选的京东金融同步",
            paragraphs: [
                "只有在你主动使用京东金融登录或同步功能时，应用才会读取 WebKit 中属于京东相关域名的登录 Cookie，并仅向京东相关服务发送完成鉴权所需的最小 Cookie 集，以读取你的基金持仓、交易记录和历史收益记录。",
                "Fund Pulse 不会把京东 Cookie 发送到自有服务器、行情服务商或 GitHub。你可以随时在“设置 > 数据 > 京东会话”中清除京东登录数据。"
            ]
        ),
        Section(
            id: "updates",
            title: "GitHub 更新检查",
            paragraphs: [
                "应用启动时会自动访问 GitHub Releases 检查新版本，你也可以手动发起检查。请求用于读取版本、发布说明和安装包信息；GitHub 可能依据其隐私政策处理 IP 地址、请求时间和网络信息。"
            ]
        ),
        Section(
            id: "collection-boundaries",
            title: "我们不收集什么",
            bullets: [
                "应用不提供自有账号、云端同步或自有数据后台。",
                "应用不包含广告 SDK 或分析 SDK，也不进行跨应用跟踪。",
                "应用不会出售你的持仓、交易记录或使用行为数据。"
            ]
        ),
        Section(
            id: "retention-deletion",
            title: "保存期限与数据删除",
            paragraphs: [
                "本地数据会一直保留，直到你主动清除。设置中的“清空所有持仓”可删除本地基金列表、待确认操作、交易记录、组合收益历史和当前收益汇总；“设置 > 数据 > 京东会话”可清除京东登录数据。",
                "macOS 删除应用本体不一定会同时删除 Application Support 数据。如需彻底删除全部本地数据，请退出 Fund Pulse 后删除 ~/Library/Application Support/fund-pulse 目录；操作前请自行备份需要保留的数据。"
            ]
        ),
        Section(
            id: "financial-disclaimer",
            title: "行情与投资免责声明",
            paragraphs: [
                "应用展示的盘中估值是依据第三方数据进行的估算，不是基金管理人公布的官方净值。行情、净值、持仓披露和计算结果可能存在延迟、缺失或错误。",
                "Fund Pulse 仅用于个人记录与信息参考，不构成投资建议、要约、招揽或交易依据，不承诺数据完整准确，也不承诺任何投资收益。投资决策及其损失由你自行承担。"
            ]
        ),
        Section(
            id: "third-party-independence",
            title: "第三方独立性",
            paragraphs: [
                "Fund Pulse 是独立开发的第三方工具，与东方财富、腾讯、同花顺、京东、GitHub、基金公司及销售机构不存在隶属、代理、认可或合作关系。第三方名称和商标归各自权利人所有。"
            ]
        )
    ]

    static var searchableText: String {
        ([title, subtitle, updatedAtText, introduction] + sections.flatMap { section in
            [section.title] + section.paragraphs + section.bullets
        })
        .joined(separator: "\n")
    }
}
