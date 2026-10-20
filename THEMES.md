# AI RADAR — 主题主线

跨天合并同一主题的演进，避免日报每天重复堆叠。由每日任务自动维护（`run.sh` → prompt.md 第 6 步）。

格式约定（agent 遵循）：

```markdown
## 主题：<主题名>
- 状态：关注中 | 已收敛 | 长期跟踪
- 时间线（最新在最上，最多 12 条）：
  - 2026-10-15 — <事实>【标签】([来源](url))
```

---

## 主题：前沿模型价格战与"每任务成本"选型

- 状态：长期跟踪
- 时间线（最新在最上）：
  - 2026-10-20 — Artificial Analysis 榜新增"每任务成本"列：Claude Opus 5.5 (max) 58 分/$5.98、Sonnet 5.5 (xhigh) 52 分/$2.01、Gemini 4 Argon (high) 53 分/$1.99、GPT-6.1 Sol (xhigh) 51 分/$0.39、(high) 50 分/$0.32【已证实】([来源](https://artificialanalysis.ai/leaderboards/models))
  - 2026-10-20 — 判断：分数差 8 分对应成本差 18 倍，"最强"与"最划算"首次能在同一列里算清；采购继续按每任务成本走，不按分数走【推测】
  - 2026-10-19 — Santander×NVIDIA：从通用大模型转向小模型特化，选定实验中单次交互 €5→约 €0.03；官方强调"cost per intelligence output"是核心指标【厂商宣称】([来源](https://www.pymnts.com/news/banking/2026/santander-turns-to-nvidia-to-build-new-ai-banking-capabilities/))
  - 2026-10-13 — Gemini 4 Argon 全球开放，$2/$10 促销价入场，12-01 起回到 $4/$20，仅 API 付费层可用【已证实】([来源](https://blog.google/innovation-and-ai/models-and-research/gemini-models/introducing-gemini-4-argon/))
  - 2026-10-20 — 判断：采购方的预算模型（单价×调用次数）比模型选择更早出错；促销期定价不能当长约基准【推测】

## 主题：OpenRouter 用量格局与国产模型份额

- 状态：长期跟踪
- 时间线（最新在最上）：
  - 2026-10-20 — OpenRouter AA 榜（through 10-19）：Opus 5.5 57.6 / Sonnet 5.5 56.0 / Fable 5.1 53.4 / Qwen3.8 Max 53.4 / GPT-6 Astra 52.7 / Gemini 4 Argon 52.6；应用 token 日榜 Claude Code 1.69T 仍居首【已证实】([来源](https://openrouter.ai/rankings))
  - 2026-10-19 — 周 token 164.0T，环比 -4.65%，11 周连涨后首次下滑；中国模型 79.18T vs 美国 17.36T，连续 25 周领先【未获一手证实】([来源](https://news.iresearch.cn/content/202610/568437.shtml))
  - 2026-10-19 — DeepSeek V4.1 Flash 连续两周第一（32.8T，-20%），但属旧快照流量迁移到 1017 新快照【未获一手证实】([来源](https://flash.jin10.com/detail/20261019103603399800))
  - 2026-10-19 — Step 5 Preview 升至第三（11.5T，+30%）；Claude Opus 5.5 第七（6.18T，+23%）【未获一手证实】([来源](https://news.iresearch.cn/content/202610/568437.shtml))
  - 2026-10-20 — 判断：价格弹性接近饱和，可靠性（DeepSeek 10 月 5 次事故）开始比单价更能决定留存【推测】

## 主题：Anthropic 产品化路径（Claude Code 为收入主力）

- 状态：关注中
- 时间线（最新在最上）：
  - 2026-10-20 — Claude Code 2.1.304（10-19）主动加"恢复旧会话会吃掉 5 小时额度"的 Pro/Max 警告；2.1.302（10-16）fork 子 agent 默认开启、`claude -p` 在第三方 provider/遥测关闭/全新安装下默认回 default 权限模式【已证实+二手】([来源](https://code.claude.com/docs/en/changelog))
  - 2026-10-19 — Claude Code 2.1.304：/auto-mode-setup、Code Review 三档、mods 工具权限事件【已证实】([来源](https://code.claude.com/docs/en/changelog))
  - 2026-10-20 — 判断：AA 智能指数前三均为 Claude（57.6/56.0/53.4），而 OpenRouter 请求份额仅 4.7%，但应用 token 榜 Claude Code 以 1.69T 居首——收入走产品不走裸 API【已证实+推测】([来源](https://openrouter.ai/rankings))

## 主题：推理成本曲线与算力投入

- 状态：长期跟踪
- 时间线（最新在最上）：
  - 2026-10-16/19 — Anthropic×Google TPU（Project North Star）：约 $600 亿、约 1.5GW，$420 亿优先债由 Broadcom 担保 + $180 亿次级，Blackstone 次级档票息 >10%（四个月前同类 8.5%）【二手】([来源](https://en.ilsole24ore.com/art/anthropic-debt-60-billion-google-and-blackstone-chips-returns-over-10-per-cent-AJ1kwmmB))
  - 2026-10-20 — AA 每任务成本最低头名是 K2 Horizon 375B A23B 与 Gemma 4 31B（非前沿旗舰）；输出速度头名 Celeris-1【已证实】([来源](https://artificialanalysis.ai/leaderboards/models))
  - 2026-10-20 — Nscale 与 Anthropic 洽谈约 $450 亿 / 460MW 算力，双方未确认【二手】([来源](https://www.digitaltoday.co.kr/en/view/116618/nscale-in-talks-with-anthropic-on-additional-45-billion-computing-deal))
  - 2026-10-20 — Modal $7.5 亿 D 轮 @ $157.5 亿投后，自称 9 月年化收入破 $10 亿（未审计）【二手】([来源](https://aifundingtracker.com/ai-funding-hits-2-42b-as-modal-lands-750m-at-15-75b-oct-12-oct-18-2026/))
  - 2026-09-22 — Epoch AI：固定分数下成本每季度降 47%（≈13×/年），五基准一致（原始分析发布日期）【已证实】([来源](https://www.stateof.ai/2026-explore/answers/is-ai-inference-getting-cheaper))
  - 2026-10-20 — 判断：单价下降不等于账单下降，agent 单任务几十到上百次调用会吃掉降幅【推测】

## 主题：EU AI Act 执法化

- 状态：长期跟踪
- 时间线（最新在最上）：
  - 2026-10-20 — Art.50 透明度/机器可读标识义务定于 2026-12-02 生效（宽限期由 6 个月缩到 3 个月），同日新增"脱衣"类与 CSAM 禁止性行为；程序条例 2026/1755 规定五年处罚时效与临时措施【二手】([来源](https://www.stephensonharwood.com/post/102msaw/eu-digital-omnibus-deal-simplification-of-ai-act-and-postponed-deadlines/))
  - 2026-10-14 — 首个协调标准 EN 18286:2026（AI 质量管理体系）刊登 OJ，给 Art.17 QMS 推定符合【二手】([来源](https://www.timelex.eu/en/blog/ai-omnibus-deal-what-survived-trilogue))
  - 2026-08-29 — AI Office 首批 RFI：安全/containment、独立外部评估、上线后监测；另向 30+ 家发训练数据透明度问询【已证实】([来源](https://www.matheson.com/insights/the-european-commissions-first-use-of-ai-act-enforcement-powers/))
  - 2026-07-27 — Regulation (EU) 2026/1744 生效：Annex III 高风险义务推迟至 2027-12-02，Annex I 至 2028-08-02，义务本身未删【二手】
  - 2026-10-20 — 判断：合规资源该从"符合性文档"移向"运行时监测"，罚则上限 €1500 万或全球营业额 3%【推测】

## 主题：榜单公信力与模型漂移监测

- 状态：关注中
- 时间线（最新在最上）：
  - 2026-10-20 — LMArena W42：Gemini 4 Argon 1525 守第一，但仅领先 Opus 5.5（1507）18 分、CI ±9/±8、票数 4,892 vs 8 万+；前十 Claude 占 7 席；Opus 5.5 Max 首登 Agent Arena 第一（净提升 15.53%、工具幻觉 0.37%）、WebDev 1813【二手】([来源](https://www.ithome.com/1/014/865.htm))
  - 2026-10-20 — 判断：通用对话 Elo 已进入"拥挤在误差内"阶段，agent/前端榜才有信息量【推测】
  - 2026-10-16 — LiveNerf：Opus 5.5 前 10 天 0.584±0.036 vs 后 10 天 0.592±0.037（读平）；Nerf Bench 105.8%（在 90–110% 正常区间）【二手】
  - 2026-10-12/19 — Muse Wonder 高分但 lava lamp 测试只画出红圆柱，Alexandr Wang 承认未针对 3D 任务训练；benchmaxxing 质疑扩散【二手】([来源](https://www.sohu.com/a/1089644152_114877))
  - 2026-10-14 — 开发者投诉 Gemini 多步推理与编码退化，Google 称总体指标仍在改善【二手】([来源](https://www.webpronews.com/google-gemini-ai-faces-backlash-over-declining-reasoning-and-coding-performance/))
  - 2026-10-20 — LiveNerf 用预注册面板每 10 天发布漂移结果（含空结果），实测 MDE≈6.6 分；"降智"争论首次有可证伪测法【二手】([来源](https://aiwiki.ai/wiki/livenerf))
  - 2026-10-20 — 判断：agent 分数已是"模型+脚手架+重试预算"的复合量，跨榜横比意义下降【推测】

## 主题：开放权重生态（中美两侧）

- 状态：关注中
- 时间线（最新在最上）：
  - 2026-10-15 — NVIDIA Nemotron 3.5 Super VL（120B，开放权重，官方称同级快 5×、约 26T token 训练）与 Bolt 74B-A9B（原生 2-bit 进 24GB，跑 RTX/DGX Spark）、Bolt E4B 4GB 定于 10-23；生态含 Scale AI/EY/Perplexity/Salesforce/CrowdStrike【已证实】([来源](https://blogs.nvidia.com/blog/nemotron-3-5-super-vl/))
  - 2026-10-20 — 判断：开放权重竞争从"刷榜"转向"装得下"，本地 agent 门槛从算力预算变成显存预算【推测】
  - 2026-10-17 — DeepSeek V4.1 Flash-1017 刷新，MIT 许可、价格不变【未获一手证实】([来源](https://flash.jin10.com/detail/20261019103603399800))
  - 2026-10-15 — Meta Muse Spark Open 开放权重 816B/42B active、1M 上下文，自定义许可非 OSI；独立评测尚缺（官方 blog 本轮抓取失败）【未获一手证实】([来源](https://huggingface.co/blog/meta-muse-spark-open))
  - 2026-10-19 — MiniMax M3.1 Flash 上线，主打约 3× 速度、约 70% 降价【二手】([来源](https://news.qq.com/rain/a/20261019A0CWC400))

## 主题：中国 AI 技术出口管制与智能信息服务立法

- 状态：关注中
- 时间线（最新在最上）：
  - 2026-10-16 — 商务部、科技部《中国禁止出口限制出口技术目录》修订征求意见（至 11-15）：新增 40 项中 AI 相关 23 项，覆盖大模型、智能体、算力集群；限制的是技术跨境转移（含海外本地化部署），API 调用/SaaS/网页交互/已开源技术被明确排除；同日启动出口前登记【二手】([来源](https://www.aastocks.com/tc/stocks/news/aafn-con/NOW.1549705/china-policy/AAFN))
  - 2026-10-10 — 《电信和互联网生成式人工智能服务安全分级指南》团体标准宣贯，覆盖开源私有化部署、API 接入第三方模型、云上部署的定级规则【二手】([来源](https://gk.gkzhan.com/news/195590.html))
  - 2026-10-20 — 判断：自建/本地化部署的跨境合规成本上升，"调 API 出海"仍是成本最低路径；与 EU 12-02 标识义务形成双向压力【推测】

## 主题：Agent 订阅额度与计费透明度

- 状态：关注中
- 时间线（最新在最上）：
  - 2026-10-19 — Claude Code issue #103406（已关闭）：多 agent 会话 15 分钟内 195 次 Opus 5.5 请求、3.1M cache read、$4.88，仅改 32 行代码，5 小时额度耗尽；周额度已达 79%【已证实】([来源](https://github.com/anthropics/claude-code/issues/103406))
  - 2026-10-19 — Claude Code 2.1.304 主动新增 Pro/Max "恢复旧会话会消耗 5 小时额度"的警告，厂商侧承认配额焦虑【已证实】([来源](https://code.claude.com/docs/en/changelog))
  - 2026-10-19 — openai/codex #54910 汇总周额度异常蒸发（#54704 一小时 24%→96%、#54677 38 秒 +67 点）；用户称 Pro 200 将于 10-30 减半至 10×，官方未确认【社媒线索】([来源](https://github.com/openai/codex/issues/54910))
  - 2026-10-20 — 判断：竞争从"能力"移到"额度表"，订阅制信任将由 telemetry 与计费透明度决定，而不是口碑【推测】
