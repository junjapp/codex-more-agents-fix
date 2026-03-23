# Codex Subagent Cleaner

一个面向 macOS 的、仅做归档的 Codex stale subagent 清理工具。

English version: [README.md](README.md)

## 它能做什么

这个项目提供一个可双击执行的 `.command` 工具，用来缓解 Codex stale subagent 堆积问题。它会：

- 从 `~/.codex` 自动发现正在使用的 Codex 线程状态库
- 先提供只读审计和预演
- 只归档 stale subagent 线程，不删除内部记录
- 在 Codex app 运行时阻止写入操作
- 每次写入前自动备份数据库

## 为什么只做归档

Codex 的内部状态基于 SQLite，而且可能包含多张相关联的表。官方没有公开保证这些内部表结构和删除语义对终端用户是稳定且安全的，因此本项目有意避免直接删除内部记录或做数据库压缩。

这个工具只做可逆的线程归档。

## 安全边界

- 只读模式可以安全运行。
- 写入模式要求先完全退出 Codex app。
- 工具不会删除内部状态记录。
- 工具不会执行 `VACUUM`。
- 每次写入前都会先创建备份。

## 包含的工具

- `bin/codex-subagent-cleaner.command`

## 使用方法

1. 下载本仓库。
2. 双击 `bin/codex-subagent-cleaner.command`。
3. 先从 `Safe Preview` 开始。
4. 如果候选结果合理，再执行 `Standard Cleanup`。

## 清理等级

- `State DB Audit`：检查检测到的状态库和当前线程分布。
- `Safe Preview`：只模拟命中结果，不写入变更。
- `Light Cleanup`：归档 24 小时以上 stale subagents。
- `Standard Cleanup`：归档 6 小时以上 stale subagents。
- `Deep Cleanup`：归档 1 小时以上 stale subagents。
- `Main-Thread Cleanup`：归档 1 小时以上 stale subagents，并归档 7 天以上 stale 主线程。
- `Custom Cleanup`：自定义阈值，先预演，再执行。

## 环境要求

- macOS
- 已安装 Codex 桌面端，或至少存在 `~/.codex` 状态目录
- `zsh`
- 系统 Python 3
- `PATH` 中可用的 `rg`

## 仓库范围

这个仓库只包含这个独立清理工具及其文档。
不包含其他研究文件、项目配置或私有工作区内容。

## 许可证

MIT
