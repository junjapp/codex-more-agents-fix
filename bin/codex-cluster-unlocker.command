#!/bin/zsh
set -euo pipefail
setopt typesetsilent

export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
PYTHON_BIN="${PYTHON_BIN:-/usr/bin/python3}"
TMP_DIR="$CODEX_HOME/tmp"
BACKUP_DIR="$CODEX_HOME/backups"
DISCOVERY_CACHE="$TMP_DIR/codex-state-db-discovery.json"

mkdir -p "$TMP_DIR" "$BACKUP_DIR"

STATE_DB_PATH=""
MENU_CHOICE_RESULT=""
ASK_SECONDS_RESULT=""

term_width() {
  local cols
  cols="$(tput cols 2>/dev/null || true)"
  if [[ -z "$cols" || ! "$cols" =~ ^[0-9]+$ ]]; then
    cols=100
  fi
  if (( cols < 72 )); then
    cols=72
  fi
  if (( cols > 140 )); then
    cols=140
  fi
  echo "$cols"
}

rule() {
  local width
  width="$(term_width)"
  printf '%*s\n' "$width" '' | tr ' ' '-'
}

wrap_text() {
  local indent="${1:-0}"
  local text="${2:-}"
  local width
  width="$(term_width)"
  "$PYTHON_BIN" - "$width" "$indent" "$text" <<'PY'
import sys
import textwrap

width = int(sys.argv[1])
indent = int(sys.argv[2])
text = sys.argv[3]
prefix = " " * indent
wrap_width = max(20, width - indent)
print(textwrap.fill(text, width=wrap_width, initial_indent=prefix, subsequent_indent=prefix))
PY
}

use_color() {
  [[ -t 1 && "${TERM:-}" != "dumb" ]]
}

color_text() {
  local color="$1"
  local text="$2"
  if use_color; then
    printf '\033[%sm%s\033[0m' "$color" "$text"
  else
    printf '%s' "$text"
  fi
}

level_color() {
  local level="$1"
  case "$level" in
    read) echo "36" ;;
    low) echo "32" ;;
    medium) echo "33" ;;
    high) echo "31" ;;
    *) echo "0" ;;
  esac
}

risk_text() {
  local level="$1"
  case "$level" in
    read) echo "Read-only" ;;
    low) echo "Low" ;;
    medium) echo "Medium" ;;
    high) echo "High" ;;
    *) echo "Undefined" ;;
  esac
}

clear_screen() {
  printf '\033c'
}

wait_return() {
  echo ""
  wrap_text 0 "Press Space to return to the current menu, 0 to go back, or q to quit."
  while true; do
    read -k 1 key
    case "$key" in
      " ") return 0 ;;
      "0") return 10 ;;
      "q"|"Q") exit 0 ;;
    esac
  done
}

codex_app_running() {
  local ps_output
  ps_output="$(ps -axo command= 2>/dev/null || true)"
  if [[ -z "$ps_output" ]]; then
    return 1
  fi
  if print -r -- "$ps_output" | rg -i -q '/Codex\.app/|(^|[[:space:]/])Codex([[:space:]]|$)' ; then
    return 0
  fi
  return 1
}

