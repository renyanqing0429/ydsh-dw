# -*- coding: utf-8 -*-
"""
第 3 周 子任务 4：Hive 表 Schema 自动抽取
------------------------------------------
从 sql/dwd/create_dwd.sql 的 DDL 中自动抽取 表名 / 表注释 / 字段名 / 字段注释，
生成供大模型理解的数据库元信息（避免把整份 DDL 塞进 Prompt，控制 token）。
运行：python src/nl2sql/schema_extract.py   （打印抽取结果）
"""
import os
import re

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DDL_PATH = os.path.join(BASE, "sql", "dwd", "create_dwd.sql")

# NL2SQL 常用核心表白名单（两张事实表 + 用户/门店/商品维度表）
CORE_TABLES = ["dwd_order", "dwd_order_item", "dim_user", "dim_store", "dim_product"]


def extract_schema(ddl_path: str = DDL_PATH) -> dict:
    """解析 DDL → {table_name: {"comment": ..., "columns": {col: comment}}}"""
    with open(ddl_path, encoding="utf-8") as f:
        text = f.read()

    schema = {}
    for block in re.finditer(
            r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([\w.]+)\s*\((.*?)\)\s*COMMENT\s*'([^']*)'",
            text, re.S | re.I):
        full_name, body, tbl_comment = block.group(1), block.group(2), block.group(3)
        table = full_name.split(".")[-1]
        columns = {}
        for line in body.splitlines():
            m = re.match(r"\s*(\w+)\s+\w+.*?COMMENT\s+'([^']*)'", line)
            if m and m.group(1).lower() not in ("partitioned", "stored"):
                columns[m.group(1)] = m.group(2)
        schema[table] = {"comment": tbl_comment, "columns": columns}
    return schema


def render_schema_desc(schema: dict, tables: list = None) -> str:
    """把 Schema 渲染成 Prompt 友好的紧凑文本。"""
    tables = tables or CORE_TABLES
    lines = []
    for t in tables:
        info = schema.get(t)
        if not info:
            continue
        cols = ", ".join(f"{c}({cm})" for c, cm in info["columns"].items())
        lines.append(f"- {t}：{info['comment']}。字段：{cols}")
    return "\n".join(lines)


if __name__ == "__main__":
    s = extract_schema()
    print(render_schema_desc(s))
