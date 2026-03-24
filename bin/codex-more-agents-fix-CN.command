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

function term_width() {
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

function rule() {
  local width
  width="$(term_width)"
  printf '%*s\n' "$width" '' | tr ' ' '-'
}

function wrap_text() {
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

function use_color() {
  [[ -t 1 && "${TERM:-}" != "dumb" ]]
}

function color_text() {
  local color="$1"
  local text="$2"
  if use_color; then
    printf '\033[%sm%s\033[0m' "$color" "$text"
  else
    printf '%s' "$text"
  fi
}

function level_color() {
  local level="$1"
  case "$level" in
    read) echo "36" ;;
    low) echo "32" ;;
    medium) echo "33" ;;
    high) echo "31" ;;
    *) echo "0" ;;
  esac
}

function risk_text() {
  local level="$1"
  case "$level" in
    read) echo "只读" ;;
    low) echo "低风险" ;;
    medium) echo "中风险" ;;
    high) echo "高风险" ;;
    *) echo "未定义" ;;
  esac
}

function clear_screen() {
  printf '\033c'
}

function wait_return() {
  echo ""
  wrap_text 0 "空格键返回当前目录，0 返回上一级，q 退出。"
  while true; do
    read -k 1 key
    case "$key" in
      " ")
        return 0
        ;;
      "0")
        return 10
        ;;
      "q"|"Q")
        exit 0
        ;;
    esac
  done
}

function codex_app_running() {
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

function discover_state_db() {
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
    wrap_text 0 "未发现可用的 Codex 线程状态库。脚本只会扫描 ~/.codex 和 ~/.codex/sqlite，并优先识别包含 threads 表的数据库，而不是锁死某个文件名。"
    echo ""
    rule
    read -k 1 "?按任意键退出..."
    exit 1
  fi
}

function print_header() {
  clear_screen
  local app_state="未检测到"
  if codex_app_running; then
    app_state="正在运行"
  fi
  wrap_text 0 "Codex 全局 Subagent 软清理工具"
  wrap_text 0 "设计目标：只做可逆、保守、可解释的线程归档，不直接删除内部状态记录，尽量避免引发 Codex app 状态库错误。"
  rule
  wrap_text 0 "Codex 目录：$CODEX_HOME"
  wrap_text 0 "当前状态库：$STATE_DB_PATH"
  wrap_text 0 "Codex app 状态：$app_state"
  if codex_app_running; then
    wrap_text 0 "写入型操作将被阻止。请先完全退出 Codex app，再执行任何清理。只读审计和预演不受影响。"
  fi
  rule
}

function main_option_title() {
  local key="$1"
  case "$key" in
    1) echo "状态库审计" ;;
    2) echo "安全预演" ;;
    3) echo "轻度清理" ;;
    4) echo "标准清理" ;;
    5) echo "深度清理" ;;
    6) echo "主线程介入清理" ;;
    7) echo "自定义清理" ;;
    *) echo "" ;;
  esac
}

function main_option_level() {
  local key="$1"
  case "$key" in
    1|2) echo "read" ;;
    3) echo "low" ;;
    4|5) echo "medium" ;;
    6|7) echo "high" ;;
    *) echo "read" ;;
  esac
}

function main_option_summary() {
  local key="$1"
  case "$key" in
    1) echo "检查全局状态库发现结果、活跃线程和归档线程分布，只读。" ;;
    2) echo "模拟不同清理动作会命中哪些线程，不写数据库。" ;;
    3) echo "归档 24 小时以上 stale subagents，适合第一次轻量释放容量。" ;;
    4) echo "归档 6 小时以上 stale subagents，适合常规整理。" ;;
    5) echo "归档 1 小时以上 stale subagents，适合 cluster 容量明显紧张时使用。" ;;
    6) echo "在深度清理基础上，再归档 7 天以上 stale 主线程，风险最高。" ;;
    7) echo "按你的阈值定制预演或执行，适合高级使用。" ;;
    *) echo "" ;;
  esac
}

