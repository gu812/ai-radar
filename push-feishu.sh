#!/usr/bin/env bash
# 把某天的日报压成一张飞书卡片，发到群 / 私聊。
#
# 两条发送通道，按配置自动选择：
#   1. FEISHU_WEBHOOK_URL 非空 → 群自定义机器人 Webhook（外部群只能用这个）
#   2. 否则                    → lark-cli 应用机器人（只能在内部群 / 私聊用）
#
#   ./push-feishu.sh                 # 发今天的 reports/$(date +%F).md
#   ./push-feishu.sh 2026-10-20      # 补发某天
#   ./push-feishu.sh --dry-run       # 只生成卡片 JSON 并打印，不发送
#
# 配置（环境变量 > config.env）：
#   FEISHU_WEBHOOK_URL=https://open.feishu.cn/open-apis/bot/v2/hook/xxx
#   FEISHU_WEBHOOK_SECRET=xxx        # 加机器人时若勾了"签名校验"，填这里；否则留空
#   FEISHU_AS=bot                    # lark-cli 通道：bot | user
#   FEISHU_RECEIVER_TYPE=user        # lark-cli 通道：user | chat
#   FEISHU_RECEIVER_ID=ou_xxx        # lark-cli 通道：open_id 或 chat_id
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

# 配置：环境变量优先于 config.env（注释和实现必须一致——早期版本 source 之后会反向覆盖）
# 用 ${VAR-__unset__} 区分「没设置」和「显式设成空」：设空可以临时禁用某个通道。
_SAVED_WEBHOOK="${FEISHU_WEBHOOK_URL-__unset__}"
_SAVED_SECRET="${FEISHU_WEBHOOK_SECRET-__unset__}"
_SAVED_RECEIVER="${FEISHU_RECEIVER_ID-__unset__}"
_SAVED_BASE="${REPORT_BASE_URL-__unset__}"
if [ -r "$PROJECT_DIR/config.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/config.env"
  set +a
fi
[ "$_SAVED_WEBHOOK" != "__unset__" ] && FEISHU_WEBHOOK_URL="$_SAVED_WEBHOOK"
[ "$_SAVED_SECRET" != "__unset__" ] && FEISHU_WEBHOOK_SECRET="$_SAVED_SECRET"
[ "$_SAVED_RECEIVER" != "__unset__" ] && FEISHU_RECEIVER_ID="$_SAVED_RECEIVER"
[ "$_SAVED_BASE" != "__unset__" ] && REPORT_BASE_URL="$_SAVED_BASE"
WEBHOOK_URL="${FEISHU_WEBHOOK_URL:-}"
WEBHOOK_SECRET="${FEISHU_WEBHOOK_SECRET:-}"
FEISHU_AS="${FEISHU_AS:-bot}"
RECEIVER_TYPE="${FEISHU_RECEIVER_TYPE:-user}"
RECEIVER_ID="${FEISHU_RECEIVER_ID:-}"
REPORT_BASE_URL="${REPORT_BASE_URL:-}"

[ -f "$REPORT" ] || { echo "找不到报告：$REPORT" >&2; log "跳过：报告不存在"; exit 3; }

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

# ---------- 通道一：群自定义机器人 Webhook ----------
send_webhook() {
  CARD="$CARD" SECRET="$WEBHOOK_SECRET" python3 - <<'PY'
import base64
import hashlib
import hmac
import json
import os
import time

payload = {"msg_type": "interactive", "card": json.loads(os.environ["CARD"])}
secret = os.environ.get("SECRET", "")
if secret:
    # 飞书签名：以 "timestamp\nsecret" 为 key，对空串做 HmacSHA256 再 base64
    ts = str(int(time.time()))
    key = f"{ts}\n{secret}".encode("utf-8")
    payload["timestamp"] = ts
    payload["sign"] = base64.b64encode(
        hmac.new(key, b"", hashlib.sha256).digest()
    ).decode("utf-8")
print(json.dumps(payload, ensure_ascii=False))
PY
}

webhook_ok() { # 判断响应是否成功：飞书新接口 code=0，旧接口 StatusCode=0
  printf '%s' "$1" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
code = d.get('code', d.get('StatusCode'))
sys.exit(0 if code == 0 else 1)
" 2>/dev/null
}

if [ -n "$WEBHOOK_URL" ]; then
  payload="$(send_webhook)" || { echo "构造 webhook 请求失败" >&2; exit 8; }
  ok=0
  for attempt in 1 2; do
    resp="$(curl -s --max-time 20 -X POST "$WEBHOOK_URL" \
      -H 'Content-Type: application/json; charset=utf-8' -d "$payload" 2>>"$LOG")"
    if webhook_ok "$resp"; then
      ok=1
      log "webhook 发送成功（第 ${attempt} 次）：$(printf '%s' "$resp" | head -c 200)"
      break
    fi
    log "webhook 第 ${attempt} 次失败：$(printf '%s' "$resp" | head -c 300)"
    [ "$attempt" -eq 1 ] && sleep 5
  done
  if [ "$ok" -eq 1 ]; then
    echo "已推送到飞书（${DATE}，webhook）"
    exit 0
  fi
  echo "webhook 推送失败，详见 $LOG" >&2
  exit 1
fi

# ---------- 通道二：lark-cli 应用机器人 ----------
[ -n "$RECEIVER_ID" ] || { echo "既没配 FEISHU_WEBHOOK_URL，也没配 FEISHU_RECEIVER_ID（见 config.env）" >&2; exit 4; }
command -v lark-cli >/dev/null || { echo "lark-cli 不在 PATH" >&2; exit 5; }

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
