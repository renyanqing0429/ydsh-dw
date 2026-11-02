-- ============================================================
-- 第 2 周 子任务 7：探索性数据分析（基于 DWD 层）
-- ------------------------------------------------------------
-- 1) 基础 KPI：总订单量 / 总用户数 / 总 GMV / 客单价
-- 2) 多维度分布：品类、省份、门店、渠道、会员等级、月度趋势
-- 3) 窗口函数：累计消费、订单排名、组内占比、排名（row_number/rank/sum over）
-- 4) 行为漏斗：浏览 → 加购/收藏 → 购买
-- 执行前提：已完成 sql/dwd/create_dwd.sql + load_dwd.sql
-- ============================================================

USE ydsh_dwd;

-- ---------- 1. 核心 KPI ----------
SELECT
    COUNT(DISTINCT order_id)                                        AS total_orders,
    COUNT(DISTINCT user_id)                                         AS total_users,
    ROUND(SUM(pay_amount), 2)                                       AS gmv,
    ROUND(AVG(pay_amount), 2)                                       AS avg_order_amount,
    ROUND(SUM(pay_amount) / COUNT(DISTINCT order_id), 2)            AS aov,
    ROUND(SUM(pay_amount) / COUNT(DISTINCT user_id), 2)             AS arpu,
    ROUND(SUM(discount_amount), 2)                                  AS total_discount
FROM ydsh_dwd.dwd_order;

-- ---------- 2. 有效订单口径 GMV（剔除待支付/已取消/退款中） ----------
SELECT
    COUNT(DISTINCT order_id)                             AS valid_orders,
    ROUND(SUM(pay_amount), 2)                            AS valid_gmv,
    ROUND(SUM(pay_amount) / COUNT(DISTINCT order_id), 2) AS valid_aov
FROM ydsh_dwd.dwd_order
WHERE is_valid_order = 1;

-- ---------- 3. 品类销售分布（明细事实表关联商品维度） ----------
SELECT
    p.category,
    COUNT(DISTINCT oi.order_id)          AS orders,
    SUM(oi.quantity)                     AS quantity,
    ROUND(SUM(oi.item_amount), 2)        AS sales,
    ROUND(SUM(oi.item_amount) * 100.0 / SUM(SUM(oi.item_amount)) OVER (), 2) AS sales_pct
FROM ydsh_dwd.dwd_order_item oi
LEFT JOIN ydsh_dwd.dim_product p ON oi.product_id = p.product_id
GROUP BY p.category
ORDER BY sales DESC;

-- ---------- 4. 省份销售分布（订单关联用户维度） ----------
SELECT
    u.province,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT o.user_id)  AS users,
    ROUND(SUM(o.pay_amount), 2) AS gmv,
    ROUND(SUM(o.pay_amount) / COUNT(DISTINCT o.order_id), 2) AS aov
FROM ydsh_dwd.dwd_order o
LEFT JOIN ydsh_dwd.dim_user u ON o.user_id = u.user_id
GROUP BY u.province
ORDER BY gmv DESC;

-- ---------- 5. 门店销售 Top10 ----------
SELECT
    s.store_id,
    s.store_name,
    s.city,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(o.pay_amount), 2) AS gmv
FROM ydsh_dwd.dwd_order o
LEFT JOIN ydsh_dwd.dim_store s ON o.store_id = s.store_id
GROUP BY s.store_id, s.store_name, s.city
ORDER BY gmv DESC
LIMIT 10;

-- ---------- 6. 渠道 / 支付方式 / 订单状态分布 ----------
SELECT channel,
       COUNT(*) AS orders,
       ROUND(SUM(pay_amount), 2) AS gmv,
       ROUND(AVG(pay_amount), 2) AS avg_amount,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS order_pct
FROM ydsh_dwd.dwd_order
GROUP BY channel
ORDER BY orders DESC;

SELECT pay_type,
       COUNT(*) AS orders,
       ROUND(SUM(pay_amount), 2) AS gmv,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS order_pct
FROM ydsh_dwd.dwd_order
GROUP BY pay_type
ORDER BY orders DESC;

SELECT order_status,
       COUNT(*) AS orders,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS order_pct
FROM ydsh_dwd.dwd_order
GROUP BY order_status
ORDER BY orders DESC;

-- ---------- 7. 会员等级消费力 ----------
SELECT
    u.member_level,
    COUNT(DISTINCT u.user_id) AS users,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(o.pay_amount), 2) AS gmv,
    ROUND(SUM(o.pay_amount) / COUNT(DISTINCT u.user_id), 2) AS avg_gmv_per_user
