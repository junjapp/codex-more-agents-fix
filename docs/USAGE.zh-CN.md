# Codex More Agents Fix 使用指南

## 适合谁用

如果 Codex 以前在较大任务里会创建多个 helper agents，但现在经常只创建很少几个，就适合用这个工具。

## 这个工具会改什么

这个工具不会删除 Codex 内部记录。
它只会归档 stale subagent 线程，减少本地状态里残留的 stale active threads。

## 使用前先确认

请先确认：

- 你使用的是 macOS
- 这台 Mac 上已经用过 Codex
- 做真正写入清理前，Codex app 已经完全退出

## 最安全的使用方式

1. 双击 `bin/codex-more-agents-fix.command`。
2. 先选择 `Safe Preview`。
3. 看候选列表是否合理。
4. 如果合理，再执行 `Standard Cleanup`。
5. 重新打开 Codex，用一个较大的任务测试它是否开始创建更多 agents。

## 各个清理等级是什么意思

### State DB Audit
只查看检测到的数据库和当前线程数量，不做任何修改。

### Safe Preview
先看哪些线程会被归档，不真正写入。

### Light Cleanup
归档 24 小时以上 stale subagents。
适合最保守的写入清理。

### Standard Cleanup
归档 6 小时以上 stale subagents。
适合作为日常常规清理。

### Deep Cleanup
归档 1 小时以上 stale subagents。
适合 Codex 明显开始只创建很少 helper agents 的情况。

### Main-Thread Cleanup
额外归档 7 天以上 stale 主线程。
只有当你明白这会让一部分旧主对话进入 archived 状态时才建议使用。

### Custom Cleanup
允许你自己设置阈值。
只有在内置等级不适合你时才建议使用。

## 安全说明

- 只读模式永远比写入模式更安全。
- 如果 Codex app 还在运行，工具会阻止写入。
- 每次写入前都会自动创建备份。
- 这个项目有意避免删除内部记录，也不会执行 `VACUUM`。

## 如果你想回退

这个工具在每次写入前都会创建备份。
如果你需要检查或恢复，可以使用本地 Codex 备份目录中的备份文件。

## 清理后的预期

它不会保证一个固定的 agent 数量。
它的目标是减少 stale 本地状态压力，让 Codex 更有机会重新做出更合理的 helper-agent 创建决策。