discover_state_db() {
  local result
  result="$("$PYTHON_BIN" - "$CODEX_HOME" "$DISCOVERY_CACHE" <<'PY'
import json
import sqlite3
import sys
from pathlib import Path

codex_home = Path(sys.argv[1]).expanduser()
cache_path = Path(sys.argv[2]).expanduser()

candidate_dirs = [codex_home, codex_home / "sqlite"]
seen = set()
files = []
for base in candidate_dirs:
    if not base.exists():
        continue
    for path in sorted(base.iterdir()):
        if not path.is_file():
            continue
        if path.suffix not in {".sqlite", ".db"}:
            continue
        resolved = str(path.resolve())
        if resolved in seen:
            continue
        seen.add(resolved)
        files.append(path)

results = []
for path in files:
    item = {
        "path": str(path),
        "tables": [],
        "score": 0,
        "error": None,
        "mtime": int(path.stat().st_mtime),
    }
    try:
        conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        tables = [row[0] for row in cur.fetchall()]
        item["tables"] = tables
        score = 0
        if "threads" in tables:
            score += 100
        if "thread_dynamic_tools" in tables:
            score += 25
        if "stage1_outputs" in tables:
            score += 10
        if "logs" in tables:
            score += 5
        item["score"] = score
        conn.close()
    except Exception as exc:
        item["error"] = str(exc)
    results.append(item)

results.sort(key=lambda x: (x["score"], x["mtime"]), reverse=True)
selected = next((r for r in results if r["score"] >= 100), None)

cache_path.parent.mkdir(parents=True, exist_ok=True)
cache_path.write_text(
    json.dumps(
        {
            "selected": selected["path"] if selected else None,
            "candidates": results,
        },
        ensure_ascii=False,
        indent=2,
    ),
    encoding="utf-8",
)

print(selected["path"] if selected else "")
PY
)"

  STATE_DB_PATH="$result"
  if [[ -z "$STATE_DB_PATH" || ! -f "$STATE_DB_PATH" ]]; then
    clear_screen
    wrap_text 0 "No usable Codex thread state database was found. The tool scans ~/.codex and ~/.codex/sqlite, then prefers databases that contain a threads table instead of assuming a fixed filename."
    echo ""
    rule
    read -k 1 "?Press any key to quit..."
    exit 1
  fi
}

print_header() {
  clear_screen
  local app_state="Not detected"
  if codex_app_running; then
    app_state="Running"
  fi
  wrap_text 0 "Codex Cluster Unlocker"
  wrap_text 0 "Goal: provide conservative, reversible thread archiving without directly deleting internal Codex records."
  rule
  wrap_text 0 "Codex home: $CODEX_HOME"
  wrap_text 0 "Detected state DB: $STATE_DB_PATH"
  wrap_text 0 "Codex app status: $app_state"
  if codex_app_running; then
    wrap_text 0 "Write actions are blocked while the Codex app is running. Close Codex completely before executing cleanup. Read-only audit and preview modes remain available."
  fi
  rule
}

main_option_title() {
  case "$1" in
    1) echo "State DB Audit" ;;
    2) echo "Safe Preview" ;;
    3) echo "Light Cleanup" ;;
    4) echo "Standard Cleanup" ;;
    5) echo "Deep Cleanup" ;;
    6) echo "Main-Thread Cleanup" ;;
    7) echo "Custom Cleanup" ;;
    *) echo "" ;;
  esac
}

main_option_level() {
  case "$1" in
    1|2) echo "read" ;;
    3) echo "low" ;;
    4|5) echo "medium" ;;
    6|7) echo "high" ;;
    *) echo "read" ;;
  esac
}

main_option_summary() {
  case "$1" in
    1) echo "Inspect the detected state database and current thread distribution." ;;
    2) echo "Simulate matches without writing any changes." ;;
    3) echo "Archive stale subagents older than 24 hours." ;;
    4) echo "Archive stale subagents older than 6 hours." ;;
    5) echo "Archive stale subagents older than 1 hour." ;;
    6) echo "Also archive stale main threads older than 7 days." ;;
    7) echo "Define your own thresholds, preview first, then execute." ;;
    *) echo "" ;;
  esac
}

main_option_details() {
  case "$1" in
    1) echo "Purpose: scan ~/.codex and ~/.codex/sqlite, identify the active thread state DB by table signature, and show active versus archived thread counts. Risk note: [Read-only] no database writes." ;;
    2) echo "Purpose: show exactly which threads would be archived under the selected thresholds before any write happens. Risk note: [Read-only] no database writes." ;;
    3) echo "Purpose: archive only stale subagents older than 24 hours. Good for first-pass cleanup when you want a conservative release of cluster capacity. Risk note: [Low] reversible archive only; Codex must be closed before execution." ;;
    4) echo "Purpose: archive only stale subagents older than 6 hours. Good for routine cleanup. Risk note: [Medium] larger candidate set than light cleanup; still archive-only and reversible." ;;
    5) echo "Purpose: archive stale subagents older than 1 hour. Good when cluster creation is clearly too conservative. Risk note: [Medium] more aggressive candidate matching; still archive-only and reversible." ;;
    6) echo "Purpose: extend deep cleanup to stale main threads older than 7 days. Risk note: [High] can affect main-thread visibility; still archive-only and reversible." ;;
    7) echo "Purpose: configure thresholds yourself, then preview and execute. Risk note: [High] actual risk depends on your thresholds; the tool still archives only and never deletes rows." ;;
    *) echo "" ;;
  esac
}

