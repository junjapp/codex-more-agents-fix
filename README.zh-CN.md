# Codex More Agents Fix

[![GitHub release](https://img.shields.io/github/v/release/junjapp/codex-more-agents-fix?display_name=tag)](https://github.com/junjapp/codex-more-agents-fix/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-black)](#环境要求)
[![Language: English + 中文](https://img.shields.io/badge/Docs-English%20%2B%20%E4%B8%AD%E6%96%87-blue)](README.md)

一个面向 macOS 的安全型、仅做归档的工具，用来通过清理 stale subagent 线程，帮助 Codex 再次创建更多 agents。

English version: [README.md](README.md)

## 它修复什么问题

有时候 Codex 在较大的任务里会开始只创建很少的 agents。

一个常见原因，就是本地 Codex 状态库里堆积了太多 stale subagent 线程。

这个工具适合想要：

- 让 Codex 再次创建更多 agents
- 安全减少 stale subagent 堆积
- 先预演再执行，避免误操作
- 避免直接删除内部 Codex 状态记录带来的风险

## 快速开始

1. 打开最新的 [Releases](https://github.com/junjapp/codex-more-agents-fix/releases)。
2. 下载仓库源码压缩包。
3. 解压后双击 `bin/codex-more-agents-fix.command`。
4. 先运行 `Safe Preview`。
5. 如果候选结果合理，再执行 `Standard Cleanup`。

## 它会做什么

这个项目提供一个可双击执行的 `.command` 工具，它会：

- 从 `~/.codex` 自动发现正在使用的 Codex 线程状态库
- 先提供只读审计和预演
- 只归档 stale subagent 线程，不删除内部记录
- 在 Codex app 运行时阻止写入操作
- 每次写入前自动备份数据库

## 为什么只做归档

Codex 的内部状态基于 SQLite，而且可能包含多张相关联的表。官方没有公开保证这些内部表结构和删除语义对终端用户是稳定且安全的，因此本项目有意避免直接删除内部记录或做数据库压缩。

这个工具只做可逆的线程归档。

## 安全边界

- 只读模式可以随时安全运行。
- 写入模式要求先完全退出 Codex app。
- 工具不会删除内部状态记录。
- 工具不会执行 `VACUUM`。
- 每次写入前都会先创建备份。

## 包含的工具

- `bin/codex-more-agents-fix.command`

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

这个仓库只包含这个独立工具及其中英双语文档。
不包含其他研究文件、项目配置或私有工作区内容。

## 许可证

MIT
