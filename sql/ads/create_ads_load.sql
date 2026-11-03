-- ============================================================
-- 第 2 周 补充：ADS 应用层（Application Data Service）
-- ------------------------------------------------------------
-- 定位：直接对接报表 / 大屏 / 分析结论的「结果表」，一行一指标或一行一排名，
--       前端（Superset 等）零计算直读，不再做 JOIN 与聚合。
-- 上游：只读 DWS 汇总层（dws_order_1d / dws_category_1d / dws_channel_1d），
--       用户/省份/会员三个主题因 DWS 未覆盖该粒度，直接回取 DWD 明细 + 维度表。
-- 表清单：
--   ads_gmv_summary          全局经营总览（单行，回答「整体做得怎么样」）
--   ads_daily_trend          日趋势（大屏折线图数据源）
--   ads_category_rank        品类销售额排名（含占比与累计占比，帕累托分析）
--   ads_channel_dist         渠道结构分布
--   ads_province_rank        省份销售排名
--   ads_user_value_seg       用户价值分层（高/中/长尾）
--   ads_member_level_compare 会员等级消费对比（用于验证「等级与消费是否相关」）
-- 口径统一约定：
--   GMV / 客单价 / 用户数 一律只统计有效订单（is_valid_order = 1）；
--   品类销售额为明细口径（单价×数量×(1-折扣率)），与订单支付金额不等价，只比占比。
-- 命名规范：库 ydsh_ads；表前缀 ads_；全部 INSERT OVERWRITE 保证可重跑。
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_ads;
USE ydsh_ads;

-- ---------- 1. 全局经营总览 ----------
DROP TABLE IF EXISTS ydsh_ads.ads_gmv_summary;
CREATE TABLE ydsh_ads.ads_gmv_summary (
    stat_start      STRING COMMENT '统计起始日期',
    stat_end        STRING COMMENT '统计结束日期',
    stat_days       INT    COMMENT '统计天数',
    order_cnt       BIGINT COMMENT '订单总数',
    valid_order_cnt BIGINT COMMENT '有效订单数',
    valid_rate      DOUBLE COMMENT '有效订单率 %',
    gmv             DOUBLE COMMENT 'GMV',
    avg_daily_gmv   DOUBLE COMMENT '日均 GMV',
    aov             DOUBLE COMMENT '客单价 = GMV / 有效订单数',
    buyer_cnt       BIGINT COMMENT '全周期去重下单用户数',
    arpu            DOUBLE COMMENT 'ARPU = GMV / 去重用户数',
    discount_total  DOUBLE COMMENT '优惠总额',
    discount_rate   DOUBLE COMMENT '优惠率 = 优惠 / (GMV + 优惠) %',
    gmv_all         DOUBLE COMMENT '含无效订单口径 GMV（仅用于与探索性分析简报对齐）',
    aov_all         DOUBLE COMMENT '含无效订单口径客单价'
) COMMENT 'ADS 全局经营总览（单行）'
STORED AS ORC;

-- 注意：不能用「按日汇总后的 buyer_cnt 直接相加」算 ARPU，同一用户跨天会被重复计数，
-- 因此用户数单独从 DWD 全周期去重后 CROSS JOIN 进来。
INSERT OVERWRITE TABLE ydsh_ads.ads_gmv_summary
SELECT
    s.stat_start, s.stat_end, s.stat_days,
    s.order_cnt, s.valid_order_cnt, s.valid_rate,
    s.gmv, s.avg_daily_gmv, s.aov,
    u.buyer_cnt,
    ROUND(s.gmv / NULLIF(u.buyer_cnt, 0), 2) AS arpu,
    s.discount_total, s.discount_rate,
    a.gmv_all, a.aov_all