custom_option_title() {
  case "$1" in
    1) echo "Set stale subagent threshold" ;;
    2) echo "Toggle main-thread scope" ;;
    3) echo "Set stale main-thread threshold" ;;
    4) echo "Preview current settings" ;;
    5) echo "Execute current settings" ;;
    6) echo "Back" ;;
    *) echo "" ;;
  esac
}

custom_option_level() {
  case "$1" in
    1|2|3|4|6) echo "read" ;;
    5) echo "high" ;;
    *) echo "read" ;;
  esac
}

custom_option_summary() {
  case "$1" in
    1) echo "Change the stale threshold for subagents." ;;
    2) echo "Decide whether main threads enter the candidate scope." ;;
    3) echo "Only applies when main-thread scope is enabled." ;;
    4) echo "Preview the current settings without writing." ;;
    5) echo "Run cleanup using the current settings." ;;
    6) echo "Return to the main menu." ;;
    *) echo "" ;;
  esac
}

custom_option_details() {
  case "$1" in
    1) echo "Purpose: define when a subagent is considered stale. Lower thresholds match more threads. Risk note: [Read-only] this step does not write, but it changes later execution scope." ;;
    2) echo "Purpose: decide whether stale main threads can be archived too. Risk note: [Read-only] this step does not write, but it can greatly expand later execution scope." ;;
    3) echo "Purpose: define when a main thread is considered stale. Risk note: [Read-only] this step does not write, but an overly small threshold may target more main threads than intended." ;;
    4) echo "Purpose: inspect exact matches before a real write. Risk note: [Read-only] no database writes." ;;
    5) echo "Purpose: archive candidates using the current settings. Risk note: [High] this writes to the state DB, though it remains archive-only and reversible." ;;
    6) echo "Purpose: leave custom mode and return to the main menu. Risk note: [Read-only] no database writes." ;;
    *) echo "" ;;
  esac
}

option_title_for() {
  if [[ "$1" == "custom" ]]; then
    custom_option_title "$2"
  else
    main_option_title "$2"
  fi
}

option_level_for() {
  if [[ "$1" == "custom" ]]; then
    custom_option_level "$2"
  else
    main_option_level "$2"
  fi
}

option_summary_for() {
  if [[ "$1" == "custom" ]]; then
    custom_option_summary "$2"
  else
    main_option_summary "$2"
  fi
}

option_details_for() {
  if [[ "$1" == "custom" ]]; then
    custom_option_details "$2"
  else
    main_option_details "$2"
  fi
}

menu_choice() {
  local prompt="$1"
  local context="$2"
  local count="$3"
  local selected=1

  while true; do
    print_header
    wrap_text 0 "$prompt"
    echo ""
    local i=1
    while [[ "$i" -le "$count" ]]; do
      local level="" label="" summary="" line="" risk=""
      level="$(option_level_for "$context" "$i")"
      label="$(option_title_for "$context" "$i")"
      summary="$(option_summary_for "$context" "$i")"
      risk="$(risk_text "$level")"
      line="[$i] $label | $summary | Risk note: [$risk]"
      if [[ "$i" -eq "$selected" ]]; then
        printf ' > %s\n' "$(color_text "$(level_color "$level")" "$line")"
      else
        printf '   %s\n' "$(color_text "$(level_color "$level")" "$line")"
      fi
      ((i++))
    done
    echo ""
    rule
    wrap_text 0 "Current option details:"
    wrap_text 2 "$(option_details_for "$context" "$selected")"
    rule
    wrap_text 0 "Controls: Up and Down arrows to move, Enter to confirm, direct number input also works. Press 0 to go back or q to quit."

    read -rs -k 1 key
    if [[ "$key" == $'\e' ]]; then
      read -rs -k 2 rest || true
      case "$rest" in
        "[A") ((selected--)); if [[ "$selected" -lt 1 ]]; then selected="$count"; fi ;;
        "[B") ((selected++)); if [[ "$selected" -gt "$count" ]]; then selected=1; fi ;;
      esac
    elif [[ "$key" == "" || "$key" == $'\n' || "$key" == $'\r' ]]; then
      MENU_CHOICE_RESULT="$selected"
      return 0
    elif [[ "$key" == "0" ]]; then
      MENU_CHOICE_RESULT="0"
      return 0
    elif [[ "$key" == "q" || "$key" == "Q" ]]; then
      MENU_CHOICE_RESULT="q"
      return 0
    elif [[ "$key" == <-> ]]; then
      local number="$key"
      read -t 0.15 -rs -k 1 next || true
      while [[ -n "${next:-}" && "$next" == <-> ]]; do
        number+="$next"
        read -t 0.15 -rs -k 1 next || true
      done
      if [[ "$number" -ge 0 && "$number" -le "$count" ]]; then
        MENU_CHOICE_RESULT="$number"
        return 0
      fi
    fi
  done
}

