# 云端打包与更新校验

`Build` 手动构建、`Build Beta` 在 beta 分支构建，均只输出 workflow artifacts。GitHub Release 的创建与上传仍由 `scripts/release.sh` 负责，避免两条流程重复发布。云端使用 macOS 15、Xcode 26.3，执行 Swift、发布脚本、README 和 CI 签名生命周期测试。

仓库管理员需在 GitHub Actions Secrets 配置以下值后才能进行签名打包；代码修改不会自动创建这些凭据：

| Secret | 含义 |
| --- | --- |
| MACOS_CERTIFICATE_BASE64 | 带私钥的 Developer ID Application `.p12` 文件的 base64 |
| MACOS_CERTIFICATE_PASSWORD | `.p12` 导出密码 |
| MACOS_SIGN_IDENTITY | 完整 Developer ID Application 证书名称 |
| APPLE_ID | 用于公证的 Apple ID |
| APPLE_TEAM_ID | 开发者团队 ID |
| APPLE_APP_PASSWORD | Apple 应用专用密码 |

`script/ci_package.sh` 在独立临时钥匙串中导入证书及公证凭据。成功、失败和中断均恢复原钥匙串搜索列表并删除临时凭据。测试通过模拟工具验证流程，不访问真实钥匙串或提交公证。

自动更新要求 ZIP 摘要匹配（GitHub `sha256` 或 `latest-mac.yml` 的 `sha512`），应用标识和发布版本完全一致，且当前应用与更新应用均具有 Apple 信任链下同一 Team ID 的 Developer ID Application 签名。证书续期可保持兼容；换团队需手动安装。开发签名或缺少摘要的旧包会拒绝自动安装，并展示失败原因，可通过发布页面手动更新。

日历覆盖 2024–2026 年。新增年份须依据交易所正式通知更新覆盖范围及休市数据，并运行跨年测试；未知年份不会默认按工作日推算受理日。

参考：[GitHub runner 镜像](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)、[Apple 签名信任说明](https://developer.apple.com/library/archive/technotes/tn2206/)、[上交所 2024 年休市安排](https://www.sse.com.cn/disclosure/dealinstruc/closed/c/c_20231226_5733941.shtml)、[2025 年休市安排](https://www.sse.com.cn/disclosure/dealinstruc/closed/c/c_20241223_10767110.shtml)。