function main_option_details() {
  local key="$1"
  case "$key" in
    1)
      echo "功能：扫描 ~/.codex 与 ~/.codex/sqlite 下的数据库文件，按表结构识别真正的线程状态库，并展示当前活跃主线程、活跃 subagents、已归档线程等概况。用途：先判断问题是否真的来自 stale subagents 堆积。风险提示：[只读] 不写入数据库，不会改变 Codex 状态。"
      ;;
    2)
      echo "功能：基于当前阈值做候选预览，显示哪些活跃 subagents 或主线程会被归档，但不会真正写入。用途：执行前先确认命中范围是否合理。风险提示：[只读] 不写入数据库，不会改变 Codex 状态。"
      ;;
    3)
      echo "功能：仅归档 24 小时以上未更新的活跃 subagents，不触碰主线程，不删除任何数据库记录。用途：保守释放一部分 cluster 容量，适合先试效果。风险提示：[低风险] 只做可逆归档；执行前必须关闭 Codex app。"
      ;;
    4)
      echo "功能：仅归档 6 小时以上未更新的活跃 subagents，不触碰主线程，不删除任何数据库记录。用途：作为日常常规整理，释放较明显的 stale subagent 占用。风险提示：[中风险] 命中范围比轻度更大，但仍只做可逆归档；执行前必须关闭 Codex app。"
      ;;
    5)
      echo "功能：仅归档 1 小时以上未更新的活跃 subagents，不触碰主线程，不删除任何数据库记录。用途：在主 Agent 开 cluster 明显偏保守时，快速回收 stale subagent 占用。风险提示：[中风险] 可能归档较新的 subagents；执行前必须关闭 Codex app。"
      ;;
    6)
      echo "功能：先按深度清理归档 stale subagents，再额外归档 7 天以上未更新的主线程。用途：当历史主线程本身也堆积且你确认很久不再使用时才考虑。风险提示：[高风险] 会影响主线程可见性；仍不删除任何记录，但执行前必须关闭 Codex app。"
      ;;
    7)
      echo "功能：可手动设置 stale subagent 阈值、是否包含主线程及主线程阈值，并先预演后执行。用途：适合反复调参。风险提示：[高风险] 风险取决于你设定的阈值；脚本仍只做归档，不做删除。"
      ;;
    *)
      echo ""
      ;;
  esac
}

function custom_option_title() {
  local key="$1"
  case "$key" in
    1) echo "设置 stale subagent 阈值" ;;
    2) echo "切换是否包含主线程" ;;
    3) echo "设置 stale 主线程阈值" ;;
    4) echo "预演当前参数" ;;
    5) echo "正式执行当前参数" ;;
    6) echo "返回上一级" ;;
    *) echo "" ;;
  esac
}

function custom_option_level() {
  local key="$1"
  case "$key" in
    1|2|3|4|6) echo "read" ;;
    5) echo "high" ;;
    *) echo "read" ;;
  esac
}

function custom_option_summary() {
  local key="$1"
  case "$key" in
    1) echo "修改 subagent 的 stale 判断阈值。" ;;
    2) echo "决定是否让主线程进入候选范围。" ;;
    3) echo "仅在包含主线程时生效。" ;;
    4) echo "先看命中结果，不写数据库。" ;;
    5) echo "按当前参数执行归档写入。" ;;
    6) echo "不保存额外状态，直接回主菜单。" ;;
    *) echo "" ;;
  esac
}

function custom_option_details() {
  local key="$1"
  case "$key" in
    1)
      echo "功能：设置 subagent 被视为 stale 的时间阈值。用途：阈值越小，命中的活跃 subagents 越多。风险提示：[只读] 当前步骤本身不写库，但会影响后续执行范围。"
      ;;
    2)
      echo "功能：切换是否让主线程也参与候选归档。用途：默认建议关闭，只在你明确确认历史主线程也造成干扰时才打开。风险提示：[只读] 当前步骤本身不写库，但会显著影响后续执行范围。"
      ;;
    3)
      echo "功能：设置主线程 stale 阈值。用途：只有在已开启主线程参与时才会生效。风险提示：[只读] 当前步骤本身不写库，但阈值过小会让更多主线程进入候选。"
      ;;
    4)
      echo "功能：按当前参数做预演，显示会命中的线程清单。用途：正式执行前做最后确认。风险提示：[只读] 不写库。"
      ;;
    5)
      echo "功能：按当前参数执行归档。用途：将候选线程从活跃状态改为已归档。风险提示：[高风险] 仍然不做删除，但会真正写库；执行前必须关闭 Codex app。"
      ;;
    6)
      echo "功能：返回主菜单。用途：放弃当前自定义调整。风险提示：[只读] 不写库。"
      ;;
    *)
      echo ""
      ;;
  esac
}

