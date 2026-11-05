-- ============================================================
-- 第 2 周 补充（三）：ADS 商品榜单 + 门店坪效
-- ------------------------------------------------------------
-- 为什么补这两张：
--   前 11 张 ADS 表覆盖了「整体 / 时间 / 品类 / 渠道 / 省份 / 用户 / 履约」，
--   但经营会上被问得最多的两个问题还答不了：
--     ① 到底哪几个单品在卖？（品类只是二级粒度，爆款与滞销品都在同一类里）
--     ② 门店是「开得多」还是「开得好」？（前期结论是门店表现均衡，需要坪效佐证）
-- 口径：
--   1. 一律只统计有效订单（is_valid_order = 1），金额用 DWD 的 pay_amount_valid；
--      dwd_order_item 自身不带订单状态，必须回 JOIN dwd_order 才能过滤。
--   2. 商品销售额为明细口径（单价 × 数量 × (1-折扣率)），与订单支付金额不等价，
--      只用于内部排名与占比，不与 GMV 对账。
--   3. 坪效 = 有效 GMV / 门店面积（平方米），面积来自 dim_store.area。
-- 幂等：全部 INSERT OVERWRITE。
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_ads;
USE ydsh_ads;

-- ---------- 1. 单品销售榜（600 个 SKU） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_product_rank;
CREATE TABLE ydsh_ads.ads_product_rank (
    rank_no          INT    COMMENT '销售额总排名',
    product_id       STRING COMMENT '商品ID',
    product_name     STRING COMMENT '商品名称',
    category         STRING COMMENT '一级类目',
    sub_category     STRING COMMENT '二级类目',
    brand            STRING COMMENT '品牌',
    price            DOUBLE COMMENT '售价',
    price_band       STRING COMMENT '价格带',
    quantity         BIGINT COMMENT '销量（件）',
    order_cnt        BIGINT COMMENT '涉及有效订单数',
    sales_amount     DOUBLE COMMENT '销售额（明细口径）',
    share_pct        DOUBLE COMMENT '销售额占比 %',
    cum_share_pct    DOUBLE COMMENT '累计占比 %（帕累托：看前 N 个 SKU 撑起多少销售）',
    rank_in_category INT    COMMENT '品类内排名',
    pareto_class     STRING COMMENT '帕累托分层：A 头部(累计≤80%) / B 中部(80~95%) / C 长尾(>95%)'
) COMMENT 'ADS 单品销售榜'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_product_rank
SELECT
    rank_no, product_id, product_name, category, sub_category, brand, price, price_band,
    quantity, order_cnt, sales_amount,
    ROUND(sales_amount * 100.0 / SUM(sales_amount) OVER (), 2) AS share_pct,
    ROUND(SUM(sales_amount) OVER (ORDER BY rank_no
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) * 100.0
          / SUM(sales_amount) OVER (), 2) AS cum_share_pct,
    RANK() OVER (PARTITION BY category ORDER BY sales_amount DESC) AS rank_in_category,
    CASE
        WHEN SUM(sales_amount) OVER (ORDER BY rank_no
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             <= 0.80 * SUM(sales_amount) OVER () THEN 'A 头部'
        WHEN SUM(sales_amount) OVER (ORDER BY rank_no
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             <= 0.95 * SUM(sales_amount) OVER () THEN 'B 中部'
        ELSE 'C 长尾'
    END AS pareto_class
FROM (
    SELECT
        RANK() OVER (ORDER BY SUM(i.item_amount) DESC) AS rank_no,
        p.product_id, p.product_name, p.category, p.sub_category, p.brand,
        p.price, p.price_band,
        SUM(i.quantity)                AS quantity,
        COUNT(DISTINCT i.order_id)     AS order_cnt,
        ROUND(SUM(i.item_amount), 2)   AS sales_amount
    FROM ydsh_dwd.dwd_order_item i
    JOIN ydsh_dwd.dwd_order  o ON i.order_id = o.order_id
    JOIN ydsh_dwd.dim_product p ON i.product_id = p.product_id
    WHERE o.is_valid_order = 1
    GROUP BY p.product_id, p.product_name, p.category, p.sub_category, p.brand,
             p.price, p.price_band
) t;

SELECT 'ads_product_rank' AS tbl, COUNT(*) AS sku_cnt,
       ROUND(SUM(sales_amount), 2) AS sales_sum,
       SUM(CASE WHEN pareto_class = 'A 头部' THEN 1 ELSE 0 END) AS class_a_cnt,
       ROUND(SUM(CASE WHEN pareto_class = 'A 头部' THEN sales_amount ELSE 0 END)
             * 100.0 / SUM(sales_amount), 2) AS class_a_share
FROM ydsh_ads.ads_product_rank;

SELECT rank_no, product_id, product_name, category, price_band, quantity,
       sales_amount, share_pct, cum_share_pct
FROM ydsh_ads.ads_product_rank ORDER BY rank_no LIMIT 10;

-- ---------- 2. 门店坪效（60 家） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_store_efficiency;
CREATE TABLE ydsh_ads.ads_store_efficiency (
    rank_no      INT    COMMENT '坪效排名',
    store_id     STRING COMMENT '门店ID',
    store_name   STRING COMMENT '门店名称',
    city         STRING COMMENT '城市',
    area         DOUBLE COMMENT '门店面积（㎡）',
    open_date    STRING COMMENT '开业日期',
    order_cnt    BIGINT COMMENT '有效订单数',
    gmv          DOUBLE COMMENT '有效 GMV',
    aov          DOUBLE COMMENT '客单价',
    gmv_per_sqm  DOUBLE COMMENT '坪效 = GMV / 面积',
    gmv_share    DOUBLE COMMENT 'GMV 占比 %',
    efficiency_level STRING COMMENT '坪效四分位分层：高效(前25%)/中效(25~75%)/低效(后25%)'
) COMMENT 'ADS 门店坪效'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_store_efficiency
SELECT
    RANK() OVER (ORDER BY gmv_per_sqm DESC) AS rank_no,
    store_id, store_name, city, area, open_date,
    order_cnt, gmv,
    ROUND(gmv / NULLIF(order_cnt, 0), 2) AS aov,
    gmv_per_sqm,
    ROUND(gmv * 100.0 / SUM(gmv) OVER (), 2) AS gmv_share,
    -- 用 NTILE(4) 代替 PERCENTILE：PERCENTILE 是聚合函数，与同层的窗口函数混用会触发
    -- "not a GROUP BY expression"；NTILE 是纯窗口函数，且 60 家门店正好每家 15 家一档
    CASE NTILE(4) OVER (ORDER BY gmv_per_sqm DESC)
        WHEN 1 THEN '高效(前25%)'
        WHEN 4 THEN '低效(后25%)'
        ELSE '中效(25~75%)'
    END AS efficiency_level
FROM (
    SELECT
        s.store_id, s.store_name, s.city, s.area, s.open_date,
        COUNT(o.order_id)                            AS order_cnt,
        ROUND(SUM(o.pay_amount_valid), 2)            AS gmv,
        ROUND(SUM(o.pay_amount_valid) / NULLIF(s.area, 0), 2) AS gmv_per_sqm
    FROM ydsh_dwd.dim_store s
    LEFT JOIN ydsh_dwd.dwd_order o
           ON s.store_id = o.store_id AND o.is_valid_order = 1
    GROUP BY s.store_id, s.store_name, s.city, s.area, s.open_date
) t;

SELECT 'ads_store_efficiency' AS tbl, COUNT(*) AS store_cnt,
       ROUND(SUM(gmv), 2) AS gmv_sum,
       ROUND(MIN(gmv_per_sqm), 2) AS min_eff,
       ROUND(MAX(gmv_per_sqm), 2) AS max_eff
FROM ydsh_ads.ads_store_efficiency;

SELECT * FROM ydsh_ads.ads_store_efficiency ORDER BY rank_no LIMIT 5;

-- ---------- 3. 全表校验 ----------
SELECT 'ads_product_rank'    AS tbl, COUNT(*) AS cnt FROM ydsh_ads.ads_product_rank
UNION ALL SELECT 'ads_store_efficiency', COUNT(*) FROM ydsh_ads.ads_store_efficiency;

-- 门店 GMV 合计必须等于全局 GMV（有效订单口径），验证 LEFT JOIN 没丢行也没重复
SELECT '门店GMV合计' AS metric, ROUND(SUM(gmv), 2) AS val FROM ydsh_ads.ads_store_efficiency
UNION ALL SELECT 'ADS总览_GMV', ROUND(gmv, 2) FROM ydsh_ads.ads_gmv_summary;
