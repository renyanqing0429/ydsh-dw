# -*- coding: utf-8 -*-
"""
第 3 周 子任务 4：SQL 安全校验 + Hive 执行器
----------------------------------------------
安全策略（对应任务书「大模型 SQL 不可控」难点）：
  1. 白名单校验：只放行单条 SELECT；
  2. 黑名单拦截：任何写操作 / DDL / PRAGMA 直接拒绝；
  3. 表名校验：FROM/JOIN 出现的表必须在已知 Schema 白名单内（防幻觉表名）。
执行：通过 docker exec 调用容器内 beeline（只读查询）。
"""
import re
import subprocess

FORBIDDEN = re.compile(
    r"\b(insert|update|delete|drop|alter|create|truncate|grant|revoke|use|"
    r"merge|load|export|set|add\s+jar|dfs|msck)\b", re.I)


def validate_sql(sql: str, known_tables: list) -> tuple:
    """返回 (ok, reason)。通过校验返回 (True, '')。"""
    sql_clean = sql.strip().rstrip(";").strip()

    if ";" in sql_clean:
        return False, "拒绝：包含多条语句（分号）"
    if not re.match(r"^\s*select\b", sql_clean, re.I):
        return False, "拒绝：不是 SELECT 查询"
    if FORBIDDEN.search(re.sub(r"'[^']*'", "", sql_clean)):  # 先剥掉字符串字面量再查关键字
        return False, "拒绝：包含被禁止的关键字（写操作/DDL）"

    used = set(re.findall(r"\b(?:from|join)\s+([\w.]+)", sql_clean, re.I))
    for t in used:
        name = t.split(".")[-1].lower()
        if name not in [k.lower() for k in known_tables]:
            return False, f"拒绝：引用了 Schema 白名单之外的表 `{t}`"
    return True, ""


def execute_sql(sql: str, container: str = "hive-server") -> str:
    """在 Hive 容器中执行只读 SQL，返回 beeline 输出（保留结果行）。"""
    proc = subprocess.run(
        ["docker", "exec", container, "sh", "-c",
         f"beeline -u jdbc:hive2://localhost:10000/ydsh_dwd -n hive "
         f"--outputformat=tsv2 --silent=true -e \"{sql.strip().rstrip(';')}\""],
        capture_output=True, text=True, timeout=300)
    out = proc.stdout + proc.stderr
    lines = [l for l in out.splitlines()
             if l and not l.startswith("SLF4J")
             and "beeline" not in l.lower()
             and "Connected to" not in l
             and "Driver:" not in l]
    return "\n".join(lines)


if __name__ == "__main__":
    from schema_extract import extract_schema
    tables = list(extract_schema().keys())
    good = "SELECT COUNT(1) AS n FROM dwd_order WHERE is_valid_order = 1"
    bad = "DROP TABLE dwd_order"
    print("合法 SQL 校验:", validate_sql(good, tables))
    print("危险 SQL 校验:", validate_sql(bad, tables))
    print("幻觉表名校验:", validate_sql("SELECT 1 FROM user_info", tables))
