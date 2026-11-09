# -*- coding: utf-8 -*-
"""
第 3 周 子任务 4：NL2SQL 主链路（自然语言 → SQL → 执行 → 返回结果）
--------------------------------------------------------------------
运行：
  python src/nl2sql/nl2sql.py "广东省上月销售额是多少？"          # 端到端
  python src/nl2sql/nl2sql.py --prompt "销量最高的前5个品类"      # 只看 Prompt（dry-run）
  python src/nl2sql/nl2sql.py --demo                            # 验收问题闭环演示
有 API Key 时走 大模型生成 SQL → 校验 → 执行；无 Key 时进入 dry-run，
用 few-shot 示例 SQL 演示「校验 → 执行 → 结果」闭环。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "llm"))

from executor import execute_sql, validate_sql      # noqa: E402
from prompt import build_prompt                     # noqa: E402
from schema_extract import extract_schema, render_schema_desc  # noqa: E402

# 任务书验收问题 → 参考 SQL（演示闭环 + 作为 few-shot 对照）
DEMO_QUESTIONS = {
    "广东省上月销售额是多少？":
        "SELECT ROUND(SUM(o.pay_amount_valid),2) AS sales FROM dwd_order o "
        "JOIN dim_store s ON o.store_id = s.store_id "
        "WHERE s.province = '广东省' AND o.order_month = '2024-12'",
    "销量最高的前 5 个品类？":
        "SELECT p.category, SUM(i.quantity) AS total_qty FROM dwd_order_item i "
        "JOIN dim_product p ON i.product_id = p.product_id "
        "GROUP BY p.category ORDER BY total_qty DESC LIMIT 5",
}


def ask(question: str, run_sql: bool = True) -> dict:
    """完整链路：Schema → Prompt → LLM 生成 SQL（或 dry-run）→ 校验 → 执行。"""
    schema_desc = render_schema_desc(extract_schema())
    prompt = build_prompt(question, schema_desc)

    try:
        from llm_config import chat, get_llm_config
        cfg = get_llm_config()
        has_key = cfg.platform != "none"
    except Exception:
        has_key = False

    result = {"question": question, "mode": "llm" if has_key else "dry-run",
              "prompt_chars": len(prompt)}

    if has_key:
        sql = chat([{"role": "user", "content": prompt}], temperature=0.0)
        sql = sql.strip().strip("```").strip()
        result["sql"] = sql
    else:
        print("[dry-run] 未配置 API Key，无法由大模型生成 SQL。")
        print("生成的 Prompt 已就绪（可在有 Key 后直接投喂）：\n")
        print(prompt)
        result["sql"] = None

    if result.get("sql"):
        ok, reason = validate_sql(result["sql"], list(extract_schema().keys()))
        result["validated"] = ok
        if not ok:
            result["error"] = reason
            return result
        if run_sql:
            result["rows"] = execute_sql(result["sql"])
    return result


def demo():
    """验收问题闭环演示：校验器自检 + 参考 SQL 实测执行。"""
    from schema_extract import extract_schema
    tables = list(extract_schema().keys())
    print("== 1. Schema 抽取 ==")
    print(render_schema_desc(extract_schema())[:400], "...\n")

    print("== 2. SQL 安全校验器自检 ==")
    print("  合法 SELECT:", validate_sql(DEMO_QUESTIONS["广东省上月销售额是多少？"], tables)[0])
    print("  危险 DROP  :", validate_sql("DROP TABLE dwd_order", tables))
    print("  幻觉表名   :", validate_sql("SELECT 1 FROM user_info", tables), "\n")

    print("== 3. 验收问题实测执行 ==")
    for q, sql in DEMO_QUESTIONS.items():
        print(f"\n问：{q}")
        print(f"SQL：{sql}")
        print("结果：")
        print(execute_sql(sql))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] == "--demo":
        demo()
    elif args[0] == "--prompt":
        print(build_prompt(args[1]))
    else:
        r = ask(" ".join(args))
        print(f"\n[mode={r['mode']}]")
        if r.get("error"):
            print("SQL 校验失败：", r["error"])
        elif r.get("sql"):
            print("SQL：", r["sql"])
            print("结果：\n", r.get("rows"))
