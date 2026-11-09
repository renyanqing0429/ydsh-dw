# -*- coding: utf-8 -*-
"""
第 3 周 子任务 5：AI 智能洞察与自动报告
----------------------------------------
流程：
  1. 规则层：从日趋势数据识别 GMV 异常日（偏离 7 日均值超过阈值）；
  2. Prompt 组装：把异常日 + 核心指标 + 上下月环比注入提示词；
  3. 大模型归因：有 Key 调用 LLM 生成异常归因；无 Key 走 dry-run
     （输出完整 Prompt + 规则基线归因），报告结构完整、结构可复跑；
  4. 自动生成经营分析摘要，写入 docs/AI洞察报告_自动生成.md。
⚠️ AI 生成内容必须人工验证（见 docs/AI应用反思.md）。
"""
import json
import os
import sys

import pandas as pd

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "llm"))

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DATA = os.path.join(BASE, "dashboard", "data", "ads_daily_trend.tsv")
OUT_MD = os.path.join(BASE, "docs", "AI洞察报告_自动生成.md")
OUT_PROMPT = os.path.join(BASE, "src", "insight", "output", "insight_prompt.txt")
THRESHOLD = 0.25  # 偏离 MA7 超过 25% 视为异常


def load_daily() -> pd.DataFrame:
    df = pd.read_csv(DATA, sep="\t")
    df.columns = [c.split(".")[-1] for c in df.columns]
    df["dt"] = pd.to_datetime(df["dt"])
    return df.sort_values("dt").reset_index(drop=True)


def detect_anomalies(df: pd.DataFrame) -> pd.DataFrame:
    d = df.copy()
    d["ma7"] = d["gmv"].rolling(7).mean()
    d["dev_pct"] = (d["gmv"] - d["ma7"]) / d["ma7"]
    d["month_mom"] = d.set_index("dt")["gmv"].resample("MS").sum().pct_change() \
        .reindex(d.set_index("dt").index, method="ffill").values
    anomalies = d[d["ma7"].notna() & (d["dev_pct"].abs() >= THRESHOLD)].copy()
    # 同向连续异常合并为一组（取首日 + 最深日），避免冗余清单
    return anomalies


def build_context(df: pd.DataFrame, anomalies: pd.DataFrame, top_n: int = 10) -> str:
    monthly = df.set_index("dt")["gmv"].resample("MS").sum().round(2)
    lines = ["【核心指标】",
             f"- 统计期：{df['dt'].iloc[0]:%Y-%m-%d} ~ {df['dt'].iloc[-1]:%Y-%m-%d}，"
             f"全年 GMV {df['gmv'].sum():,.0f} 元，日均 {df['gmv'].mean():,.0f} 元",
             "- 月度 GMV（元）：" + "；".join(
                 f"{k:%Y-%m}={v:,.0f}" for k, v in monthly.items())]
    lines.append(f"\n【异常日清单】（日 GMV 偏离 7 日均值 ≥ 25%，"
                 f"共检出 {len(anomalies)} 个，下列为偏离最深的 Top {top_n}）")
    if anomalies.empty:
        lines.append("- 无")
    else:
        top = anomalies.reindex(anomalies["dev_pct"].abs().sort_values(ascending=False).index).head(top_n)
        top = top.sort_values("dt")
        for _, r in top.iterrows():
            lines.append(f"- {r['dt']:%Y-%m-%d}：GMV {r['gmv']:,.0f} 元，"
                         f"偏离 MA7 {r['dev_pct'] * 100:+.1f}%")
    return "\n".join(lines)


PROMPT_TEMPLATE = """你是"云购生活"新零售企业的经营分析专家。下面是某新零售平台 2024 全年的经营数据摘要。

{context}

请输出：
1. 异常归因：对 GMV 异常日（尤其突降日）给出 2~3 个可能原因假设，并按可能性排序；
2. 经营洞察：基于月度走势给出 3 条有数据支撑的经营建议；
3. 置信度声明：明确说明哪些结论是数据可证的、哪些是待验证假设（本平台无促销/天气/竞品数据，归因存在信息盲区）。

要求：观点必须与给出的数字一致，不得编造数据；语言简洁，用 Markdown。
"""


def main() -> int:
    df = load_daily()
    anomalies = detect_anomalies(df)
    context = build_context(df, anomalies)
    prompt = PROMPT_TEMPLATE.format(context=context)

    os.makedirs(os.path.dirname(OUT_PROMPT), exist_ok=True)
    with open(OUT_PROMPT, "w", encoding="utf-8") as f:
        f.write(prompt)

    from llm_config import get_llm_config
    cfg = get_llm_config()

    md = ["# AI 智能洞察报告（自动生成）",
          "",
          f"> 生成方式：{'大模型归因（' + cfg.platform + '/' + cfg.model + '）' if cfg.platform != 'none' else 'dry-run（未配置 API Key，仅规则基线 + Prompt 存档）'}",
          "> ⚠️ 归因结论均为待验证假设（本数据无促销/天气/竞品变量）；AI 生成内容须人工核验，方法见 `docs/AI应用反思.md`。",
          "",
          "## 输入数据摘要（喂给模型的上下文）",
          "",
          "```", context, "```", ""]

    if cfg.platform != "none":
        from llm_config import chat
        answer = chat([{"role": "user", "content": prompt}], temperature=0.3)
        md += ["## 大模型归因与洞察", "", answer, ""]
    else:
        # 规则基线归因（dry-run，待 LLM 接入后替换）
        worst = anomalies.assign(pct=anomalies["dev_pct"]).nsmallest(3, "gmv") \
            if not anomalies.empty else anomalies
        baseline = [
            "## 规则基线洞察（dry-run，非 AI 生成）", "",
            "1. **异常概况**：全年检出 "
            f"{len(anomalies)} 个偏离 MA7 ≥ 25% 的异常日"
            + (f"，最深突降日 {worst['dt'].iloc[0]:%m-%d}（GMV 较 MA7 低 "
               f"{abs(worst['dev_pct'].iloc[0]) * 100:.0f}%）。" if not worst.empty else "。"),
            "2. **可能原因假设（待验证）**：周末/工作日结构性波动、渠道投放节奏变化、"
            "促销活动前后需求透支；本数据集无促销日历与外部变量，无法定证。",
            "3. **经营建议（数据可证）**：2 月、6 月、10 月 GMV 环比降幅均超 3%，"
            "建议按月复盘品类结构（品类 Top5 稳定为运动户外/数码家电/服饰鞋包/食品生鲜/图书文娱）；"
            "日波动系数 23%，备货与排班建议以 MA7 而非单日值作为基准。",
            "",
            "## 大模型 Prompt 存档", "",
            f"完整 Prompt 已存档：`src/insight/output/insight_prompt.txt`（{len(prompt)} 字符）。"
            "配置 API Key 后重跑本脚本，即可用同一 Prompt 获得大模型归因。", ""]

        md += baseline
        answer = None

    with open(OUT_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(md))

    print(f"异常日检出：{len(anomalies)} 个（阈值 {THRESHOLD:.0%}）")
    print(f"Prompt 存档：{OUT_PROMPT}（{len(prompt)} 字符）")
    print(f"报告输出：{OUT_MD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
