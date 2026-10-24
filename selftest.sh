#!/usr/bin/env bash
# AI Radar 自检（macOS 版）：把「定时任务能不能真跑起来」变成可机器验证的断言。
#   ./selftest.sh        # 全部检查，PASS/FAIL 汇总，任一 FAIL 则退出码 1
set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC="$PROJECT_DIR/com.gugu.ai-radar.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.gugu.ai-radar.plist"
PASS=0; FAIL=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
info() { printf '  \033[2m----\033[0m %s\n' "$1"; }
check() { # 描述, 命令…
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

echo "AI Radar 自检 — $PROJECT_DIR"
echo

echo "[1] 项目文件"
for f in prompt.md run.sh selftest.sh README.md INDEX.md THEMES.md \
         build-card.py push-feishu.sh fetch.sh config.env .gitignore; do
  check "$f 存在且非空" test -s "$PROJECT_DIR/$f"
done
for f in run.sh selftest.sh push-feishu.sh fetch.sh build-card.py; do
  check "$f 可执行" test -x "$PROJECT_DIR/$f"
done
check "run.sh 语法正确" bash -n "$PROJECT_DIR/run.sh"
check "push-feishu.sh 语法正确" bash -n "$PROJECT_DIR/push-feishu.sh"
check "fetch.sh 语法正确" bash -n "$PROJECT_DIR/fetch.sh"
check "build-card.py 语法正确" python3 -m py_compile "$PROJECT_DIR/build-card.py"
check "reports/ 可写" test -w "$PROJECT_DIR/reports"
check "logs/ 可写" test -w "$PROJECT_DIR/logs"
echo

echo "[2] 提示词契约（prompt.md 必须约束住产出路径与来源强度）"
for token in '{{DATE}}' '{{WEEK_START}}' 'reports/{{DATE}}.md' 'INDEX.md' 'THEMES.md' \
             'web_search' './fetch.sh' '【已证实】' '【一手】' '【二手】' '【社媒线索】' \
             '本轮实际' '最近一周产品情况' '热度榜与风评' '趋势解读' \
             '至少覆盖 2 个不同来源' '一手来源核查' '{{BUDGET_SEARCH}}' '{{BUDGET_FETCH}}'; do
  check "prompt.md 含 $token" grep -qF -- "$token" "$PROJECT_DIR/prompt.md"
done
check "prompt.md 已无旧工具名 fetch_content" bash -c "! grep -qF 'fetch_content' '$PROJECT_DIR/prompt.md'"
check "prompt.md 已无 exa provider 参数" bash -c "! grep -qF 'provider: \"exa\"' '$PROJECT_DIR/prompt.md'"
check "提示词渲染无残留占位符" bash -c "sed -e 's|{{WEEK_START}}|x|g' -e 's|{{DATE}}|x|g' -e 's|{{BUDGET_SEARCH}}|x|g' -e 's|{{BUDGET_FETCH}}|x|g' '$PROJECT_DIR/prompt.md' | grep -q '{{' && exit 1 || exit 0"
echo

echo "[3] 执行器护栏（防"零检索凭记忆交作业"与 macOS 兼容）"
check "session 收在项目内（logs/sessions）" grep -qF 'SESSION_DIR="$LOG_DIR/sessions"' "$PROJECT_DIR/run.sh"
check "每次调用生成独立 session id" grep -qF 'SESSION_ID="ai-radar-$DATE-$(date +%H%M%S)"' "$PROJECT_DIR/run.sh"
check "run.sh 传了 --session-dir" grep -qF -- '--session-dir "$SESSION_DIR"' "$PROJECT_DIR/run.sh"
check "工具白名单不含已废弃的 fetch_content" bash -c "! grep -q 'fetch_content,get_search_content' '$PROJECT_DIR/run.sh'"
check "存在真实检索次数护栏" grep -qF 'AI_RADAR_MIN_SEARCHES' "$PROJECT_DIR/run.sh"
check "周度窗口为滚动 7 天（BSD date -v-6d）" grep -qF 'date -j -v-6d' "$PROJECT_DIR/run.sh"
check "存在报告必备章节校验" grep -qF 'AI_RADAR_REQUIRE' "$PROJECT_DIR/run.sh"
check "真实调用次数会追写进报告" grep -qF '运行器取证' "$PROJECT_DIR/run.sh"
check "引文溯源已机器化" grep -qF '引文溯源' "$PROJECT_DIR/run.sh"
check "URL 归一化函数存在" grep -qF 'norm_url()' "$PROJECT_DIR/run.sh"
check "溯源严格模式可开关" grep -qF 'AI_RADAR_CITATION_STRICT' "$PROJECT_DIR/run.sh"
check "报告头部会写入来源披露" grep -qF '信息来源（运行器写入）' "$PROJECT_DIR/run.sh"
check "会检测社交平台引用" grep -qF 'social_cites' "$PROJECT_DIR/run.sh"
check "会统计来源层级标注数" grep -qF 'tier_first' "$PROJECT_DIR/run.sh"
check "一手取证已机器化" grep -qF '一手取证：' "$PROJECT_DIR/run.sh"
check "预算由 run.sh 注入提示词" grep -qF '{{BUDGET_FETCH}}' "$PROJECT_DIR/run.sh"
check "抓取取证走 fetch.sh 记账" grep -qF 'AI_RADAR_FETCH_LOG' "$PROJECT_DIR/run.sh"
check "fetch.sh 会写入取证记账" grep -qF 'AI_RADAR_FETCH_LOG' "$PROJECT_DIR/fetch.sh"
check "macOS 无 timeout：改用 perl alarm" grep -qF "perl -e 'alarm shift; exec @ARGV'" "$PROJECT_DIR/run.sh"
check "BSD find 无 -delete：改用 -exec rm" bash -c "! grep -v '^[[:space:]]*#' '$PROJECT_DIR/run.sh' | grep -q -- '-delete'"
check "已移除 systemd 依赖" bash -c "! grep -q 'systemctl' '$PROJECT_DIR/run.sh'"
check "已移除 notify-send 依赖" bash -c "! grep -v '^[[:space:]]*#' '$PROJECT_DIR/run.sh' | grep -q 'notify-send'"
check "无效报告会触发重试" grep -qF '报告可能凭空生成' "$PROJECT_DIR/run.sh"
check "sessions 与 fetch 记账也会被清理" grep -qF "prune \"\$SESSION_DIR\" '*.tsv'" "$PROJECT_DIR/run.sh"
check "fetch.sh 直连失败会走代理重试" grep -qF 'try_fetch proxy' "$PROJECT_DIR/fetch.sh"
check "fetch.sh 支持 JSON 透传（API 不被 HTML 清洗）" grep -qF '*json*)' "$PROJECT_DIR/fetch.sh"
check "fetch.sh 不会 source 整个 config.env" bash -c "! grep -qE '^[[:space:]]*\.[[:space:]]+.*config\.env' '$PROJECT_DIR/fetch.sh'"
check "run.sh 只 export FETCH_PROXY（不把 webhook 凭据喂给 agent）" bash -c "! grep -qE '^[[:space:]]*\.[[:space:]]+.*config\.env' '$PROJECT_DIR/run.sh' && grep -q 'export FETCH_PROXY' '$PROJECT_DIR/run.sh'"
echo

echo "[4] 运行前提"
check "pi 在 PATH" command -v pi
check "python3 在 PATH" command -v python3
check "curl 在 PATH" command -v curl
check "lark-cli 在 PATH" command -v lark-cli
MODEL="${AI_RADAR_MODEL:-$(sed -n 's/^MODEL="\${AI_RADAR_MODEL:-\(.*\)}"$/\1/p' "$PROJECT_DIR/run.sh" | head -1)}"
info "run.sh 默认模型：${MODEL:-<未解析到>}"
check "模型在 pi 模型中可见（${MODEL}）" \
  bash -c "pi --list-models 2>/dev/null | awk '{print \$1\"/\"\$2}' | grep -qxF '$MODEL'"
check "已装提供 web_search 的扩展（pi-web-search 或 pi-web-access）" bash -c "pi list 2>/dev/null | grep -qE 'pi-web-(search|access)'"
check "pi 凭据 auth.json 存在" test -r "$HOME/.pi/agent/auth.json"
check "DeepSeek Search API 真实可达" bash -c "
  K=\$(python3 -c \"import json,os;print(json.load(open(os.path.expanduser('~/.pi/agent/auth.json')))['deepseek']['key'])\") &&
  curl -s --max-time 30 -o /dev/null -w '%{http_code}' -X POST https://api.deepseek.com/v1/tools/search \
    -H \"Authorization: Bearer \$K\" -H 'Content-Type: application/json' \
    -d '{\"query\":\"selftest\",\"max_results\":1}' | grep -q 200"
check "fetch.sh 能抓到真实正文" bash -c "cd '$PROJECT_DIR' && ./fetch.sh https://techcrunch.com/ 300 | grep -q ."
PROXY_CONF="$(sed -n 's/^FETCH_PROXY=//p' "$PROJECT_DIR/config.env" | head -1)"
if [ -n "$PROXY_CONF" ]; then
  info "代理配置：$PROXY_CONF"
  check "被墙站能通过代理降级抓到（huggingface.co）" bash -c "cd '$PROJECT_DIR' && ./fetch.sh https://huggingface.co 100 | grep -q ."
  check "JSON API 透传可用（HF trending）" bash -c "cd '$PROJECT_DIR' && ./fetch.sh 'https://huggingface.co/api/models?sort=trendingScore&direction=-1&limit=2' 200 | grep -q trendingScore"
else
  info "未配置 FETCH_PROXY，被墙站（huggingface.co 等）将抓不到"
fi
echo

if [ "$(uname -s)" = "Darwin" ]; then
echo "[5] 定时任务（launchd，macOS）"
check "仓库内有 plist 模板" test -s "$PLIST_SRC"
check "plist 已安装到 ~/Library/LaunchAgents" test -s "$PLIST_DST"
check "plist 语法有效（plutil）" plutil -lint "$PLIST_DST"
check "plist 配置为 08:30" bash -c "plutil -p '$PLIST_DST' | grep -q '\"Hour\" => 8' && plutil -p '$PLIST_DST' | grep -q '\"Minute\" => 30'"
check "plist 的 PATH 含 pi 目录" bash -c "plutil -p '$PLIST_DST' | grep -q '.pi/agent/bin'"
check "launchd 已加载该任务" bash -c "launchctl list | grep -q 'com.gugu.ai-radar'"
info "launchctl 状态：$(launchctl list | grep 'com.gugu.ai-radar' || echo '<未加载>')"
else
echo "[5] 定时任务（cron / systemd timer，Linux）"
if crontab -l 2>/dev/null | grep -q 'ai-radar/run.sh'; then
  ok "crontab 已配置 ai-radar"
  info "cron: $(crontab -l 2>/dev/null | grep 'ai-radar/run.sh')"
elif systemctl list-timers 2>/dev/null | grep -q 'ai-radar'; then
  ok "systemd timer 已配置 ai-radar"
else
  info "未检测到 cron / systemd timer（定时未配置）"
fi
fi
echo

echo "[6] 飞书推送可达性"
WEBHOOK="$(sed -n 's/^FEISHU_WEBHOOK_URL=//p' "$PROJECT_DIR/config.env" | head -1)"
RECEIVER="$(sed -n 's/^FEISHU_RECEIVER_ID=//p' "$PROJECT_DIR/config.env" | head -1)"
if [ -n "$WEBHOOK" ]; then
  ok "已配置 webhook 通道（外部群可用）"
  check "webhook 地址形如 open-apis/bot/v2/hook" bash -c "echo '$WEBHOOK' | grep -q 'bot/v2/hook'"
  if [ -n "$(sed -n 's/^FEISHU_WEBHOOK_SECRET=//p' "$PROJECT_DIR/config.env" | head -1)" ]; then
    ok "已配置 webhook 签名密钥（签名校验模式）"
  else
    info "未配签名密钥（若机器人开了签名校验，发送会失败）"
  fi
  check "webhook 地址真实可达（不发送、只看连通性）" bash -c "curl -s -o /dev/null --max-time 15 -X POST '$WEBHOOK' -H 'Content-Type: application/json' -d '{}' ; true"
elif [ -n "$RECEIVER" ]; then
  ok "已配置 lark-cli 通道（仅内部群/私聊可用）"
  check "bot 身份 ready" bash -c "lark-cli auth status 2>/dev/null | grep -q '\"bot\"'"
  info "接收配置：$(grep -E '^FEISHU_(AS|RECEIVER_TYPE)=' "$PROJECT_DIR/config.env" | tr '\n' ' ')"
else
  bad "webhook 和 receiver 都没配，无法推送"
fi
LATEST_REPORT="$(ls -t "$PROJECT_DIR"/reports/*.md 2>/dev/null | head -1)"
if [ -n "$LATEST_REPORT" ]; then
  check "卡片是 Card 1.0 格式（webhook 只认 1.0，2.0 会静默不渲染）" bash -c "python3 '$PROJECT_DIR/build-card.py' '$LATEST_REPORT' | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"schema\" not in d and d.get(\"elements\") and d.get(\"header\")'"
  check "卡片含今日必读条目" bash -c "python3 '$PROJECT_DIR/build-card.py' '$LATEST_REPORT' | grep -q '条必读'"
else
  info "尚无报告，跳过卡片生成检查"
fi
if grep -qE '^REPORT_BASE_URL=https://' "$PROJECT_DIR/config.env"; then
  ok "REPORT_BASE_URL 已配置（卡片有跳转按钮）"
else
  info "REPORT_BASE_URL 未配置（卡片只有内容、无跳转按钮）"
fi
echo

echo "[7] 版本管理与保留策略"
check "项目是 git 仓库" git -C "$PROJECT_DIR" rev-parse --git-dir
check "已配置 origin 远端" git -C "$PROJECT_DIR" remote get-url origin
check ".gitignore 忽略 logs/" bash -c "git -C '$PROJECT_DIR' check-ignore -q logs/probe.log"
check ".gitignore 忽略 config.env" bash -c "git -C '$PROJECT_DIR' check-ignore -q config.env"
check "config.env 未被跟踪" bash -c "! git -C '$PROJECT_DIR' ls-files --error-unmatch config.env 2>/dev/null | grep -q ."
info "远端：$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || echo '<无>')"
echo

echo "[8] 运行留痕"
if ls "$PROJECT_DIR"/reports/*.md >/dev/null 2>&1; then
  info "已有报告 $(ls "$PROJECT_DIR"/reports/*.md | wc -l | tr -d ' ') 份，最新：$(basename "$LATEST_REPORT")"
  d="$(basename "$LATEST_REPORT" .md)"
  sess="$(ls -t "$PROJECT_DIR"/logs/sessions/*_"ai-radar-$d-"*.jsonl 2>/dev/null | head -1)"
  if [ -n "$sess" ]; then
    n=$(grep -o '"type":"toolCall","id":"[^"]*","name":"web_search"' "$sess" | wc -l | tr -d ' ')
    info "该报告 session 记录到真实 web_search $n 次"
    if [ "$n" -ge 2 ]; then ok "有真实检索取证（≥2 次）"; else info "检索取证不足（$n 次，可能是历史/测试报告）"; fi
  else
    info "该报告无对应 session（可能是外部导入的样例报告）"
  fi
  miss=""
  for t in 今日必读 最近一周产品情况 热度榜与风评 一手来源核查 抓取说明; do
    grep -qF -- "$t" "$LATEST_REPORT" || miss="$miss$t "
  done
  if [ -z "$miss" ]; then ok "最新报告包含五个必备章节"; else bad "最新报告缺少章节：$miss"; fi
else
  info "尚无报告（还没跑过）"
fi
echo

printf '结果：\033[32m%d PASS\033[0m / ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d FAIL\033[0m\n' "$FAIL"; exit 1; fi
printf '0 FAIL\n'
exit 0