FROM (
    SELECT
        MIN(dt)                        AS stat_start,
        MAX(dt)                        AS stat_end,
        COUNT(DISTINCT dt)             AS stat_days,
        SUM(order_cnt)                 AS order_cnt,
        SUM(valid_order_cnt)           AS valid_order_cnt,
        ROUND(SUM(valid_order_cnt) * 100.0 / SUM(order_cnt), 2) AS valid_rate,
        ROUND(SUM(gmv), 2)             AS gmv,
        ROUND(SUM(gmv) / COUNT(DISTINCT dt), 2) AS avg_daily_gmv,
        ROUND(SUM(gmv) / SUM(valid_order_cnt), 2) AS aov,
        ROUND(SUM(discount_total), 2)  AS discount_total,
        ROUND(SUM(discount_total) * 100.0
              / (SUM(gmv) + SUM(discount_total)), 2) AS discount_rate
    FROM ydsh_dws.dws_order_1d
) s
CROSS JOIN (
    SELECT COUNT(DISTINCT user_id) AS buyer_cnt
    FROM ydsh_dwd.dwd_order
    WHERE is_valid_order = 1
) u
-- 全订单口径（含待支付/取消/退款）：源数据中这些状态同样写了 pay_amount，
-- 真实业务不应计入 GMV，故只作为对照列，不参与主口径计算。
CROSS JOIN (
    SELECT ROUND(SUM(pay_amount), 2) AS gmv_all,
           ROUND(SUM(pay_amount) / COUNT(*), 2) AS aov_all
    FROM ydsh_dwd.dwd_order
) a;

SELECT * FROM ydsh_ads.ads_gmv_summary;

-- ---------- 2. 日趋势（大屏折线） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_daily_trend;
CREATE TABLE ydsh_ads.ads_daily_trend (
    dt          STRING COMMENT '统计日期',
    gmv         DOUBLE COMMENT 'GMV',
    order_cnt   BIGINT COMMENT '订单数',
    valid_order_cnt BIGINT COMMENT '有效订单数',
    buyer_cnt   BIGINT COMMENT '下单用户数',
    aov         DOUBLE COMMENT '客单价'
) COMMENT 'ADS 日趋势'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_daily_trend
SELECT dt, gmv, order_cnt, valid_order_cnt, buyer_cnt, avg_order_amount AS aov
FROM ydsh_dws.dws_order_1d
ORDER BY dt;

SELECT 'ads_daily_trend' AS tbl, COUNT(*) AS row_cnt,
       ROUND(SUM(gmv), 2) AS gmv_sum, ROUND(AVG(aov), 2) AS aov_avg
FROM ydsh_ads.ads_daily_trend;

-- ---------- 3. 品类销售额排名（帕累托） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_category_rank;
CREATE TABLE ydsh_ads.ads_category_rank (
    rank_no       INT    COMMENT '销售额排名',
    category      STRING COMMENT '一级类目',
    sales_amount  DOUBLE COMMENT '销售额（明细口径）',
    quantity      BIGINT COMMENT '销售件数',
    order_cnt     BIGINT COMMENT '涉及订单数',
    share_pct     DOUBLE COMMENT '销售额占比 %',
    cum_share_pct DOUBLE COMMENT '累计占比 %（帕累托判断）'
) COMMENT 'ADS 品类销售额排名'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_category_rank
SELECT
    rank_no, category, sales_amount, quantity, order_cnt,
    ROUND(sales_amount * 100.0 / SUM(sales_amount) OVER (), 2) AS share_pct,
    ROUND(SUM(sales_amount) OVER (ORDER BY rank_no
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) * 100.0
          / SUM(sales_amount) OVER (), 2) AS cum_share_pct
FROM (
    SELECT
        RANK() OVER (ORDER BY SUM(sales_amount) DESC) AS rank_no,
        category,
        ROUND(SUM(sales_amount), 2) AS sales_amount,
        SUM(quantity)               AS quantity,
        SUM(order_cnt)              AS order_cnt
    FROM ydsh_dws.dws_category_1d
    GROUP BY category
) t;

SELECT * FROM ydsh_ads.ads_category_rank ORDER BY rank_no;

