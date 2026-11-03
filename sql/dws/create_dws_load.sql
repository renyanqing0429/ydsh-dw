-- ============================================================
-- 第 2 周 补充：DWS 汇总层（Data Warehouse Summary）
-- ------------------------------------------------------------
-- 定位：面向「分析主题」的轻度汇总层，按 天（1d）+ 主题 组织。
--       上游只读 DWD 明细/维度表，下游只被 ADS 应用层引用。
-- 设计原则：
--   1. 只做聚合与维度退化（把常用维度字段冗余进来），不再做清洗；
--   2. 粒度统一为「统计日 + 主题维度」，一张表只服务一个分析主题；
--   3. 全部按 dt 分区 + ORC 存储，INSERT OVERWRITE 保证可重复执行。
-- 表清单：
--   dws_order_1d    订单主题日汇总（GMV/订单数/有效订单/客单价）
--   dws_user_1d     用户主题日汇总（下单用户/新增用户/人均消费）
--   dws_category_1d 品类主题日汇总（走明细事实表，因订单表无 product_id）
--   dws_channel_1d  渠道主题日汇总（渠道结构 + 有效订单率）
-- 命名规范：库 ydsh_dws；表前缀 dws_；分区字段统一 dt（yyyy-MM-dd）
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dws;
USE ydsh_dws;

SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;
SET hive.exec.max.dynamic.partitions = 2000;
SET hive.exec.max.dynamic.partitions.pernode = 2000;

-- ---------- 1. 订单主题日汇总 ----------
DROP TABLE IF EXISTS ydsh_dws.dws_order_1d;
CREATE TABLE ydsh_dws.dws_order_1d (
    order_cnt        BIGINT  COMMENT '订单总数（含取消/退款）',
    valid_order_cnt  BIGINT  COMMENT '有效订单数（已完成/已支付）',
    invalid_order_cnt BIGINT COMMENT '无效订单数（取消/退款/待支付）',
    valid_rate       DOUBLE  COMMENT '有效订单率 = 有效订单数 / 订单总数',
    gmv              DOUBLE  COMMENT 'GMV = 有效订单支付金额合计',
    discount_total   DOUBLE  COMMENT '优惠金额合计（有效订单）',
    avg_order_amount DOUBLE  COMMENT '客单价 = GMV / 有效订单数',
    buyer_cnt        BIGINT  COMMENT '下单用户数（去重，全部订单）',
    per_capita_gmv   DOUBLE  COMMENT '人均消费 = GMV / 下单用户数'
) COMMENT 'DWS 订单主题日汇总'
PARTITIONED BY (dt STRING COMMENT '统计日期 yyyy-MM-dd')
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_dws.dws_order_1d PARTITION (dt)
SELECT
    COUNT(*)                                                        AS order_cnt,
    SUM(is_valid_order)                                             AS valid_order_cnt,
    COUNT(*) - SUM(is_valid_order)                                  AS invalid_order_cnt,
    ROUND(SUM(is_valid_order) * 100.0 / COUNT(*), 2)                AS valid_rate,
    -- 口径由 DWD 的 pay_amount_valid 提供（无效订单已在加载时置 0），此处不再重复写 CASE
    ROUND(SUM(pay_amount_valid), 2)                                 AS gmv,
    ROUND(SUM(discount_amount_valid), 2)                            AS discount_total,
    ROUND(SUM(pay_amount_valid) / NULLIF(SUM(is_valid_order), 0), 2) AS avg_order_amount,
    COUNT(DISTINCT user_id)                                         AS buyer_cnt,
    ROUND(SUM(pay_amount_valid)
          / NULLIF(COUNT(DISTINCT user_id), 0), 2)                  AS per_capita_gmv,
    order_date                                                      AS dt
FROM ydsh_dwd.dwd_order
GROUP BY order_date;

SELECT 'dws_order_1d' AS tbl, COUNT(*) AS row_cnt, COUNT(DISTINCT dt) AS dt_cnt FROM ydsh_dws.dws_order_1d;

-- ---------- 2. 用户主题日汇总 ----------
-- 说明：新增用户按 dim_user.register_date 判定；消费指标只统计有效订单。
DROP TABLE IF EXISTS ydsh_dws.dws_user_1d;
CREATE TABLE ydsh_dws.dws_user_1d (
    buyer_cnt      BIGINT COMMENT '当日下单用户数',
    new_user_cnt   BIGINT COMMENT '当日新注册用户数（来自 dim_user）',
    order_cnt      BIGINT COMMENT '当日有效订单数',
    gmv            DOUBLE COMMENT '当日 GMV',
    avg_user_amount DOUBLE COMMENT '当日人均消费 = GMV / 下单用户数',
    repeat_buyer_cnt BIGINT COMMENT '当日复购用户数（该用户历史有效订单 > 1 笔）'
) COMMENT 'DWS 用户主题日汇总'
PARTITIONED BY (dt STRING COMMENT '统计日期 yyyy-MM-dd')
STORED AS ORC;

-- 复购口径：该用户在「全周期」有效订单 > 1 笔，即老客；用窗口函数先算历史累计再按日聚合。
INSERT OVERWRITE TABLE ydsh_dws.dws_user_1d PARTITION (dt)
SELECT
    o.buyer_cnt,
    COALESCE(n.new_user_cnt, 0)                        AS new_user_cnt,
    o.order_cnt,
    o.gmv,
    ROUND(o.gmv / NULLIF(o.buyer_cnt, 0), 2)           AS avg_user_amount,
    o.repeat_buyer_cnt,
    o.order_date                                       AS dt
