-- ============================================================
-- 第 3 周 子任务 1：核心 KPI 补齐（复购率）与 KPI 汇总总表
-- ------------------------------------------------------------
-- 背景：第 2 周 DWS/ADS 已覆盖任务书 6 项 KPI 中的 5 项——
--       GMV、订单量、客单价（ads_gmv_summary）、
--       活跃用户数（ads_gmv_summary.buyer_cnt / dws_user_1d.buyer_cnt）、
--       品类销售占比（ads_category_rank.share_pct）。
--       缺口：复购率（repurchase_rate）——dws_user_1d 只有「当日复购人数」，
--       ADS 层没有可对外输出的复购率指标。
-- 本脚本补两张表：
--   ads_kpi_core        任务书 6 项 KPI 单行汇总总表（答辩 / 看板直读）
--   ads_repurchase_rate 月度复购率（观察复购随月份的变化趋势）
-- 口径约定（与第 2 周一致，全部只统计有效订单 is_valid_order = 1）：
--   GMV            = SUM(pay_amount_valid)
--   订单量         = COUNT(DISTINCT order_id)（有效订单）
--   客单价 AOV     = GMV / 订单量
--   活跃用户数     = COUNT(DISTINCT user_id)（有下单行为的去重用户）
--   复购率         = 全周期有效订单 >= 2 笔的去重用户数 / 活跃用户数
--   品类销售占比   = 品类明细销售额 / 全部品类明细销售额（明细口径，只比占比）
-- 命名规范：库 ydsh_ads；表前缀 ads_；INSERT OVERWRITE 保证可重跑。
-- ============================================================

USE ydsh_ads;

-- ---------- 1. 复购用户集合（全周期有效订单 >= 2 笔） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_user_order_freq;
CREATE TABLE ydsh_ads.ads_user_order_freq (
    user_id          BIGINT COMMENT '用户 ID',
    valid_order_cnt  BIGINT COMMENT '全周期有效订单数',
    gmv              DOUBLE COMMENT '该用户全周期 GMV（有效订单）',
    first_order_date STRING COMMENT '首单日期',
    last_order_date  STRING COMMENT '最近一单日期',
    is_repeat_buyer  INT    COMMENT '是否复购用户：1=有效订单>=2 笔，0=否'
) COMMENT '用户下单频次明细（复购率计算底表）';

INSERT OVERWRITE TABLE ydsh_ads.ads_user_order_freq
SELECT
    t.user_id,
    t.valid_order_cnt,
    ROUND(t.gmv, 2)                      AS gmv,
    m.min_dt                             AS first_order_date,
    m.max_dt                             AS last_order_date,
    IF(t.valid_order_cnt >= 2, 1, 0)     AS is_repeat_buyer
FROM (
    SELECT
        d.user_id,
        SUM(d.is_valid_order)      AS valid_order_cnt,
        SUM(d.pay_amount_valid)    AS gmv
    FROM ydsh_dwd.dwd_order d
    GROUP BY d.user_id
) t
-- 回取首末单日期（仍按有效订单）
JOIN (
    SELECT user_id, MIN(order_date) AS min_dt, MAX(order_date) AS max_dt
    FROM ydsh_dwd.dwd_order
    WHERE is_valid_order = 1
    GROUP BY user_id
) m ON t.user_id = m.user_id;

-- ---------- 2. 月度复购率（截至各月末的累计口径） ----------
-- 说明：复购是「历史行为」指标，分子分母都用「截至当月末」的累计值：
--   累计活跃用户 = 首单月份 <= 当月的用户数；
--   累计复购用户 = 累计有效订单达到 2 笔的月份 <= 当月的用户数。
-- 避免出现「分子累计、分母当月」的口径错位（会虚高甚至得出 100%）。
DROP TABLE IF EXISTS ydsh_ads.ads_repurchase_rate;
CREATE TABLE ydsh_ads.ads_repurchase_rate (
    stat_month        STRING COMMENT '统计月份 yyyy-MM',
    active_user_cnt   BIGINT COMMENT '截至当月末累计有下单行为的去重用户数',
    repeat_user_cnt   BIGINT COMMENT '截至当月末累计有效订单 >= 2 笔的去重用户数',
    repurchase_rate   DOUBLE COMMENT '复购率 % = repeat_user_cnt / active_user_cnt * 100'
) COMMENT '月度累计复购率';

