# fund-pulse

基金持仓收益状态栏工具。当前项目是 Swift 原生 macOS 菜单栏应用，以基金记录和收益查看为核心，保留新增基金、持仓配置、收益统计、菜单栏收益展示、数据导入导出和更新检查等能力。

## 开发

```bash
pnpm install
pnpm run build
pnpm run dev
```

默认开发、构建和打包命令已经指向 Swift 版：

```bash
pnpm run swift:run
pnpm run swift:verify
pnpm run package
```

Swift 版应用产物会生成在 `dist/fund-pulse.app`，发布包会生成在 `release/swift/`。

旧 Electron / React 工程源码已经移除，当前仓库以 SwiftPM 作为唯一构建入口。

## 数据源

- 基金实时净值、估值和基础信息：东方财富 / 天天基金相关接口
- Swift 版当前使用 `fundgz.1234567.com.cn` 作为实时估值源
- 养基宝小程序接口链路和板块字段维护记录见 [docs/yangjibao-api.md](docs/yangjibao-api.md)

## 数据文件

Swift 版固定读取和写入：

```text
~/Library/Application Support/fund-pulse/portfolio.json
~/Library/Application Support/fund-pulse/settings.json
```

旧版本加密数据可通过迁移脚本转换：

```bash
pnpm run swift:migrate
```

## 版本

当前版本以 `package.json` 为准，历史更新记录以本项目 `CHANGELOG.md` 为准。

每项面向用户的改动都应在 `.release-notes/` 增加一个 Markdown 片段，并和对应代码一起提交。发布脚本会按类型生成中文 GitHub Release 正文、更新 `CHANGELOG.md`，然后消费已发布的片段。

```markdown
---
type: optimization
---

行情刷新改为串行合并，避免并发请求造成状态覆盖。
```

支持的类型为 `breaking`、`feature`、`fix`、`optimization` 和 `other`。正文使用一句面向用户的中文说明，不要填写提交标题或占位内容。

发布前先提交所有业务改动并保持 `main` 与 `origin/main` 同步：

```bash
npm run release:dry
npm run release -- --yes
```

正式发布会先创建 Draft Release，校验正文、tag、ZIP、DMG 和 `latest-mac.yml` 后再公开。没有变更片段时默认拒绝发布；纯重新打包必须显式传入 `--allow-empty-notes`。
