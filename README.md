# Codex Subagent Cleaner

A safe, archive-only cleanup tool for Codex stale subagent threads on macOS.

Chinese version: [README.zh-CN.md](README.zh-CN.md)

## What It Does

This project provides a double-clickable `.command` tool that helps reduce stale subagent buildup in Codex by:

- discovering the active Codex thread state database from `~/.codex`
- showing read-only audits and dry runs first
- archiving stale subagent threads instead of deleting internal records
- blocking write actions while the Codex app is running
- creating a database backup before every write action

## Why It Is Archive-Only

Codex uses internal SQLite state that may contain multiple related tables. This project deliberately avoids direct row deletion and database compaction because those operations are not publicly documented as stable or safe for end users.

This tool only performs reversible thread archiving.

## Safety Model

- Read-only modes are always safe to run.
- Write modes require the Codex app to be fully closed first.
- The tool never deletes internal Codex state rows.
- The tool never runs `VACUUM`.
- A backup is created before each write action.

## Included Tool

- `bin/codex-subagent-cleaner.command`

## Usage

1. Download this repository.
2. Double-click `bin/codex-subagent-cleaner.command`.
3. Start with `Safe Preview`.
4. If the candidate list looks correct, move to `Standard Cleanup`.

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
- Codex desktop app or Codex state directory present at `~/.codex`
- `zsh`
- system Python 3
- `rg` installed and available in `PATH`

## Scope

This repository contains only the standalone cleanup tool and its documentation.
It does not include unrelated research files, project-specific configs, or private workspace context.

## License

MIT