-- ---------- 4. 渠道结构分布 ----------
DROP TABLE IF EXISTS ydsh_ads.ads_channel_dist;
CREATE TABLE ydsh_ads.ads_channel_dist (
    channel      STRING COMMENT '渠道',
    order_cnt    BIGINT COMMENT '订单数',
    valid_order_cnt BIGINT COMMENT '有效订单数',
    valid_rate   DOUBLE COMMENT '有效订单率 %',
    gmv          DOUBLE COMMENT 'GMV',
    aov          DOUBLE COMMENT '客单价',
    gmv_share    DOUBLE COMMENT 'GMV 占比 %',
    order_share  DOUBLE COMMENT '订单量占比 %'
) COMMENT 'ADS 渠道结构分布'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_channel_dist
SELECT
    channel,
    SUM(order_cnt)       AS order_cnt,
    SUM(valid_order_cnt) AS valid_order_cnt,
    ROUND(SUM(valid_order_cnt) * 100.0 / SUM(order_cnt), 2) AS valid_rate,
    ROUND(SUM(gmv), 2)   AS gmv,
    ROUND(SUM(gmv) / NULLIF(SUM(valid_order_cnt), 0), 2) AS aov,
    ROUND(SUM(gmv) * 100.0 / SUM(SUM(gmv)) OVER (), 2)         AS gmv_share,
    ROUND(SUM(order_cnt) * 100.0 / SUM(SUM(order_cnt)) OVER (), 2) AS order_share
FROM ydsh_dws.dws_channel_1d
GROUP BY channel;

SELECT * FROM ydsh_ads.ads_channel_dist ORDER BY gmv DESC;

-- ---------- 5. 省份销售排名 ----------
DROP TABLE IF EXISTS ydsh_ads.ads_province_rank;
CREATE TABLE ydsh_ads.ads_province_rank (
    rank_no     INT    COMMENT 'GMV 排名',
    province    STRING COMMENT '省份',
    buyer_cnt   BIGINT COMMENT '下单用户数',
    order_cnt   BIGINT COMMENT '有效订单数',
    gmv         DOUBLE COMMENT 'GMV',
    aov         DOUBLE COMMENT '客单价',
    gmv_share   DOUBLE COMMENT 'GMV 占比 %'
) COMMENT 'ADS 省份销售排名'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_province_rank
SELECT
    RANK() OVER (ORDER BY gmv DESC) AS rank_no,
    province, buyer_cnt, order_cnt, gmv,
    ROUND(gmv / NULLIF(order_cnt, 0), 2) AS aov,
    ROUND(gmv * 100.0 / SUM(gmv) OVER (), 2) AS gmv_share
FROM (
    SELECT
        u.province                    AS province,
        COUNT(DISTINCT o.user_id)     AS buyer_cnt,
        COUNT(*)                      AS order_cnt,
        ROUND(SUM(o.pay_amount), 2)   AS gmv
    FROM ydsh_dwd.dwd_order o
    JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
    WHERE o.is_valid_order = 1
    GROUP BY u.province
) t;

SELECT * FROM ydsh_ads.ads_province_rank ORDER BY rank_no LIMIT 10;

-- ---------- 6. 用户价值分层 ----------
-- 阈值说明：探索性分析（简报）用的是「全订单口径」，用户人均 3.85 万，5 万/2 万阈值合理；
-- 本表改用「有效订单口径」（人均 2.56 万），若仍用 5 万阈值只有 7 人达标，分层失效。
-- 故按有效口径分位数重标定：P80 = 33,911 → 3.5 万；P40 = 22,521 → 2 万。
DROP TABLE IF EXISTS ydsh_ads.ads_user_value_seg;
CREATE TABLE ydsh_ads.ads_user_value_seg (
    seg          STRING COMMENT '分层：高价值(>=3.5万)/中价值(2-3.5万)/长尾(<2万)',
    user_cnt     BIGINT COMMENT '用户数',
    user_share   DOUBLE COMMENT '用户占比 %',
    order_cnt    BIGINT COMMENT '有效订单数',
    gmv          DOUBLE COMMENT 'GMV',
    gmv_share    DOUBLE COMMENT 'GMV 占比 %',
    arpu         DOUBLE COMMENT '人均消费',
    avg_orders   DOUBLE COMMENT '人均订单数'
) COMMENT 'ADS 用户价值分层'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_user_value_seg
SELECT
    seg, user_cnt,
    ROUND(user_cnt * 100.0 / SUM(user_cnt) OVER (), 2) AS user_share,
    order_cnt, gmv,
    ROUND(gmv * 100.0 / SUM(gmv) OVER (), 2)           AS gmv_share,
    ROUND(gmv / NULLIF(user_cnt, 0), 2)                AS arpu,
    ROUND(order_cnt * 1.0 / NULLIF(user_cnt, 0), 2)    AS avg_orders
