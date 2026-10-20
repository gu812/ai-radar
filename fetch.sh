#!/usr/bin/env bash
# 抓网页正文，给 pi 的 bash 工具用（本机没有 fetch_content 工具，走 curl 兜底）。
#
#   ./fetch.sh <url> [max_chars]     # 默认输出前 12000 字符
#
# 抓取策略：先直连，失败再用 FETCH_PROXY 重试。
#   本机网络下 huggingface.co / lmarena.ai 直连是 000（被墙），走代理才通；
#   而 anthropic.com / github.blog 直连就 200，走代理反而多一跳。所以是两级降级，不是全走代理。
#
# 退出码：0 成功；1 抓取失败；2 参数错误
# 输出：标题 + 正文纯文本（已去 script/style/标签、压缩空白）
set -uo pipefail

URL="${1:-}"
MAX="${2:-12000}"
[ -n "$URL" ] || { echo "用法: $0 <url> [max_chars]" >&2; exit 2; }

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

# 代理：优先用环境变量（run.sh export 进来的）；手动跑时自己从 config.env 补。
# 只 sed 取这一行，不 source 整个 config.env——里面有 webhook 凭据，
# 而本脚本会被 pi 的 bash 工具调用，不能让凭据进 agent 环境。
PROXY="${FETCH_PROXY:-}"
if [ -z "$PROXY" ]; then
  _cfg="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/config.env"
  [ -r "$_cfg" ] && PROXY="$(sed -n 's/^FETCH_PROXY=//p' "$_cfg" 2>/dev/null | head -1)"
fi

TMP="$(mktemp -t airadar-fetch)"
trap 'rm -f "$TMP"' EXIT

# 抓一次，把 HTTP 码与 content-type 打到 stdout
# 不用 "${arr[@]}" 传参：macOS 自带 bash 3.2 在 set -u 下展开空数组会报 unbound variable
do_curl() {
  curl -sL --compressed --max-time 40 \
    -A "$UA" "$@" \
    -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
    -H 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8' \
    -w '%{http_code}|%{content_type}' -o "$TMP" "$URL" 2>/dev/null
}

try_fetch() { # mode(direct|proxy)
  if [ "$1" = "proxy" ]; then
    do_curl -x "$PROXY"
  else
    do_curl
  fi
}

channel="direct"; raw="$(try_fetch direct)"
code="${raw%%|*}"; ctype="${raw#*|}"
# 000 = 连不上，403/429/5xx = 被拦或服务端异常；这两种都值得换代理再试一次
if [ "$code" != "200" ] && [ -n "$PROXY" ]; then
  case "$code" in
    000|403|429|5??)
      raw2="$(try_fetch proxy)"
      code2="${raw2%%|*}"
      if [ "$code2" = "200" ] || [ "$code2" != "000" ]; then
        channel="proxy"; code="$code2"; ctype="${raw2#*|}"
      fi
      ;;
  esac
fi

# 抓取取证：run.sh 设了 AI_RADAR_FETCH_LOG 就逐次记账，供执行器精确计数
# （pi 没有 fetch_content 工具，抓取走本脚本，所以计数必须由脚本自己落账）
if [ -n "${AI_RADAR_FETCH_LOG:-}" ]; then
  printf '%s\t%s\t%s\n' "$URL" "$code" "$channel" >>"$AI_RADAR_FETCH_LOG" 2>/dev/null || true
fi

if [ "$code" != "200" ]; then
  echo "抓取失败：HTTP $code  ${URL}（通道 ${channel}${PROXY:+，已尝试代理}）" >&2
  exit 1
fi

# JSON 响应原样输出：API 数据被 HTML 去标签会直接干掉结构
case "$ctype" in
  *json*)
    head -c "$MAX" "$TMP"
    [ "$(wc -c <"$TMP")" -gt "$MAX" ] && printf '\n…（已截断到 %s 字节）\n' "$MAX"
    exit 0
    ;;
esac

python3 - "$TMP" "$MAX" <<'PY'
import html as htmllib
import re
import sys

path, max_chars = sys.argv[1], int(sys.argv[2])
with open(path, encoding="utf-8", errors="replace") as f:
    html = f.read()

title = ""
m = re.search(r"<title[^>]*>(.*?)</title>", html, re.I | re.S)
if m:
    title = re.sub(r"\s+", " ", m.group(1)).strip()

# 去掉不承载正文的块
html = re.sub(r"<(script|style|noscript|svg|iframe|nav|footer|aside)\b[^>]*>.*?</\1>",
              " ", html, flags=re.I | re.S)
body = re.sub(r"<!--.*?-->", " ", html, flags=re.S)

# 块级标签换行，行内标签直接去掉，避免单词粘连
body = re.sub(r"</?(p|div|br|li|h[1-6]|tr|section|article|header|blockquote)\b[^>]*>",
              "\n", body, flags=re.I)
body = re.sub(r"<[^>]+>", " ", body)
body = htmllib.unescape(body)

# 压缩空白：行内多空格合一，连续空行合一
lines = [re.sub(r"[ \t\u00a0]+", " ", ln).strip() for ln in body.splitlines()]
lines = [ln for ln in lines if ln]
text = "\n".join(lines)

if title:
    print(f"# {title}\n")
print(text[:max_chars])
if len(text) > max_chars:
    print(f"\n…（正文共 {len(text)} 字符，已截断到 {max_chars}）")
PY
