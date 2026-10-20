#!/usr/bin/env python3
"""把 reports/YYYY-MM-DD.md 压成一张飞书 Card 2.0 卡片 JSON。

只取《今日必读》+ 运行器取证，正文留在 GitHub 上，靠按钮跳转。
用法：build-card.py <report.md> [--report-url URL] [--themes-url URL]
输出：卡片的 to-JSON 串（stdout），供 push-feishu.sh 塞给 lark-cli。
"""
import json
import re
import sys

MAX_ITEMS = 5          # 今日必读最多取 5 条，再多群里就是刷屏
SUMMARY_CHARS = 110    # 每条摘要上限，保证卡片一屏能看完

# 标签配色：可信度三档 + 来源层级三档，同色同义
TAG_COLORS = {
    "已证实": "green",
    "厂商宣称": "orange",
    "推测": "grey",
    "一手": "green",
    "二手": "grey",
    "社媒线索": "orange",
}

BOLD_RE = re.compile(r"\*\*(.+?)\*\*")
TAG_RE = re.compile(r"【([^】]+)】")
LINK_RE = re.compile(r"\(\[[^\]]*\]\([^)]*\)\)")   # 尾部 ([来源](url))


def die(msg: str) -> None:
    print(f"build-card: {msg}", file=sys.stderr)
    sys.exit(1)


def section(lines: list[str], title_prefix: str) -> list[str]:
    """取出二级标题以 title_prefix 开头那一节的内容行。"""
    out, inside = [], False
    for line in lines:
        if line.startswith("## "):
            inside = line[3:].strip().startswith(title_prefix)
            continue
        if inside:
            out.append(line)
    return out


def parse_headlines(lines: list[str]) -> list[dict]:
    """解析《今日必读》的 - 开头条目：结论 / 标签 / 摘要 / 来源。"""
    items = []
    for raw in section(lines, "今日必读"):
        line = raw.strip()
        if not line.startswith("- "):
            continue
        body = line[2:].strip()

        # 来源链接：取最后一个 markdown 链接
        src_name, src_url = "", ""
        m = re.search(r"\[([^\]]+)\]\((https?://[^)]+)\)", body)
        if m:
            src_name, src_url = m.group(1), m.group(2)

        bold = BOLD_RE.search(body)
        title = bold.group(1).strip() if bold else body[:60]

        tags = TAG_RE.findall(body)
        tags = [t for t in tags if t in TAG_COLORS]        # 丢掉正文里非标签的【】

        summary = LINK_RE.sub("", body)
        summary = BOLD_RE.sub("", summary)
        summary = TAG_RE.sub("", summary).strip()
        summary = re.sub(r"\s+", " ", summary)
        if len(summary) > SUMMARY_CHARS:
            summary = summary[:SUMMARY_CHARS].rstrip() + "…"

        if not title:
            continue
        items.append(
            {"title": title, "tags": tags, "summary": summary,
             "src_name": src_name, "src_url": src_url}
        )
        if len(items) >= MAX_ITEMS:
            break
    return items


def parse_runner_evidence(lines: list[str]) -> str:
    """取『运行器取证』那一行的统计，没有就返回空串。"""
    for line in lines:
        if "运行器取证" in line:
            m = re.search(
                r"web_search\s*(\d+)\s*次\s*/\s*(?:fetch_content|抓取正文)\s*(\d+)\s*次",
                line,
            )
            if m:
                return f"检索 {m.group(1)} 次 · 抓取 {m.group(2)} 次"
    return ""


def tag_html(tags: list[str]) -> str:
    if not tags:
        return ""
    painted = [
        f"<font color='{TAG_COLORS[t]}'>【{t}】</font>" for t in tags if t in TAG_COLORS
    ]
    return " ".join(painted)


def build_markdown(items: list[dict]) -> str:
    blocks = []
    for i, it in enumerate(items, 1):
        head = f"**{i}. {it['title']}**"
        line2 = tag_html(it["tags"])
        if it["summary"]:
            line2 = f"{line2} {it['summary']}" if line2 else it["summary"]
        block = [head]
        if line2:
            block.append(line2)
        if it["src_url"]:
            block.append(f"[{it['src_name']}]({it['src_url']})")
        blocks.append("\n".join(block))
    return "\n\n".join(blocks)


def main() -> None:
    args = sys.argv[1:]
    if not args:
        die("缺少报告路径参数")
    report_path = args[0]

    report_url = themes_url = ""
    for i, a in enumerate(args):
        if a == "--report-url" and i + 1 < len(args):
            report_url = args[i + 1]
        if a == "--themes-url" and i + 1 < len(args):
            themes_url = args[i + 1]

    try:
        with open(report_path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        die(f"读不到报告：{e}")

    lines = text.splitlines()
    date = ""
    for line in lines:
        if line.startswith("# AI Radar "):
            date = line.replace("# AI Radar", "").strip()
            break
    if not date:
        m = re.search(r"(\d{4}-\d{2}-\d{2})", report_path)
        date = m.group(1) if m else ""

    items = parse_headlines(lines)
    if not items:
        die("报告里没解析出《今日必读》条目（章节缺失或格式异常）")

    evidence = parse_runner_evidence(lines)
    subtitle_parts = [f"{len(items)} 条必读"]
    if evidence:
        subtitle_parts.append(evidence)
    subtitle = " · ".join(subtitle_parts)

    buttons = []
    if report_url:
        buttons.append({
            "tag": "button",
            "text": {"tag": "plain_text", "content": "查看完整日报"},
            "type": "primary_filled",
            "width": "fill",
            "behaviors": [{"type": "open_url", "default_url": report_url}],
        })
    if themes_url:
        buttons.append({
            "tag": "button",
            "text": {"tag": "plain_text", "content": "主题主线"},
            "type": "default",
            "behaviors": [{"type": "open_url", "default_url": themes_url}],
        })

    elements = [
        {"tag": "markdown", "content": build_markdown(items)},
        {"tag": "hr"},
    ]
    if buttons:
        elements.append({
            "tag": "column_set",
            "flex_mode": "bisect",
            "horizontal_spacing": "small",
            "columns": [
                {"tag": "column", "width": "weighted", "weight": 1,
                 "elements": [b]}
                for b in buttons
            ],
        })
    else:
        elements.append({
            "tag": "markdown",
            "content": "<font color='grey'>完整报告见项目 reports/ 目录</font>",
        })

    card = {
        "schema": "2.0",
        "config": {"update_multi": True, "width_mode": "default"},
        "header": {
            "title": {"tag": "plain_text", "content": f"AI Radar · {date}"},
            "subtitle": {"tag": "plain_text", "content": subtitle},
            "template": "blue",
        },
        "body": {"direction": "vertical", "elements": elements},
    }
    print(json.dumps(card, ensure_ascii=False))


if __name__ == "__main__":
    main()