FROM (
    SELECT
        t.order_date,
        COUNT(DISTINCT t.user_id)                                  AS buyer_cnt,
        SUM(t.is_valid_order)                                      AS order_cnt,
        ROUND(SUM(t.pay_amount_valid), 2)                          AS gmv,
        COUNT(DISTINCT CASE WHEN t.valid_order_cnt_hist > 1 THEN t.user_id END)    AS repeat_buyer_cnt
    FROM (
        SELECT
            d.order_date, d.user_id, d.is_valid_order, d.pay_amount_valid,
            SUM(d.is_valid_order) OVER (PARTITION BY d.user_id) AS valid_order_cnt_hist
        FROM ydsh_dwd.dwd_order d
    ) t
    GROUP BY t.order_date
) o
LEFT JOIN (
    SELECT register_date, COUNT(*) AS new_user_cnt
    FROM ydsh_dwd.dim_user
    GROUP BY register_date
) n ON o.order_date = n.register_date;

SELECT 'dws_user_1d' AS tbl, COUNT(*) AS row_cnt, SUM(buyer_cnt) AS buyer_sum, SUM(new_user_cnt) AS new_sum FROM ydsh_dws.dws_user_1d;

-- ---------- 3. 品类主题日汇总 ----------
-- 说明：dwd_order 无 product_id，品类维度必须走明细事实表 dwd_order_item。
--       口径：品类销售额 = Σ(单价 × 数量 × (1 - 折扣率))，与订单支付金额不等价，只比较占比。
DROP TABLE IF EXISTS ydsh_dws.dws_category_1d;
CREATE TABLE ydsh_dws.dws_category_1d (
    category      STRING COMMENT '一级类目',
    order_cnt     BIGINT COMMENT '涉及订单数（去重）',
    item_cnt      BIGINT COMMENT '明细行数（件数按 quantity 另计）',
    quantity      BIGINT COMMENT '销售件数',
    sales_amount  DOUBLE COMMENT '品类销售额（明细口径）',
    avg_item_price DOUBLE COMMENT '件单价 = 销售额 / 件数'
) COMMENT 'DWS 品类主题日汇总（明细口径）'
PARTITIONED BY (dt STRING COMMENT '统计日期 yyyy-MM-dd')
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_dws.dws_category_1d PARTITION (dt)
SELECT
    p.category                                       AS category,
    COUNT(DISTINCT i.order_id)                       AS order_cnt,
    COUNT(*)                                         AS item_cnt,
    SUM(i.quantity)                                  AS quantity,
    ROUND(SUM(i.item_amount), 2)                     AS sales_amount,
    ROUND(SUM(i.item_amount) / NULLIF(SUM(i.quantity), 0), 2) AS avg_item_price,
    i.order_date                                     AS dt
FROM ydsh_dwd.dwd_order_item i
LEFT JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
WHERE p.category IS NOT NULL
GROUP BY p.category, i.order_date;

SELECT 'dws_category_1d' AS tbl, COUNT(*) AS row_cnt, ROUND(SUM(sales_amount),2) AS sales_sum FROM ydsh_dws.dws_category_1d;

-- ---------- 4. 渠道主题日汇总 ----------
DROP TABLE IF EXISTS ydsh_dws.dws_channel_1d;
CREATE TABLE ydsh_dws.dws_channel_1d (
    channel        STRING COMMENT '下单渠道（已标准化）',
    order_cnt      BIGINT COMMENT '订单数',
    valid_order_cnt BIGINT COMMENT '有效订单数',
    gmv            DOUBLE COMMENT 'GMV',
    avg_order_amount DOUBLE COMMENT '客单价',
    user_cnt       BIGINT COMMENT '下单用户数'
) COMMENT 'DWS 渠道主题日汇总'
PARTITIONED BY (dt STRING COMMENT '统计日期 yyyy-MM-dd')
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_dws.dws_channel_1d PARTITION (dt)
SELECT
    channel,
    COUNT(*)                                          AS order_cnt,
    SUM(is_valid_order)                               AS valid_order_cnt,
    ROUND(SUM(pay_amount_valid), 2)                   AS gmv,
    ROUND(SUM(pay_amount_valid)
          / NULLIF(SUM(is_valid_order), 0), 2)        AS avg_order_amount,
    COUNT(DISTINCT user_id)                           AS user_cnt,
    order_date                                        AS dt
FROM ydsh_dwd.dwd_order
GROUP BY channel, order_date;

SELECT 'dws_channel_1d' AS tbl, COUNT(*) AS row_cnt, ROUND(SUM(gmv),2) AS gmv_sum FROM ydsh_dws.dws_channel_1d;

-- ---------- 5. 建表与数据校验 ----------
SHOW TABLES IN ydsh_dws;
SELECT 'dws_total_rows' AS metric,
       (SELECT COUNT(*) FROM ydsh_dws.dws_order_1d)
     + (SELECT COUNT(*) FROM ydsh_dws.dws_user_1d)
     + (SELECT COUNT(*) FROM ydsh_dws.dws_category_1d)
     + (SELECT COUNT(*) FROM ydsh_dws.dws_channel_1d) AS val;
