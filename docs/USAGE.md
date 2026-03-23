# How to Use Codex More Agents Fix

## Who This Is For

Use this tool if Codex used to create multiple helper agents for larger tasks, but now it often creates too few.

## What This Tool Changes

This tool does not delete internal Codex records.
It only archives stale subagent threads so Codex has fewer stale active threads competing for local state.

## Before You Start

Make sure:

- you are on macOS
- Codex has been used on this Mac before
- the Codex app is fully closed before you run any write cleanup

## The Safest Way To Use It

1. Double-click `bin/codex-more-agents-fix.command`.
2. Choose `Safe Preview` first.
3. Review the candidate list.
4. If the result looks correct, run `Standard Cleanup`.
5. Open Codex again and test whether it now creates more agents for a larger task.

## What The Cleanup Levels Mean

### State DB Audit
Use this when you want to inspect the detected database and current thread counts without changing anything.

### Safe Preview
Use this when you want to see what would be archived before making any changes.

### Light Cleanup
Archives stale subagents older than 24 hours.
Choose this if you want the most conservative write mode.

### Standard Cleanup
Archives stale subagents older than 6 hours.
Choose this for routine cleanup.

### Deep Cleanup
Archives stale subagents older than 1 hour.
Choose this when Codex is clearly creating too few helper agents.

### Main-Thread Cleanup
Also archives stale main threads older than 7 days.
Only use this if you understand that some older main conversations may move into archived state.

### Custom Cleanup
Lets you choose your own thresholds.
Use this only if the built-in levels do not match your needs.

## Safety Notes

- Read-only modes are always safer than write modes.
- The tool blocks write actions if the Codex app is still running.
- A backup is created before every write action.
- This project intentionally avoids deleting internal rows and avoids running `VACUUM`.

## If You Want To Undo A Cleanup

This tool creates a backup before each write action.
If you need to inspect or restore from a backup, use the backup copy created in your local Codex backup directory.

## What To Expect After Cleanup

You are not guaranteed a specific number of agents.
The goal is to reduce stale local state pressure so Codex can make better decisions about spawning helper agents again.
