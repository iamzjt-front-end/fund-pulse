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
