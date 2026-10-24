#!/usr/bin/env bash
# AI Radar — 每日 AI 动态扫描执行器（macOS / launchd 版，也可手动跑）
#
#   ./run.sh              # 跑今天
#   ./run.sh 2026-10-01   # 回填某天（报告写到 reports/2026-10-01.md）
#
# 相对原版（Linux/systemd）的改造：
#   1. systemd + notify-send → launchd + 飞书卡片推送
#   2. GNU timeout 不存在 → perl alarm+exec 实现同样的硬超时
#   3. fetch_content 工具不存在 → 抓取走 fetch.sh（自带调用记账，取证更准）
#   4. GNU date -d → BSD date -j -v-Nd
#   5. find -delete → find -exec rm -f
#
# 可用环境变量覆盖：
#   AI_RADAR_MODEL / AI_RADAR_THINKING / AI_RADAR_TIMEOUT / AI_RADAR_ATTEMPTS
#   AI_RADAR_MIN_SEARCHES / AI_RADAR_REQUIRE / AI_RADAR_BUDGET_SEARCH / AI_RADAR_BUDGET_FETCH
#   AI_RADAR_CITATION_STRICT=1   # 引用无法溯源时判为无效报告（默认 0：只披露+告警）
#   AI_RADAR_KEEP_REPORTS / AI_RADAR_KEEP_LOGS
#   AI_RADAR_NO_PUSH=1           # 跳过 git 提交推送
#   AI_RADAR_NO_FEISHU=1         # 跳过飞书推送
set -uo pipefail
export GIT_TERMINAL_PROMPT=0

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR" || exit 1

DATE="${1:-$(date +%F)}"
# BSD date 没有 -d；-j 表示只解析不设时钟
# 跨平台日期运算：macOS 用 BSD date -j -v，Linux 用 GNU date -d
week_start_for() { # <YYYY-MM-DD> → 6 天前
  date -j -v-6d -f "%Y-%m-%d" "$1" +%F 2>/dev/null \
    || date -d "$1 -6 days" +%F 2>/dev/null \
    || date -v-6d +%F
}
WEEK_START="$(week_start_for "$DATE")"
MODEL="${AI_RADAR_MODEL:-deepseek/deepseek-flash}"
THINKING="${AI_RADAR_THINKING:-medium}"
RUN_TIMEOUT="${AI_RADAR_TIMEOUT:-1800}"
ATTEMPTS="${AI_RADAR_ATTEMPTS:-2}"
MIN_REPORT_BYTES=400
MIN_SEARCHES="${AI_RADAR_MIN_SEARCHES:-2}"
CITATION_STRICT="${AI_RADAR_CITATION_STRICT:-0}"
REQUIRED_SECTIONS="${AI_RADAR_REQUIRE:-今日必读|最近一周产品情况|热度榜与风评|一手来源核查|抓取说明}"
BUDGET_SEARCH="${AI_RADAR_BUDGET_SEARCH:-12}"
BUDGET_FETCH="${AI_RADAR_BUDGET_FETCH:-12}"
KEEP_REPORT_DAYS="${AI_RADAR_KEEP_REPORTS:-90}"
KEEP_LOG_DAYS="${AI_RADAR_KEEP_LOGS:-30}"
NO_PUSH="${AI_RADAR_NO_PUSH:-0}"
NO_FEISHU="${AI_RADAR_NO_FEISHU:-0}"

LOG_DIR="$PROJECT_DIR/logs"
SESSION_DIR="$LOG_DIR/sessions"
REPORT="$PROJECT_DIR/reports/$DATE.md"
LOG="$LOG_DIR/$DATE.log"
SESSION_ID="ai-radar-$DATE-$(date +%H%M%S)"
PI_BIN="${AI_RADAR_PI_BIN:-$(command -v pi)}"

mkdir -p "$LOG_DIR" "$SESSION_DIR" "$PROJECT_DIR/reports"
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }

# 只把 fetch.sh 需要的代理传进 pi 的运行环境。
# 绝不 source 整个 config.env：里面有 webhook 凭据，pi 的 bash 工具和 session 都能看到它。
FETCH_PROXY="$(sed -n 's/^FETCH_PROXY=//p' "$PROJECT_DIR/config.env" 2>/dev/null | head -1)"
[ -n "$FETCH_PROXY" ] && export FETCH_PROXY

