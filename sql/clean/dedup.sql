-- ============================================================
-- 数据清洗（一）：重复值检测与去重
-- 两类重复，处理策略不同：
--   A. 整行完全重复        → 直接按主键去重保留一条即可
--   B. 主键重复但内容不同  → 按"最后更新"等业务规则保留一条（本脚本
--     以 order_time 最晚为最新记录，保留它）
-- 输出：dwd_order（去重后订单表），并统计去重前后行数差异
-- ============================================================

USE ydsh_ods;

-- ---------- 1. 检测 ----------
-- 1.1 主键重复订单数
SELECT order_id, COUNT(*) AS dup_cnt
FROM ods_order
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY dup_cnt DESC
LIMIT 20;

-- 1.2 区分两类重复
SELECT
    SUM(CASE WHEN all_cols_cnt > 1 THEN 1 ELSE 0 END) AS fully_dup_groups,
    SUM(CASE WHEN id_cnt > 1 AND all_cols_cnt = 1 THEN 1 ELSE 0 END) AS content_conflict_groups
FROM (
    SELECT
        order_id,
        COUNT(*) AS id_cnt,
        COUNT(DISTINCT CONCAT_WS('|', user_id, store_id, order_date, order_time,
              CAST(pay_amount AS STRING), CAST(discount_amount AS STRING),
              pay_type, order_status, channel)) AS all_cols_cnt
    FROM ods_order
    GROUP BY order_id
) t;

-- ---------- 2. 去重：ROW_NUMBER 窗口函数 ----------
-- 排序规则：order_time 越晚视为越新，保留最新一条（rn=1）
CREATE TABLE IF NOT EXISTS dwd_order AS
SELECT
    order_id, user_id, store_id, order_date, order_time,
    pay_amount, discount_amount, pay_type, order_status, channel
FROM (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY order_time DESC, pay_amount DESC
        ) AS rn
    FROM ods_order
) t
WHERE rn = 1;

-- ---------- 3. 去重前后行数差异 ----------
SELECT
    (SELECT COUNT(*) FROM ods_order) AS before_dedup,
    (SELECT COUNT(*) FROM dwd_order) AS after_dedup,
    (SELECT COUNT(*) FROM ods_order) - (SELECT COUNT(*) FROM dwd_order) AS removed_rows;

-- 4. 验证：dwd_order 中主键不再重复
SELECT COUNT(*) AS residual_dup
FROM (SELECT order_id FROM dwd_order GROUP BY order_id HAVING COUNT(*) > 1) t;