INSERT OVERWRITE TABLE ydsh_ads.ads_repurchase_rate
SELECT
    m.stat_month,
    COUNT(u.user_id)                                                    AS active_user_cnt,
    COUNT(CASE WHEN u.repeat_month IS NOT NULL
                AND u.repeat_month <= m.stat_month THEN u.user_id END)   AS repeat_user_cnt,
    ROUND(COUNT(CASE WHEN u.repeat_month IS NOT NULL
                AND u.repeat_month <= m.stat_month THEN u.user_id END)
          / COUNT(u.user_id) * 100, 2)                                   AS repurchase_rate
FROM (
    -- 自然月清单（保证无单月份也有口径基准）
    SELECT DISTINCT SUBSTR(order_date, 1, 7) AS stat_month
    FROM ydsh_dwd.dwd_order
    WHERE is_valid_order = 1
) m
JOIN (
    -- 每个用户：首单月份 + 首次达到 2 笔有效订单的月份
    SELECT
        user_id,
        MIN(mm)                                    AS first_month,
        MIN(CASE WHEN cum_cnt >= 2 THEN mm END)    AS repeat_month
    FROM (
        SELECT
            user_id,
            mm,
            SUM(cnt) OVER (PARTITION BY user_id ORDER BY mm
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_cnt
        FROM (
            SELECT user_id, SUBSTR(order_date, 1, 7) AS mm, SUM(is_valid_order) AS cnt
            FROM ydsh_dwd.dwd_order
            WHERE is_valid_order = 1
            GROUP BY user_id, SUBSTR(order_date, 1, 7)
        ) a
    ) b
    GROUP BY user_id
) u ON u.first_month <= m.stat_month
GROUP BY m.stat_month;

-- ---------- 3. 核心 KPI 总表（任务书 6 项，单行直读） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_kpi_core;
CREATE TABLE ydsh_ads.ads_kpi_core (
    stat_start       STRING COMMENT '统计起始日期',
    stat_end         STRING COMMENT '统计结束日期',
    gmv              DOUBLE COMMENT 'KPI-1 GMV（有效订单实付金额）',
    order_cnt        BIGINT COMMENT 'KPI-2 订单量（去重有效订单数）',
    aov              DOUBLE COMMENT 'KPI-3 客单价 = GMV / 订单量',
    active_user_cnt  BIGINT COMMENT 'KPI-4 活跃用户数（有下单行为的去重用户）',
    repurchase_rate  DOUBLE COMMENT 'KPI-5 复购率 %（有效订单>=2 笔用户 / 活跃用户）',
    repeat_user_cnt  BIGINT COMMENT '复购用户数（有效订单>=2 笔）',
    top_category     STRING COMMENT 'KPI-6 品类销售占比：第一名品类',
    top_category_pct DOUBLE COMMENT '第一名品类销售占比 %'
) COMMENT '第 3 周核心 KPI 汇总总表（任务书 6 项）';

INSERT OVERWRITE TABLE ydsh_ads.ads_kpi_core
SELECT
    s.stat_start,
    s.stat_end,
    s.gmv,
    s.valid_order_cnt                                            AS order_cnt,
    s.aov,
    s.buyer_cnt                                                  AS active_user_cnt,
    r.repurchase_rate,
    r.repeat_user_cnt,
    c.category                                                   AS top_category,
    c.share_pct                                                  AS top_category_pct
FROM ydsh_ads.ads_gmv_summary s
CROSS JOIN (
    -- 全周期复购口径：有有效订单的用户中，有效订单 >= 2 笔者占比
    SELECT ROUND(SUM(is_repeat_buyer) / COUNT(*) * 100, 2) AS repurchase_rate,
           SUM(is_repeat_buyer)                            AS repeat_user_cnt
    FROM ydsh_ads.ads_user_order_freq
    WHERE valid_order_cnt >= 1
) r
CROSS JOIN (
    SELECT category, share_pct
    FROM ydsh_ads.ads_category_rank
    ORDER BY rank_no
    LIMIT 1
) c;

-- ---------- 4. 验证查询 ----------
-- SELECT * FROM ydsh_ads.ads_kpi_core;
-- SELECT * FROM ydsh_ads.ads_repurchase_rate ORDER BY stat_month;
-- 抽查：复购用户数应 <= 活跃用户数；复购率应在 0~100 之间。
