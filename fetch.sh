#!/usr/bin/env bash
# 抓网页正文，给 pi 的 bash 工具用（本机没有 fetch_content 工具，走 curl 兜底）。
#
#   ./fetch.sh <url> [max_chars]     # 默认输出前 12000 字符
#
# 退出码：0 成功；1 抓取失败；2 参数错误
# 输出：标题 + 正文纯文本（已去 script/style/标签、压缩空白）
set -uo pipefail

URL="${1:-}"
MAX="${2:-12000}"
[ -n "$URL" ] || { echo "用法: $0 <url> [max_chars]" >&2; exit 2; }

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
TMP="$(mktemp -t airadar-fetch)"
trap 'rm -f "$TMP"' EXIT

code="$(curl -sL --compressed --max-time 45 \
  -A "$UA" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Accept-Language: en-US,en;q=0.9,zh-CN;q=0.8' \
  -w '%{http_code}' -o "$TMP" "$URL" 2>/dev/null)"

# 抓取取证：run.sh 设了 AI_RADAR_FETCH_LOG 就逐次记账，供执行器精确计数
# （pi 没有 fetch_content 工具，抓取走本脚本，所以计数必须由脚本自己落账）
if [ -n "${AI_RADAR_FETCH_LOG:-}" ]; then
  printf '%s\t%s\n' "$URL" "$code" >>"$AI_RADAR_FETCH_LOG" 2>/dev/null || true
fi

if [ "$code" != "200" ]; then
  echo "抓取失败：HTTP $code  $URL" >&2
  exit 1
fi

python3 - "$TMP" "$MAX" <<'PY'
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

# HTML 实体
import html as htmllib
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