FROM ydsh_dwd.dim_user u
LEFT JOIN ydsh_dwd.dwd_order o ON u.user_id = o.user_id
GROUP BY u.member_level
ORDER BY avg_gmv_per_user DESC;

-- ---------- 8. 月度销售趋势（含环比） ----------
SELECT
    order_month,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(SUM(pay_amount), 2) AS gmv,
    ROUND(SUM(pay_amount) - LAG(SUM(pay_amount), 1) OVER (ORDER BY order_month), 2) AS gmv_mom_diff
FROM ydsh_dwd.dwd_order
GROUP BY order_month
ORDER BY order_month;

-- ---------- 9. 窗口函数：用户累计消费 + 订单排名 ----------
SELECT
    user_id,
    order_id,
    order_date,
    pay_amount,
    ROUND(SUM(pay_amount) OVER (PARTITION BY user_id ORDER BY order_date), 2) AS user_cum_amount,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY pay_amount DESC) AS user_order_rank
FROM ydsh_dwd.dwd_order
WHERE user_id IN (
    SELECT user_id FROM (
        SELECT user_id, SUM(pay_amount) AS amt
        FROM ydsh_dwd.dwd_order
        GROUP BY user_id
        ORDER BY amt DESC
        LIMIT 3
    ) t
)
ORDER BY user_id, order_date
LIMIT 30;

-- ---------- 10. 用户消费分层（RFM 中的 M） ----------
SELECT
    user_id,
    orders,
    total_amount,
    CASE
        WHEN total_amount >= 50000 THEN '高价值'
        WHEN total_amount >= 20000 THEN '中价值'
        ELSE '长尾'
    END AS user_level
FROM (
    SELECT
        user_id,
        COUNT(DISTINCT order_id) AS orders,
        ROUND(SUM(pay_amount), 2) AS total_amount
    FROM ydsh_dwd.dwd_order
    GROUP BY user_id
) t
ORDER BY total_amount DESC
LIMIT 20;

SELECT
    CASE
        WHEN total_amount >= 50000 THEN '高价值(>=5万)'
        WHEN total_amount >= 20000 THEN '中价值(2-5万)'
        ELSE '长尾(<2万)'
    END AS user_level,
    COUNT(*) AS users,
    ROUND(SUM(total_amount), 2) AS gmv,
    ROUND(SUM(total_amount) * 100.0 / SUM(SUM(total_amount)) OVER (), 2) AS gmv_pct
FROM (
    SELECT user_id, ROUND(SUM(pay_amount), 2) AS total_amount
    FROM ydsh_dwd.dwd_order
    GROUP BY user_id
) t
GROUP BY CASE
        WHEN total_amount >= 50000 THEN '高价值(>=5万)'
        WHEN total_amount >= 20000 THEN '中价值(2-5万)'
        ELSE '长尾(<2万)'
    END
ORDER BY gmv DESC;

-- ---------- 11. 门店月度排名（rank 窗口函数） ----------
SELECT
    order_month,
    store_id,
    gmv,
    RANK() OVER (PARTITION BY order_month ORDER BY gmv DESC) AS gmv_rank_in_month
FROM (
    SELECT order_month, store_id, ROUND(SUM(pay_amount), 2) AS gmv
    FROM ydsh_dwd.dwd_order
    GROUP BY order_month, store_id
) t
ORDER BY order_month, gmv_rank_in_month
LIMIT 24;

-- ---------- 12. 用户行为漏斗 ----------
SELECT
    behavior_type,
    COUNT(*) AS behavior_cnt,
    COUNT(DISTINCT user_id) AS uv,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM ydsh_dwd.dwd_user_behavior
GROUP BY behavior_type
ORDER BY behavior_cnt DESC;

-- ---------- 13. 品类 × 渠道 交叉分析 ----------
SELECT
    p.category,
    o.channel,
    ROUND(SUM(oi.item_amount), 2) AS sales
FROM ydsh_dwd.dwd_order_item oi
LEFT JOIN ydsh_dwd.dim_product p ON oi.product_id = p.product_id
LEFT JOIN ydsh_dwd.dwd_order o ON oi.order_id = o.order_id
GROUP BY p.category, o.channel
ORDER BY p.category, sales DESC;

-- ---------- 14. 周末 vs 工作日（关联时间维度） ----------
SELECT
    CASE WHEN d.is_weekend = 1 THEN '周末' ELSE '工作日' END AS day_type,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(o.pay_amount), 2) AS gmv
FROM ydsh_dwd.dwd_order o
LEFT JOIN ydsh_dwd.dim_date d ON o.order_date = d.date_id
GROUP BY d.is_weekend
ORDER BY gmv DESC;