ask_seconds() {
  local title="$1"
  local hint="$2"
  local default_value="$3"
  while true; do
    print_header
    wrap_text 0 "$title"
    echo ""
    wrap_text 0 "$hint"
    wrap_text 0 "Enter the value in seconds and press Enter. Press 0 to go back."
    echo ""
    printf 'Default [%s]: ' "$default_value"
    read -r value
    value="${value:-$default_value}"
    if [[ "$value" == "0" ]]; then
      ASK_SECONDS_RESULT="0"
      return 0
    fi
    if [[ "$value" =~ ^[0-9]+$ ]]; then
      ASK_SECONDS_RESULT="$value"
      return 0
    fi
  done
}

require_closed_codex_for_write() {
  if codex_app_running; then
    print_header
    wrap_text 0 "To reduce the chance of write conflicts or state corruption, this tool blocks write actions while the Codex app is running. Close Codex completely, then reopen the tool and try again."
    rule
    wait_return || true
    return 1
  fi
  return 0
}

run_python() {
  local mode="$1"
  local subagent_max_age_seconds="$2"
  local include_main="$3"
  local main_max_age_seconds="$4"
  local preview_limit="$5"
  local backup_stamp
  backup_stamp="$(date +%Y%m%d-%H%M%S)"

  if [[ "$mode" == "execute" ]]; then
    require_closed_codex_for_write || return 0
  fi

  print_header
  wrap_text 0 "Execution summary:"
  wrap_text 2 "Mode: $mode"
  wrap_text 2 "Stale subagent threshold: $subagent_max_age_seconds seconds"
  wrap_text 2 "Include stale main threads: $include_main"
  if [[ "$include_main" == "1" ]]; then
    wrap_text 2 "Stale main-thread threshold: $main_max_age_seconds seconds"
  fi
  wrap_text 2 "Preview limit: $preview_limit"
  echo ""
  wrap_text 0 "Transparent execution output:"
  echo ""

  "$PYTHON_BIN" - "$STATE_DB_PATH" "$BACKUP_DIR" "$backup_stamp" "$mode" "$subagent_max_age_seconds" "$include_main" "$main_max_age_seconds" "$preview_limit" <<'PY'
import sqlite3
import sys
import time
from pathlib import Path

db_path = Path(sys.argv[1])
backup_dir = Path(sys.argv[2])
backup_stamp = sys.argv[3]
mode = sys.argv[4]
subagent_max_age_seconds = int(sys.argv[5])
include_main = sys.argv[6] == "1"
main_max_age_seconds = int(sys.argv[7])
preview_limit = int(sys.argv[8])

backup_dir.mkdir(parents=True, exist_ok=True)

now = int(time.time())
subagent_cutoff = now - subagent_max_age_seconds
main_cutoff = now - main_max_age_seconds if include_main and main_max_age_seconds > 0 else None

conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
cur = conn.cursor()

def scalar(sql, params=()):
    cur.execute(sql, params)
    return cur.fetchone()[0]

def rows(sql, params=()):
    cur.execute(sql, params)
    return cur.fetchall()

active_total_before = scalar("SELECT COUNT(*) FROM threads WHERE archived = 0")
active_main_before = scalar("SELECT COUNT(*) FROM threads WHERE archived = 0 AND agent_role IS NULL")
active_sub_before = scalar("SELECT COUNT(*) FROM threads WHERE archived = 0 AND agent_role IS NOT NULL")
archived_total_before = scalar("SELECT COUNT(*) FROM threads WHERE archived = 1")
archived_sub_before = scalar("SELECT COUNT(*) FROM threads WHERE archived = 1 AND agent_role IS NOT NULL")

stale_subagents = rows(
    """
    SELECT id, COALESCE(agent_role, 'MAIN'), title, updated_at
    FROM threads
    WHERE archived = 0
      AND agent_role IS NOT NULL
      AND updated_at < ?
    ORDER BY updated_at ASC
    """,
    (subagent_cutoff,),
)

stale_mains = []
if include_main and main_cutoff is not None:
    stale_mains = rows(
        """
        SELECT id, 'MAIN', title, updated_at
        FROM threads
        WHERE archived = 0
          AND agent_role IS NULL
          AND updated_at < ?
        ORDER BY updated_at ASC
        """,
        (main_cutoff,),
    )

old_archived_subagents = rows(
    """
    SELECT id, COALESCE(agent_role, 'MAIN'), title, COALESCE(archived_at, updated_at, created_at)
    FROM threads
    WHERE archived = 1
      AND agent_role IS NOT NULL
    ORDER BY COALESCE(archived_at, updated_at, created_at) ASC
    LIMIT ?
    """,
    (preview_limit,),
)

print("[1/4] Current overview")
print(f"      Active total threads: {active_total_before}")
print(f"      Active main threads: {active_main_before}")
print(f"      Active subagents: {active_sub_before}")
print(f"      Archived total threads: {archived_total_before}")
print(f"      Archived subagents: {archived_sub_before}")
print(f"      Stale subagent candidates: {len(stale_subagents)}")
if include_main and main_cutoff is not None:
    print(f"      Stale main-thread candidates: {len(stale_mains)}")

print("[2/4] Archive candidate preview")
preview_rows = stale_subagents + stale_mains
if not preview_rows:
    print("      None")
else:
    for row in preview_rows[:preview_limit]:
        thread_id, role, title, updated_at = row
        title = (title or "").replace("\n", " ")[:120]
        print(f"      - {thread_id} | {role} | updated_at={updated_at} | {title}")
    if len(preview_rows) > preview_limit:
        print(f"      ... {len(preview_rows) - preview_limit} more rows not shown")

print("[3/4] Archived subagent sample")
if not old_archived_subagents:
    print("      No archived subagent samples found.")
else:
    for row in old_archived_subagents:
        thread_id, role, title, archived_ref = row
        title = (title or "").replace("\n", " ")[:120]
        print(f"      - {thread_id} | {role} | archived_ref={archived_ref} | {title}")

conn.close()

if mode != "execute":
    print("[4/4] Preview complete. No changes were written.")
    raise SystemExit(0)

backup_path = backup_dir / f"{db_path.name}.{backup_stamp}.bak"
source_conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
dest_conn = sqlite3.connect(str(backup_path))
source_conn.backup(dest_conn)
dest_conn.close()
source_conn.close()
print(f"[4/4] Backup created: {backup_path}")

try:
    write_conn = sqlite3.connect(str(db_path), timeout=1)
    write_conn.execute("PRAGMA foreign_keys = ON")
    write_cur = write_conn.cursor()
    write_cur.execute("BEGIN IMMEDIATE")

    archive_targets = [row[0] for row in preview_rows]
    if archive_targets:
        placeholders = ",".join("?" for _ in archive_targets)
        write_cur.execute(
            f"UPDATE threads SET archived = 1, archived_at = ? WHERE id IN ({placeholders})",
            [now, *archive_targets],
        )

    write_conn.commit()

    active_total_after = write_conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 0").fetchone()[0]
    active_main_after = write_conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 0 AND agent_role IS NULL").fetchone()[0]
    active_sub_after = write_conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 0 AND agent_role IS NOT NULL").fetchone()[0]
    archived_total_after = write_conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1").fetchone()[0]
    archived_sub_after = write_conn.execute("SELECT COUNT(*) FROM threads WHERE archived = 1 AND agent_role IS NOT NULL").fetchone()[0]

    print("[4/4] Execution complete")
    print(f"      Archived threads: {len(archive_targets)}")
    print(f"      Active total threads: {active_total_before} -> {active_total_after}")
    print(f"      Active main threads: {active_main_before} -> {active_main_after}")
    print(f"      Active subagents: {active_sub_before} -> {active_sub_after}")
    print(f"      Archived total threads: {archived_total_before} -> {archived_total_after}")
    print(f"      Archived subagents: {archived_sub_before} -> {archived_sub_after}")
    write_conn.close()
except sqlite3.OperationalError as exc:
    print("[4/4] Write failed")
    print(f"      SQLite returned: {exc}")
    print("      Suggestion: make sure the Codex app is fully closed, then retry.")
    raise SystemExit(1)
PY
}

