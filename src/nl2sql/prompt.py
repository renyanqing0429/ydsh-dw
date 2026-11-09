# -*- coding: utf-8 -*-
"""
第 3 周 子任务 4：NL2SQL 系统提示词（Prompt 设计）
--------------------------------------------------
设计要点（任务书要求）：
  1. 注入 Schema 元信息，约束模型只能用真实存在的表名/字段名；
  2. 强制只读（只允许 SELECT），禁止 INSERT/UPDATE/DELETE/DDL；
  3. 固定口径（GMV = SUM(pay_amount_valid)，只算有效订单）；
  4. few-shot 示例对齐任务书验收问题。
"""

SCHEMA_FALLBACK = """\
- dwd_order：订单事实表（订单粒度）。字段：order_id(订单ID主键), user_id(用户ID), store_id(门店ID), order_timestamp(下单时间戳 yyyy-MM-dd HH:mm:ss), order_month(下单月份 yyyy-MM), pay_amount(支付金额), discount_amount(优惠金额), pay_type(支付方式), order_status(订单状态), channel(下单渠道), is_valid_order(是否有效订单 1=是), pay_amount_valid(有效支付金额,无效订单置0,GMV主口径), discount_amount_valid(有效优惠金额)
- dwd_order_item：订单明细事实表（订单×商品粒度）。字段：order_id(订单ID), product_id(商品ID→dim_product), quantity(购买数量), unit_price(成交单价), pay_amount(明细实付金额)
- dim_user：用户维度表。字段：user_id(用户ID主键), user_name(用户名), gender(性别), age(年龄), age_band(年龄段), province(省份), city(城市), register_date(注册日期), member_level(会员等级)
- dim_store：门店维度表。字段：store_id(门店ID主键), store_name(门店名称), province(省份), city(城市), district(区县), open_date(开业日期), area(门店面积平米)
"""

SYSTEM_PROMPT = """你是 Hive SQL 专家，负责把用户的自然语言问题转换为可在 Hive 上执行的查询语句。

可用表 Schema（表名、字段名、字段注释）：
{schema_desc}

数据口径与硬性规则：
1. 只允许生成一条 SELECT 语句；严禁 INSERT / UPDATE / DELETE / DROP / ALTER / CREATE / USE 等任何写操作或 DDL。
2. 只能使用上面 Schema 中出现的表名和字段名，不得编造。
3. GMV / 销售额统一口径：SUM(dwd_order.pay_amount_valid)（有效支付金额，无效订单已置 0）；订单量用 COUNT(DISTINCT order_id)。
4. 时间词用 order_month（格式 yyyy-MM，数据仅覆盖 2024 年）或 SUBSTR(order_timestamp,1,10) 表达，注意 Hive 兼容写法。
5. 金额用 ROUND(x, 2) 保留 2 位小数。
6. 输出格式：只输出 SQL 本身（一条 SELECT 语句，不要解释、不要 markdown 标记、不要分号）。

示例（few-shot）：
问：广东省 2024 年 12 月销售额是多少？
SELECT ROUND(SUM(o.pay_amount_valid),2) AS sales FROM dwd_order o JOIN dim_store s ON o.store_id = s.store_id WHERE s.province = '广东省' AND o.order_month = '2024-12'

问：销量最高的前 5 个品类？
SELECT p.category, SUM(i.quantity) AS total_qty FROM dwd_order_item i JOIN dim_product p ON i.product_id = p.product_id GROUP BY p.category ORDER BY total_qty DESC LIMIT 5
"""


def build_prompt(question: str, schema_desc: str = None) -> str:
    """组装最终发送给大模型的完整提示词。"""
    if schema_desc is None:
        from schema_extract import extract_schema, render_schema_desc
        schema_desc = render_schema_desc(extract_schema()) or SCHEMA_FALLBACK
    return SYSTEM_PROMPT.format(schema_desc=schema_desc) + f"\n问：{question}\n"
