# AI Radar（macOS 版）

每天 08:30 自动跑一次的 AI 动态雷达：用 `pi` headless 模式做多角度检索，产出一份**有来源、有可信度标签、去过重**的中文日报，推到 GitHub，同时把《今日必读》压成一张飞书卡片发到群里。

源自 [SuTang-vain/ai-radar](https://github.com/SuTang-vain/ai-radar)（Linux/systemd 版），本项目是 macOS/launchd 改造版，核心改动：

| 原版 | 本版 |
|---|---|
| systemd timer | launchd（`com.gugu.ai-radar.plist`） |
| `notify-send` 桌面弹窗 | 飞书卡片（`lark-cli`，bot 身份） |
| `pi-web-access`（需 Exa/Jina key） | `pi-web-search`（DeepSeek 原生 Search API，复用现有 key，零额外成本） |
| `fetch_content` 工具 | `fetch.sh`（curl + 正文提取，自带调用记账） |
| GNU `timeout` / `date -d` / `find -delete` | `perl alarm` / `date -v-6d` / `find -exec rm` |

## 跑

```bash
./run.sh                      # 跑今天
./run.sh 2026-10-01           # 回填某天
./run.sh 2026-10-01 && ./push-feishu.sh 2026-10-01   # 单独补发飞书
./push-feishu.sh --dry-run    # 只看卡片 JSON，不发
./fetch.sh <url>              # 抓网页正文（agent 也用它）
./selftest.sh                 # 自检
tail -f logs/$(date +%F).log  # 实时日志
```

## 配置

`config.env`（已 gitignore）：

```
FEISHU_AS=bot                  # bot | user
FEISHU_RECEIVER_TYPE=user      # user（open_id）| chat（chat_id）
FEISHU_RECEIVER_ID=ou_xxx
REPORT_BASE_URL=https://github.com/<owner>/ai-radar/blob/main   # 留空则卡片不出按钮
```

环境变量覆盖：`AI_RADAR_MODEL`（默认 `deepseek/deepseek-flash`）、`AI_RADAR_THINKING`、
`AI_RADAR_TIMEOUT`（1800s）、`AI_RADAR_ATTEMPTS`（2）、`AI_RADAR_BUDGET_SEARCH/FETCH`（12/12）、
`AI_RADAR_CITATION_STRICT`、`AI_RADAR_NO_PUSH`、`AI_RADAR_NO_FEISHU`。

## 定时任务

```bash
cp com.gugu.ai-radar.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.gugu.ai-radar.plist
launchctl list | grep ai-radar                 # 看是否已加载
launchctl start com.gugu.ai-radar              # 立刻触发一次
launchctl unload ~/Library/LaunchAgents/com.gugu.ai-radar.plist   # 停掉
```

改了 plist 后必须 `unload` 再 `load` 才生效。机器睡眠错过 08:30 时，launchd 在唤醒后补跑一次。

## 组成

```
ai-radar/
├── prompt.md            # 情报编辑指令（检索预算 / 双标签 / 溯源 / 去重规则）
├── run.sh               # 执行器：跑 pi → 校验产物 → 取证 → git push → 飞书推送 → 清理
├── push-feishu.sh       # 日报 → 飞书卡片（lark-cli，失败重试 1 次）
├── build-card.py        # markdown 报告 → Card 2.0 JSON
├── fetch.sh             # 网页正文抓取（curl + 去标签），自带调用记账
├── selftest.sh          # 自检断言
├── config.env           # 本地配置（gitignore）
├── reports/             # 日报
├── logs/                # 运行日志 + session（gitignore，保留 30 天）
├── INDEX.md  THEMES.md  # 日报索引 / 跨天主题主线
└── com.gugu.ai-radar.plist
```

## 质量护栏（沿用原版设计）

- **每条必须有真实来源 URL**；断言带可信度（【已证实】/【厂商宣称】/【推测】）× 来源层级（【一手】/【二手】/【社媒线索】）双标签。
- **社媒只能当线索**：来自 X/HN/Reddit 的信息必须回溯一手来源并读正文核对，否则只能进《早期信号》。
- **零检索不算成功**：`run.sh` 从 session 里数真实 `web_search` 调用，少于 2 次即判无效报告并重试。
- **引文溯源**：报告里每条引用 URL 必须在本轮 session 中出现过；`AI_RADAR_CITATION_STRICT=1` 时不可溯源即失败。
- **一手取证**：标【一手】的断言行，其 URL 必须真被 `fetch.sh` 抓过。
- **取证结果写回报告**：头部写入来源通道与真实调用量，尾部追写「运行器取证」行，模型自述与实测不一致一眼可见。
- **推送失败不判任务失败**：日报是主要产出，飞书/git push 失败只记 WARN 并写进日志。
