#!/usr/bin/env bash
# 把某天的日报压成一张飞书卡片，用 bot 身份发到群 / 私聊。
#
#   ./push-feishu.sh                 # 发今天的 reports/$(date +%F).md
#   ./push-feishu.sh 2026-10-20      # 补发某天
#   ./push-feishu.sh --dry-run       # 只生成卡片 JSON 并打印，不发送
#
# 配置（环境变量 > config.env）：
#   FEISHU_AS=bot                    # bot | user
#   FEISHU_RECEIVER_TYPE=user        # user | chat
#   FEISHU_RECEIVER_ID=ou_xxx        # 对应 user 的 open_id 或 chat 的 chat_id
#   REPORT_BASE_URL=https://...      # 报告在 GitHub 上的 blob 目录，留空则不出按钮
set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR" || exit 1

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"

DATE=""; DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -*) echo "未知参数：$arg" >&2; exit 2 ;;
    *) DATE="$arg" ;;
  esac
done
DATE="${DATE:-$(date +%F)}"

REPORT="$PROJECT_DIR/reports/$DATE.md"
LOG="$LOG_DIR/$DATE.log"
log() { printf '[%s] feishu: %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

# 配置：先 config.env，再让真实环境变量覆盖
if [ -r "$PROJECT_DIR/config.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/config.env"
  set +a
fi
FEISHU_AS="${FEISHU_AS:-bot}"
RECEIVER_TYPE="${FEISHU_RECEIVER_TYPE:-user}"
RECEIVER_ID="${FEISHU_RECEIVER_ID:-}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"

[ -f "$REPORT" ] || { echo "找不到报告：$REPORT" >&2; log "跳过：报告不存在"; exit 3; }
[ -n "$RECEIVER_ID" ] || { echo "未配置 FEISHU_RECEIVER_ID（见 config.env.example）" >&2; exit 4; }
command -v lark-cli >/dev/null || { echo "lark-cli 不在 PATH" >&2; exit 5; }

# 拼报告链接：REPORT_BASE_URL 末尾不带斜杠
REPORT_URL=""; THEMES_URL=""
if [ -n "$REPORT_BASE_URL" ]; then
  BASE="${REPORT_BASE_URL%/}"
  REPORT_URL="$BASE/reports/$DATE.md"
  THEMES_URL="$BASE/THEMES.md"
fi

CARD="$(python3 "$PROJECT_DIR/build-card.py" "$REPORT" \
  ${REPORT_URL:+--report-url "$REPORT_URL"} \
  ${THEMES_URL:+--themes-url "$THEMES_URL"} 2>>"$LOG")"
if [ -z "$CARD" ]; then
  echo "卡片生成失败，详见 $LOG" >&2
  log "卡片生成失败"
  exit 6
fi

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$CARD"
  exit 0
fi

case "$RECEIVER_TYPE" in
  user) TARGET=(--user-id "$RECEIVER_ID") ;;
  chat) TARGET=(--chat-id "$RECEIVER_ID") ;;
  *) echo "FEISHU_RECEIVER_TYPE 只能是 user 或 chat" >&2; exit 7 ;;
esac

send_once() {
  lark-cli im +messages-send --as "$FEISHU_AS" "${TARGET[@]}" \
    --msg-type interactive --content "$CARD" --format json 2>>"$LOG"
}

ok=0
for attempt in 1 2; do
  resp="$(send_once)" || true
  if printf '%s' "$resp" | grep -q '"ok": *true'; then
    ok=1
    msg_id="$(printf '%s' "$resp" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get('data') or {}).get('message_id',''))
except Exception:
    print('')
" 2>/dev/null)"
    log "发送成功（第 ${attempt} 次，message_id=${msg_id:-未知}，as=${FEISHU_AS}，${RECEIVER_TYPE}=${RECEIVER_ID}）"
    break
  fi
  log "第 ${attempt} 次发送失败：$(printf '%s' "$resp" | head -c 300)"
  [ "$attempt" -eq 1 ] && sleep 5
done

if [ "$ok" -eq 1 ]; then
  echo "已推送到飞书（${DATE}，${RECEIVER_TYPE}=${RECEIVER_ID}）"
  exit 0
fi
echo "推送失败，详见 $LOG" >&2
exit 1