show_db_discovery() {
  print_header
  "$PYTHON_BIN" - "$DISCOVERY_CACHE" <<'PY'
import json
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
if not cache_path.exists():
    print("No discovery cache exists yet.")
    raise SystemExit(0)

data = json.loads(cache_path.read_text(encoding="utf-8"))
selected = data.get("selected")
print("State DB candidate audit")
print("")
print(f"Selected: {selected}")
print("")
for item in data.get("candidates", []):
    path = item.get("path")
    score = item.get("score")
    tables = ",".join(item.get("tables", [])[:12])
    error = item.get("error")
    marker = "*" if path == selected else " "
    print(f"{marker} Path: {path}")
    print(f"  Score: {score}")
    if error:
        print(f"  Error: {error}")
    else:
        print(f"  Tables: {tables}")
    print("")
PY
}

custom_menu() {
  local subagent_seconds=3600
  local include_main=0
  local main_seconds=604800

  while true; do
    menu_choice \
      "Custom cleanup settings. The tool still archives only and never deletes internal rows. All write actions require the Codex app to be fully closed first." \
      "custom" \
      6
    local choice="$MENU_CHOICE_RESULT"

    case "$choice" in
      "0"|"6") return 0 ;;
      "q") exit 0 ;;
      "1")
        ask_seconds "Set stale subagent threshold" "Examples: 3600 = 1 hour, 21600 = 6 hours, 86400 = 1 day." "$subagent_seconds"
        local value="$ASK_SECONDS_RESULT"
        [[ "$value" == "0" ]] || subagent_seconds="$value"
        ;;
      "2")
        if [[ "$include_main" == "0" ]]; then include_main=1; else include_main=0; fi
        ;;
      "3")
        ask_seconds "Set stale main-thread threshold" "Examples: 86400 = 1 day, 604800 = 7 days. Avoid very small values unless you are sure." "$main_seconds"
        local value="$ASK_SECONDS_RESULT"
        [[ "$value" == "0" ]] || main_seconds="$value"
        ;;
      "4")
        run_python "dry-run" "$subagent_seconds" "$include_main" "$main_seconds" 30
        wait_return
        ;;
      "5")
        run_python "execute" "$subagent_seconds" "$include_main" "$main_seconds" 30
        wait_return
        ;;
    esac
  done
}

main_menu() {
  while true; do
    menu_choice \
      "Choose a global cleanup level. The list is ordered from lightest to deepest. Colors also move from cool to warm to red as depth and risk increase." \
      "main" \
      7
    local choice="$MENU_CHOICE_RESULT"

    case "$choice" in
      "0"|"q") exit 0 ;;
      "1") show_db_discovery; wait_return || true ;;
      "2") run_python "dry-run" 3600 0 0 30; wait_return || true ;;
      "3") run_python "execute" 86400 0 0 30; wait_return || true ;;
      "4") run_python "execute" 21600 0 0 30; wait_return || true ;;
      "5") run_python "execute" 3600 0 0 30; wait_return || true ;;
      "6") run_python "execute" 3600 1 604800 30; wait_return || true ;;
      "7") custom_menu ;;
    esac
  done
}

cd "$HOME"
discover_state_db
main_menu