function option_title_for() {
  local context="$1"
  local key="$2"
  if [[ "$context" == "custom" ]]; then
    custom_option_title "$key"
  else
    main_option_title "$key"
  fi
}

function option_level_for() {
  local context="$1"
  local key="$2"
  if [[ "$context" == "custom" ]]; then
    custom_option_level "$key"
  else
    main_option_level "$key"
  fi
}

function option_summary_for() {
  local context="$1"
  local key="$2"
  if [[ "$context" == "custom" ]]; then
    custom_option_summary "$key"
  else
    main_option_summary "$key"
  fi
}

function option_details_for() {
  local context="$1"
  local key="$2"
  if [[ "$context" == "custom" ]]; then
    custom_option_details "$key"
  else
    main_option_details "$key"
  fi
}

function menu_choice() {
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
      local level label summary line risk
      level="$(option_level_for "$context" "$i")"
      label="$(option_title_for "$context" "$i")"
      summary="$(option_summary_for "$context" "$i")"
      risk="$(risk_text "$level")"
      line="[$i] $label | $summary | 风险提示：[$risk]"
      if [[ "$i" -eq "$selected" ]]; then
        printf ' > %s\n' "$(color_text "$(level_color "$level")" "$line")"
      else
        printf '   %s\n' "$(color_text "$(level_color "$level")" "$line")"
      fi
      ((i++))
    done
    echo ""
    rule
    wrap_text 0 "当前选项详细说明："
    wrap_text 2 "$(option_details_for "$context" "$selected")"
    rule
    wrap_text 0 "操作提示：方向键上下移动，回车确认，也可以直接输入数字。输入 0 返回上一级，q 退出。"

    read -rs -k 1 key
    if [[ "$key" == $'\e' ]]; then
      read -rs -k 2 rest || true
      case "$rest" in
        "[A")
          ((selected--))
          if [[ "$selected" -lt 1 ]]; then
            selected="$count"
          fi
          ;;
        "[B")
          ((selected++))
          if [[ "$selected" -gt "$count" ]]; then
            selected=1
          fi
          ;;
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

