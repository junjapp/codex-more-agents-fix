# Codex More Agents Fix

[![GitHub release](https://img.shields.io/github/v/release/junjapp/codex-more-agents-fix?display_name=tag)](https://github.com/junjapp/codex-more-agents-fix/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-black)](#requirements)
[![Language: English + 中文](https://img.shields.io/badge/Docs-English%20%2B%20%E4%B8%AD%E6%96%87-blue)](README.zh-CN.md)

A safe, archive-only macOS utility that helps Codex create more agents again by cleaning up stale subagent threads.

Chinese version: [README.zh-CN.md](README.zh-CN.md)

## The Problem It Fixes

Sometimes Codex starts creating too few agents for bigger tasks.

A common reason is stale subagent buildup inside the local Codex state database.

This tool is for users who want to:

- help Codex create more agents again
- reduce stale subagent buildup safely
- preview changes before writing anything
- avoid risky direct deletion of internal Codex rows

## Quick Start

1. Open the latest [Releases](https://github.com/junjapp/codex-more-agents-fix/releases).
2. Download the repository source archive.
3. Open the folder and double-click `bin/codex-more-agents-fix.command`.
4. Start with `Safe Preview`.
5. If the candidate list looks correct, run `Standard Cleanup`.

## What It Does

This project provides a double-clickable `.command` tool that:

- discovers the active Codex thread state database from `~/.codex`
- shows read-only audits and dry runs first
- archives stale subagent threads instead of deleting internal records
- blocks write actions while the Codex app is running
- creates a database backup before every write action

## Why It Is Archive-Only

Codex uses internal SQLite state with multiple related tables. This project deliberately avoids direct row deletion and database compaction because those operations are not publicly documented as stable or safe for end users.

This tool only performs reversible thread archiving.

## Safety Model

- Read-only modes are safe to run anytime.
- Write modes require the Codex app to be fully closed first.
- The tool never deletes internal Codex state rows.
- The tool never runs `VACUUM`.
- A backup is created before each write action.

## Included Tool

- `bin/codex-more-agents-fix.command`

## Cleanup Levels

- `State DB Audit`: inspect the detected Codex state database and current thread counts.
- `Safe Preview`: simulate candidate matches without writing changes.
- `Light Cleanup`: archive stale subagents older than 24 hours.
- `Standard Cleanup`: archive stale subagents older than 6 hours.
- `Deep Cleanup`: archive stale subagents older than 1 hour.
- `Main-Thread Cleanup`: archive stale subagents older than 1 hour and stale main threads older than 7 days.
- `Custom Cleanup`: set your own thresholds, preview first, then execute.

## Requirements

- macOS
- Codex desktop app or a Codex state directory present at `~/.codex`
- `zsh`
- system Python 3
- `rg` installed and available in `PATH`

## Scope

This repository contains only the standalone cleanup tool and its bilingual documentation.
It does not include unrelated research files, project-specific configs, or private workspace context.

## License

MIT