# 卡片按钮指向的 GitHub 基址。只有它非空时，“报告是否推送成功”才影响要不要发飞书。
REPORT_BASE_URL="$(sed -n 's/^REPORT_BASE_URL=//p' "$PROJECT_DIR/config.env" 2>/dev/null | head -1)"

# 抓取取证落账文件：fetch.sh 每抓一次追加一行（URL<TAB>HTTP码）
export AI_RADAR_FETCH_LOG="$SESSION_DIR/fetch-$SESSION_ID.tsv"
: >"$AI_RADAR_FETCH_LOG"

# macOS 没有 GNU timeout：alarm 设在 perl 进程上，exec 后仍然有效
run_with_timeout() { # secs cmd...
  local secs="$1"; shift
  perl -e 'alarm shift; exec @ARGV' "$secs" "$@" </dev/null
}

notify() { # title, body（macOS 桌面通知；Linux 无图形会话时静默跳过）
  if [ "$(uname -s)" = "Darwin" ]; then
    osascript -e "display notification \"${2//\"/\\\"}\" with title \"${1//\"/\\\"}\"" >/dev/null 2>&1 || true
  fi
}

# 飞书纯文本告警：用于“不是报告失败、而是根本跑不起来”的情况（余额不足、密钥失效）。
# 不走卡片（卡片需要报告）、不依赖 push-feishu.sh（那边会先检查报告存在）。
alert_feishu() { # text
  local url payload
  url="$(sed -n 's/^FEISHU_WEBHOOK_URL=//p' "$PROJECT_DIR/config.env" 2>/dev/null | head -1)"
  [ -n "$url" ] || return 0
  payload="$(TEXT="$1" python3 -c 'import json,os; print(json.dumps({"msg_type":"text","content":{"text":os.environ["TEXT"]}}, ensure_ascii=False))' 2>/dev/null)" || return 0
  [ -n "$payload" ] || return 0
  curl -s --max-time 15 -X POST "$url" -H 'Content-Type: application/json' \
    -d "$payload" >/dev/null 2>&1 || true
}

# 从日报里抠出前 N 条「今日必读」的加粗结论，用于失败/降级时的兜底通知
headlines() { # N
  awk -v limit="$1" '
    /^## / { insec = ($0 ~ /^## 今日必读/) }
    insec && /^- / {
      if (match($0, /\*\*[^*]+\*\*/)) { print "• " substr($0, RSTART + 2, RLENGTH - 4) }
      else { s = substr($0, 3); print "• " (length(s) > 90 ? substr(s, 1, 90) "…" : s) }
      n++; if (n >= limit) exit
    }' "$REPORT" 2>/dev/null
}

# URL 归一化：去转义、协议、www、锚点/查询、末尾标点与斜杠
norm_url() { sed -E 's#\\/#/#g; s#^https?://##; s#^www\.##; s#[#?].*$##; s#[)\]\}.,;:*]+$##; s#/$##'; }

[ -f "$PROJECT_DIR/prompt.md" ] || { log "FATAL: prompt.md 不存在"; notify "AI Radar 配置错误" "找不到 prompt.md"; exit 2; }
PROMPT="$(sed -e "s|{{WEEK_START}}|$WEEK_START|g" -e "s|{{DATE}}|$DATE|g" \
  -e "s|{{BUDGET_SEARCH}}|$BUDGET_SEARCH|g" -e "s|{{BUDGET_FETCH}}|$BUDGET_FETCH|g" \
  "$PROJECT_DIR/prompt.md")"
[ -n "$PROMPT" ] || { log "FATAL: prompt 渲染为空"; exit 2; }

log "===== ai-radar $DATE 开始（model=$MODEL, thinking=$THINKING, attempts=$ATTEMPTS, week=${WEEK_START}）====="