FROM (
    SELECT
        CASE
            WHEN total_amount >= 35000 THEN '高价值(>=3.5万)'
            WHEN total_amount >= 20000 THEN '中价值(2-3.5万)'
            ELSE '长尾(<2万)'
        END                         AS seg,
        COUNT(*)                    AS user_cnt,
        SUM(orders)                 AS order_cnt,
        ROUND(SUM(total_amount), 2) AS gmv
    FROM (
        SELECT
            user_id,
            COUNT(*)                  AS orders,
            SUM(pay_amount)           AS total_amount
        FROM ydsh_dwd.dwd_order
        WHERE is_valid_order = 1
        GROUP BY user_id
    ) t
    GROUP BY CASE
        WHEN total_amount >= 35000 THEN '高价值(>=3.5万)'
        WHEN total_amount >= 20000 THEN '中价值(2-3.5万)'
        ELSE '长尾(<2万)'
    END
) s;

SELECT * FROM ydsh_ads.ads_user_value_seg ORDER BY gmv DESC;

-- ---------- 7. 会员等级消费对比 ----------
DROP TABLE IF EXISTS ydsh_ads.ads_member_level_compare;
CREATE TABLE ydsh_ads.ads_member_level_compare (
    member_level STRING COMMENT '会员等级',
    level_weight INT    COMMENT '等级权重 1~4',
    user_cnt     BIGINT COMMENT '下单用户数',
    order_cnt    BIGINT COMMENT '有效订单数',
    gmv          DOUBLE COMMENT 'GMV',
    aov          DOUBLE COMMENT '客单价',
    arpu         DOUBLE COMMENT '人均消费',
    gmv_share    DOUBLE COMMENT 'GMV 占比 %'
) COMMENT 'ADS 会员等级消费对比'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_member_level_compare
SELECT
    member_level, level_weight, user_cnt, order_cnt, gmv,
    ROUND(gmv / NULLIF(order_cnt, 0), 2) AS aov,
    ROUND(gmv / NULLIF(user_cnt, 0), 2)  AS arpu,
    ROUND(gmv * 100.0 / SUM(gmv) OVER (), 2) AS gmv_share
FROM (
    SELECT
        u.member_level                 AS member_level,
        MAX(u.level_weight)            AS level_weight,
        COUNT(DISTINCT o.user_id)      AS user_cnt,
        COUNT(*)                       AS order_cnt,
        ROUND(SUM(o.pay_amount), 2)    AS gmv
    FROM ydsh_dwd.dwd_order o
    JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
    WHERE o.is_valid_order = 1
    GROUP BY u.member_level
) t;

SELECT * FROM ydsh_ads.ads_member_level_compare ORDER BY level_weight;

-- ---------- 8. 四层链路对账 ----------
-- 校验 DWD → DWS → ADS 的 GMV 是否一致（链路可核对性，答辩重点）
SELECT 'ADS总览_GMV' AS metric, ROUND(gmv, 2) AS val FROM ydsh_ads.ads_gmv_summary
UNION ALL SELECT 'DWS日汇总_GMV', ROUND(SUM(gmv), 2) FROM ydsh_dws.dws_order_1d
UNION ALL SELECT 'DWD明细_GMV', ROUND(SUM(pay_amount), 2) FROM ydsh_dwd.dwd_order WHERE is_valid_order = 1
UNION ALL SELECT 'ADS日趋势_GMV', ROUND(SUM(gmv), 2) FROM ydsh_ads.ads_daily_trend
UNION ALL SELECT 'ADS总览_GMV含无效单', ROUND(gmv_all, 2) FROM ydsh_ads.ads_gmv_summary;

SHOW TABLES IN ydsh_ads;