function ask_seconds() {
  local title="$1"
  local hint="$2"
  local default_value="$3"
  while true; do
    print_header
    wrap_text 0 "$title"
    echo ""
    wrap_text 0 "$hint"
    wrap_text 0 "直接输入秒数，回车确认。输入 0 返回上一级。"
    echo ""
    printf "默认值 [%s]：" "$default_value"
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

function require_closed_codex_for_write() {
  if codex_app_running; then
    print_header
    wrap_text 0 "为了尽量避免写库冲突和 Codex app 状态异常，脚本不允许在 Codex app 运行时执行写入型清理。请先完全退出 Codex app，再重新打开脚本执行。"
    rule
    wait_return || true
    return 1
  fi
  return 0
}

function run_python() {
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
  wrap_text 0 "准备执行："
  wrap_text 2 "模式：$mode"
  wrap_text 2 "stale subagent 阈值：$subagent_max_age_seconds 秒"
  wrap_text 2 "是否包含 stale 主线程：$include_main"
  if [[ "$include_main" == "1" ]]; then
    wrap_text 2 "stale 主线程阈值：$main_max_age_seconds 秒"
  fi
  wrap_text 2 "预览数量上限：$preview_limit"
  echo ""
  wrap_text 0 "执行过程透明展示如下："
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

print("[1/4] 当前概况")
print(f"      活跃总线程: {active_total_before}")
print(f"      活跃主线程: {active_main_before}")
print(f"      活跃 subagents: {active_sub_before}")
print(f"      已归档总线程: {archived_total_before}")
print(f"      已归档 subagents: {archived_sub_before}")
print(f"      stale subagent 候选: {len(stale_subagents)}")
if include_main and main_cutoff is not None:
    print(f"      stale 主线程候选: {len(stale_mains)}")

print("[2/4] 待归档候选预览")
preview_rows = stale_subagents + stale_mains
if not preview_rows:
    print("      无")
else:
    for row in preview_rows[:preview_limit]:
        thread_id, role, title, updated_at = row
        title = (title or "").replace("\n", " ")[:120]
        print(f"      - {thread_id} | {role} | updated_at={updated_at} | {title}")
    if len(preview_rows) > preview_limit:
        print(f"      ... 其余 {len(preview_rows) - preview_limit} 条未展开")

print("[3/4] 已归档 subagent 观察样本")
if not old_archived_subagents:
    print("      当前没有已归档 subagent 样本。")
else:
    for row in old_archived_subagents:
        thread_id, role, title, archived_ref = row
        title = (title or "").replace("\n", " ")[:120]
        print(f"      - {thread_id} | {role} | archived_ref={archived_ref} | {title}")

conn.close()

if mode != "execute":
    print("[4/4] 预演结束：未写入任何变更。")
    raise SystemExit(0)

backup_path = backup_dir / f"{db_path.name}.{backup_stamp}.bak"
source_conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
dest_conn = sqlite3.connect(str(backup_path))
source_conn.backup(dest_conn)
dest_conn.close()
source_conn.close()
print(f"[4/4] 已创建数据库备份：{backup_path}")

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

    print("[4/4] 正式执行完成")
    print(f"      已归档线程: {len(archive_targets)}")
    print(f"      活跃总线程: {active_total_before} -> {active_total_after}")
    print(f"      活跃主线程: {active_main_before} -> {active_main_after}")
    print(f"      活跃 subagents: {active_sub_before} -> {active_sub_after}")
    print(f"      已归档总线程: {archived_total_before} -> {archived_total_after}")
    print(f"      已归档 subagents: {archived_sub_before} -> {archived_sub_after}")
    write_conn.close()
except sqlite3.OperationalError as exc:
    print("[4/4] 写入失败")
    print(f"      SQLite 返回：{exc}")
    print("      建议：确认 Codex app 已完全退出后再重试。")
    raise SystemExit(1)
PY
}

function show_db_discovery() {
  print_header
  "$PYTHON_BIN" - "$DISCOVERY_CACHE" <<'PY'
import json
import sys
from pathlib import Path

cache_path = Path(sys.argv[1])
if not cache_path.exists():
    print("尚未生成状态库发现缓存。")
    raise SystemExit(0)

data = json.loads(cache_path.read_text(encoding="utf-8"))
selected = data.get("selected")
print("状态库候选审计")
print("")
print(f"最终选中：{selected}")
print("")
for item in data.get("candidates", []):
    path = item.get("path")
    score = item.get("score")
    tables = ",".join(item.get("tables", [])[:12])
    error = item.get("error")
    marker = "*" if path == selected else " "
    print(f"{marker} 路径：{path}")
    print(f"  分数：{score}")
    if error:
        print(f"  错误：{error}")
    else:
        print(f"  表：{tables}")
    print("")
PY
}

function custom_menu() {
  local subagent_seconds=3600
  local include_main=0
  local main_seconds=604800

  while true; do
    menu_choice \
      "自定义清理参数。脚本仍然只做归档，不做删除；所有写入都要求 Codex app 已完全退出。" \
      "custom" \
      6
    local choice="$MENU_CHOICE_RESULT"

    case "$choice" in
      "0"|"6")
        return 0
        ;;
      "q")
        exit 0
        ;;
      "1")
        ask_seconds "设置 stale subagent 阈值" "示例：3600=1小时，21600=6小时，86400=1天。" "$subagent_seconds"
        local value="$ASK_SECONDS_RESULT"
        [[ "$value" == "0" ]] || subagent_seconds="$value"
        ;;
      "2")
        if [[ "$include_main" == "0" ]]; then
          include_main=1
        else
          include_main=0
        fi
        ;;
      "3")
        ask_seconds "设置 stale 主线程阈值" "示例：86400=1天，604800=7天。建议阈值不要太小。" "$main_seconds"
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

function main_menu() {
  while true; do
    menu_choice \
      "请选择要执行的全局清理等级。排序从浅到深；颜色也从冷到暖，再到红色，表示介入深度和风险级别逐步上升。" \
      "main" \
      7
    local choice="$MENU_CHOICE_RESULT"

    case "$choice" in
      "0")
        exit 0
        ;;
      "q")
        exit 0
        ;;
      "1")
        show_db_discovery
        wait_return || true
        ;;
      "2")
        run_python "dry-run" 3600 0 0 30
        wait_return || true
        ;;
      "3")
        run_python "execute" 86400 0 0 30
        wait_return || true
        ;;
      "4")
        run_python "execute" 21600 0 0 30
        wait_return || true
        ;;
      "5")
        run_python "execute" 3600 0 0 30
        wait_return || true
        ;;
      "6")
        run_python "execute" 3600 1 604800 30
        wait_return || true
        ;;
      "7")
        custom_menu
        ;;
    esac
  done
}

cd "$HOME"
discover_state_db
main_menu