status="fail"; attempt=0
missing_sections=""; searches=0; fetches=0
social_cites=0; tier_first=0; tier_second=0; fh_total=0; fh_verified=0; fh_unverified=0
total_cited=0; untraceable=0; untraceable_list=""; sess_file=""
while [ "$attempt" -lt "$ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  log "-- attempt $attempt/$ATTEMPTS --"
  rm -f "$REPORT"
  attempt_out="$SESSION_DIR/out-$SESSION_ID-$attempt.log"
  run_with_timeout "$RUN_TIMEOUT" \
    "$PI_BIN" --print --approve \
    --model "$MODEL" --thinking "$THINKING" \
    --name "ai-radar $DATE" --session-dir "$SESSION_DIR" --session-id "$SESSION_ID" \
    --tools read,write,edit,bash,web_search \
    "$PROMPT" >"$attempt_out" 2>&1
  rc=$?
  cat "$attempt_out" >>"$LOG" 2>/dev/null
  [ "$rc" -eq 142 ] && log "WARN: 超过 ${RUN_TIMEOUT}s 被强杀（alarm）"

  # 账户级故障：重试无意义，立即止报而不是空烧到超时
  if grep -q 'Insufficient Balance' "$attempt_out" 2>/dev/null; then
    log "FATAL: ${MODEL} 返回 Insufficient Balance（余额不足），任务终止。重试无意义，已跳过剩余尝试。"
    notify "AI Radar 余额不足" "${MODEL} 账户余额不足，今日日报未生成"
    alert_feishu "【AI Radar 告警】${DATE} 日报未生成：${MODEL} 账户余额不足（Insufficient Balance）。充值后手动跑 ./run.sh ${DATE} 补上。"
    rm -f "$attempt_out"
    exit 3
  fi
  size=0; [ -f "$REPORT" ] && size=$(wc -c <"$REPORT")

  # (a) 结构校验：必备章节标题是否齐全
  missing_sections=""
  if [ -f "$REPORT" ]; then
    IFS='|' read -r -a _want <<< "$REQUIRED_SECTIONS"
    for _token in "${_want[@]}"; do
      grep -qF -- "$_token" "$REPORT" || missing_sections="$missing_sections$_token "
    done
  fi

  # (b) 取证：真实检索次数从 session 数，真实抓取次数从 fetch.sh 的记账数
  sess_file="$(ls -t "$SESSION_DIR"/*_"$SESSION_ID".jsonl 2>/dev/null | head -1)"
  searches=0; social_cites=0; tier_first=0; tier_second=0
  fh_total=0; fh_verified=0; fh_unverified=0; fh_unverified_list=""
  fetches=0; [ -f "$AI_RADAR_FETCH_LOG" ] && fetches=$(grep -c . "$AI_RADAR_FETCH_LOG")
  if [ -n "$sess_file" ]; then
    searches=$(grep -o '"type":"toolCall","id":"[^"]*","name":"web_search"' "$sess_file" | wc -l | tr -d ' ')
    social_cites=$(grep -oE '\]\(https?://(www\.)?(x\.com|twitter\.com|reddit\.com|news\.ycombinator\.com|weibo\.com|zhihu\.com)/[^)]*' "$REPORT" 2>/dev/null | wc -l | tr -d ' ')
    tier_first=$(grep -o '【一手】' "$REPORT" 2>/dev/null | wc -l | tr -d ' ')
    tier_second=$(grep -o '【二手】' "$REPORT" 2>/dev/null | wc -l | tr -d ' ')
  fi

  # (c) 引文溯源：报告里每条引用 URL 必须在本轮 session 出现过
  total_cited=0; untraceable=0; untraceable_list=""
  if [ -n "$sess_file" ] && [ -f "$REPORT" ]; then
    _pool="$(mktemp "${TMPDIR:-/tmp}/airadar-pool.XXXXXX")"; _cited="$(mktemp "${TMPDIR:-/tmp}/airadar-cited.XXXXXX")"
    grep -oE 'https?://[^"\\ )]+' "$sess_file" | norm_url | LC_ALL=C sort -u >"$_pool"
    grep -oE '\]\(https?://[^)]+\)' "$REPORT" | sed -E 's#^\]\(##; s#\)$##' | norm_url | LC_ALL=C sort -u >"$_cited"
    total_cited=$(grep -c . "$_cited" || true)
    _missing="$(LC_ALL=C comm -23 "$_cited" "$_pool")"
    untraceable=$(printf '%s' "$_missing" | grep -c . || true)
    untraceable_list="$(printf '%s' "$_missing" | grep . | head -5 | tr '\n' ' ')"
    rm -f "$_pool" "$_cited"
  fi

  # (d) 一手取证：标了【一手】的断言行，其引用 URL 必须在本轮真的被 fetch.sh 抓过
  if [ -f "$AI_RADAR_FETCH_LOG" ] && [ -f "$REPORT" ]; then
    _fpool="$(mktemp "${TMPDIR:-/tmp}/airadar-fpool.XXXXXX")"
    cut -f1 "$AI_RADAR_FETCH_LOG" | norm_url | LC_ALL=C sort -u >"$_fpool"
    while IFS= read -r _line; do
      _urls="$(printf '%s' "$_line" | grep -oE '\]\(https?://[^)]+\)' | sed -E 's#^\]\(##; s#\)$##')"
      [ -n "$_urls" ] || continue
      fh_total=$((fh_total + 1))
      _hit=0
      while IFS= read -r _u; do
        [ -n "$_u" ] || continue
        if grep -qxF "$(printf '%s' "$_u" | norm_url)" "$_fpool"; then _hit=1; break; fi
      done <<< "$_urls"
      if [ "$_hit" -eq 1 ]; then fh_verified=$((fh_verified + 1)); else
        fh_unverified_list="$fh_unverified_list$(printf '%s' "$_line" | cut -c1-70) ｜"
      fi
    done < <(grep -E '^- .*【一手】' "$REPORT")
    fh_unverified=$((fh_total - fh_verified))
    rm -f "$_fpool"
  fi

  log "-- attempt $attempt 结束：exit=$rc report_bytes=$size 真实检索=${searches} / 抓取=${fetches} / 引用溯源 $((total_cited - untraceable))/$total_cited / 一手${tier_first} 二手${tier_second} 社媒${social_cites} / 一手取证 ${fh_verified}/${fh_total} --"

  ok=1
  [ "$rc" -eq 0 ] || ok=0
  [ "$size" -ge "$MIN_REPORT_BYTES" ] || ok=0
  [ "$searches" -ge "$MIN_SEARCHES" ] || ok=0
  [ -z "$missing_sections" ] || ok=0
  { [ "$CITATION_STRICT" != "1" ] || [ "$untraceable" -eq 0 ]; } || ok=0

  if [ "$ok" -eq 1 ]; then status="ok"; break; fi

  [ -z "$missing_sections" ] || log "无效：报告缺少必备章节：$missing_sections"
  [ "$searches" -ge "$MIN_SEARCHES" ] || log "无效：本轮实际检索 $searches 次（需 ≥${MIN_SEARCHES}），报告可能凭空生成"
  [ "$untraceable" -gt 0 ] && log "WARN: $untraceable 条引用无法在本轮会话中溯源：$untraceable_list"
  [ "$fh_unverified" -gt 0 ] && log "WARN: $fh_unverified 条【一手】断言的引用未被本轮抓取：$fh_unverified_list"
  if [ "$attempt" -lt "$ATTEMPTS" ]; then log "本次未产出有效报告，60s 后重试（复用同一 session）"; sleep 60; fi
done

# 项目内保留策略（BSD find 没有 -delete）
prune() { find "$1" -maxdepth 1 -type f -name "$2" -mtime +"$3" -exec rm -f {} + 2>/dev/null; }
prune "$PROJECT_DIR/reports" '*.md' "$KEEP_REPORT_DAYS"
prune "$LOG_DIR" '*.log' "$KEEP_LOG_DAYS"
prune "$SESSION_DIR" '*.jsonl' "$KEEP_LOG_DAYS"
prune "$SESSION_DIR" '*.tsv' "$KEEP_LOG_DAYS"
prune "$SESSION_DIR" 'out-*.log' "$KEEP_LOG_DAYS"

# 运行器举证：把可验证的事实写进报告本身
if [ "$status" = "ok" ] && [ -n "$sess_file" ]; then
  if ! grep -q '信息来源（运行器写入）' "$REPORT"; then
    src_note="> **信息来源（运行器写入）**：检索通道 DeepSeek Search API（pi-web-search 扩展），抓取通道 curl + fetch.sh（失败即记 0，不重抓）。本轮真实调用：web_search ${searches} 次 / 抓取正文 ${fetches} 次（抓取由 fetch.sh 自己记账）；引文溯源 $((total_cited - untraceable))/${total_cited} 条可在本轮会话中追溯；来源层级标注：一手 ${tier_first} 条 / 二手 ${tier_second} 条；一手取证：${fh_verified}/${fh_total} 条【一手】断言的引用确为本轮抓取过$( [ "$fh_unverified" -gt 0 ] && printf '，**其中 %s 条仅凭搜索摘要（应降级为【二手】）**' "$fh_unverified" )。"
    { head -1 "$REPORT"; printf '\n%s\n' "$src_note"; tail -n +2 "$REPORT"; } >"$REPORT.tmp" && mv "$REPORT.tmp" "$REPORT"
    log "已写入来源披露（溯源 $((total_cited - untraceable))/${total_cited}）"
  fi
  if ! grep -q '运行器取证' "$REPORT"; then
    printf -- '- 运行器取证（run.sh 解析 session + fetch.sh 记账，非模型自述）：web_search %s 次 / 抓取正文 %s 次（预算上限 %s / %s）\n' \
      "$searches" "$fetches" "$BUDGET_SEARCH" "$BUDGET_FETCH" >>"$REPORT"
    log "已追加运行器取证：检索 $searches / 抓取 $fetches"
  fi
  [ "$searches" -gt "$BUDGET_SEARCH" ] && log "WARN: 超出检索预算（$searches > ${BUDGET_SEARCH}）"
  [ "$fetches" -gt "$BUDGET_FETCH" ] && log "WARN: 超出抓取预算（$fetches > ${BUDGET_FETCH}）"
  [ "$untraceable" -gt 0 ] && log "WARN: 存在无法溯源的引用，已在报告头部标明"
  [ "$social_cites" -gt 0 ] && log "WARN: 报告含 $social_cites 条社交平台引用（只能作线索，须回溯一手来源）"
fi

# 落账到 git（推送失败不改变任务成败：日报才是主要产出）
push_note=""
push_ok=1   # 0 = 报告没真正上去；卡片按钮会 404，此时不能发飞书
if [ "$status" = "ok" ] && [ "$NO_PUSH" != "1" ] && git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null)" ]; then
    git -C "$PROJECT_DIR" add -A -- reports INDEX.md THEMES.md logs 2>/dev/null
    # logs/ 在 .gitignore 里，add 会被忽略；这里只提交真正需要入库的
    git -C "$PROJECT_DIR" add -A -- . >>"$LOG" 2>&1
    if git -C "$PROJECT_DIR" commit -q -m "report: $DATE" >>"$LOG" 2>&1; then
      log "git: 已提交 report: $DATE"
    else
      # cron 环境最常见原因：没有 user.name / user.email
      push_ok=0
      log "FATAL: git commit 失败（cron 环境多为未配置 user.name/user.email，见下方 git 报错）"
    fi
  else
    log "git: 无变更，跳过提交"
  fi
  if run_with_timeout 120 git -C "$PROJECT_DIR" push --quiet origin HEAD >>"$LOG" 2>&1; then
    log "git: 已推送 origin"
  else
    push_ok=0
    push_note="（git push 未成功，本地提交已保留，详见 logs/$DATE.log）"
    log "WARN: git push 失败"
  fi
