# Release note fragments

每项面向用户的改动应新增一个独立的 `.md` 文件，并和对应代码一起提交。

```markdown
---
type: optimization
---

行情刷新改为串行合并，避免并发请求造成状态覆盖。
```

支持的 `type`：

- `breaking`：重要变更
- `feature`：新功能
- `fix`：问题修复
- `optimization`：功能优化
- `other`：其他变更

约束：

- 正文只写一句面向用户的具体中文说明。
- 不要填写 `TODO`、`chore: release` 或笼统的重新打包说明。
- 文件名使用简短、稳定的英文 kebab-case。
- 发布脚本会自动更新 `CHANGELOG.md` 并删除本次已消费的片段；本说明文件会永久保留。