fi

# 飞书卡片推送（主通知通道）
feishu_note=""
if [ "$status" = "ok" ] && [ "$NO_FEISHU" != "1" ]; then
  # 卡片按钮指向 REPORT_BASE_URL；报告没推上去还发，点开必然 404
  if [ "$push_ok" != "1" ] && [ -n "$REPORT_BASE_URL" ]; then
    log "WARN: 报告未推送成功，跳过飞书推送（否则卡片按钮会 404）"
    feishu_note="（报告未推送，已跳过飞书）"
  elif [ -x "$PROJECT_DIR/push-feishu.sh" ]; then
    if "$PROJECT_DIR/push-feishu.sh" "$DATE" >>"$LOG" 2>&1; then
      log "飞书: 卡片已推送"
    else
      feishu_note="（飞书推送失败，详见 logs/$DATE.log）"
      log "WARN: 飞书推送失败"
    fi
  else
    log "WARN: push-feishu.sh 不存在或不可执行，跳过飞书"
  fi
fi

if [ "$status" = "ok" ]; then
  body="$(headlines 3)"
  [ -n "$body" ] || body="报告已生成：reports/$DATE.md"
  [ -n "$push_note" ] && body="$body"$'\n'"$push_note"
  [ -n "$feishu_note" ] && body="$body"$'\n'"$feishu_note"
  notify "AI Radar $DATE · $(printf '%s\n' "$body" | grep -c '^•') 条必读" "$body"
  log "===== 成功：${REPORT}（$(wc -c <"$REPORT") 字节，检索 $searches / 抓取 ${fetches}）====="
  exit 0
fi

notify "AI Radar $DATE 抓取失败" "已重试 $ATTEMPTS 次，详见 logs/$DATE.log"
log "===== 失败：多次尝试后仍未产出有效报告 ====="
exit 1
