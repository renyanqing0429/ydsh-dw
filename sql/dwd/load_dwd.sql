-- ============================================================
-- 第 2 周 子任务 6：DWD 层数据加载（维度表 + 事实表 + 分区/分桶）
-- ------------------------------------------------------------
-- 前提：已执行 sql/clean/standardize_enum.sql、outlier_format.sql、split_merge.sql
--      已执行 sql/dwd/create_dwd.sql
-- 说明：
--   1. 维度表全量覆盖写入；事实表按日期动态分区写入
--   2. 订单事实表来自去重后的清洗结果，订单明细事实表关联订单取分区日期
--   3. 分桶表 dwd_user_behavior_bucket 演示 CLUSTERED BY 的用法
-- ============================================================

SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;
-- 订单/行为按天分区会产生 366 个分区，需放开默认的 100/1000 上限
SET hive.exec.max.dynamic.partitions = 2000;
SET hive.exec.max.dynamic.partitions.pernode = 2000;
SET hive.enforce.bucketing = true;

USE ydsh_dwd;

-- ---------- 1. 用户维度 ----------
INSERT OVERWRITE TABLE ydsh_dwd.dim_user
SELECT
    user_id,
    user_name,
    gender,
    age,
    CASE
        WHEN age < 18 THEN '18岁以下'
        WHEN age <= 25 THEN '18-25'
        WHEN age <= 35 THEN '26-35'
        WHEN age <= 45 THEN '36-45'
        WHEN age <= 60 THEN '46-60'
        ELSE '60岁以上'
    END AS age_band,
    province_std,
    city_std,
    region,
    register_date,
    member_level,
    level_weight,
    phone,
    email,
    is_email_missing
FROM ydsh_dwd.stg_user_merge;

-- ---------- 2. 商品维度 ----------
INSERT OVERWRITE TABLE ydsh_dwd.dim_product
SELECT
    product_id,
    product_name,
    category,
    sub_category,
    brand,
    price,
    CASE
        WHEN price < 100 THEN '0-100'
        WHEN price < 500 THEN '100-500'
        WHEN price < 2000 THEN '500-2000'
        ELSE '2000以上'
    END AS price_band,
    cost,
    stock,
    status,
    launch_date
FROM ydsh_dwd.stg_product_clean;

-- ---------- 3. 门店维度 ----------
INSERT OVERWRITE TABLE ydsh_dwd.dim_store
SELECT
    store_id, store_name, province, city, district, address, open_date, area, manager
FROM ydsh_dwd.stg_store_clean;

-- ---------- 4. 时间维度（2024 全年 366 天） ----------
INSERT OVERWRITE TABLE ydsh_dwd.dim_date
SELECT
    d                                        AS date_id,
    YEAR(d)                                  AS year,
    CAST(FLOOR((MONTH(d) + 2) / 3) AS INT)   AS quarter,
    MONTH(d)                                 AS month,
    SUBSTR(d, 1, 7)                          AS month_key,
    DAY(d)                                   AS day,
    CAST(PMOD(DATEDIFF(d, '2024-01-01'), 7) + 1 AS INT) AS day_of_week,
    CASE WHEN PMOD(DATEDIFF(d, '2024-01-01'), 7) IN (5, 6) THEN 1 ELSE 0 END AS is_weekend
FROM (
    SELECT DATE_ADD('2024-01-01', pos) AS d
    FROM (SELECT POSEXPLODE(SPLIT(SPACE(365), ' ')) AS (pos, x)) t
) s
ORDER BY date_id;

-- ---------- 5. 订单事实表（动态分区：order_date） ----------
INSERT OVERWRITE TABLE ydsh_dwd.dwd_order PARTITION (order_date)
SELECT
    order_id,
    user_id,
    store_id,
    order_timestamp,
    order_month,
    pay_amount,
    discount_amount,
    pay_type,
    order_status,
    channel,
    is_valid_order,
    CASE WHEN is_amount_negative_fixed = 1 OR is_amount_capped = 1 THEN 1 ELSE 0 END AS is_amount_fixed,
    -- 口径下沉：源数据中取消/退款/待支付订单同样写了 pay_amount（共 5,034 笔、约 1,282.70 万），
    -- 真实业务不应计入 GMV。在此显式置 0，下游 DWS/ADS 直接用有效金额字段，
    -- 不必每层重复写 SUM(CASE WHEN is_valid_order = 1 ...)，也避免漏写导致口径漂移。
    CASE WHEN is_valid_order = 1 THEN pay_amount      ELSE 0 END AS pay_amount_valid,
    CASE WHEN is_valid_order = 1 THEN discount_amount ELSE 0 END AS discount_amount_valid,
    order_date
FROM ydsh_dwd.stg_order_merge;

-- ---------- 6. 订单明细事实表（含 product_id，供品类分析） ----------
INSERT OVERWRITE TABLE ydsh_dwd.dwd_order_item PARTITION (order_date)
SELECT
    i.item_id,
    i.order_id,
    o.user_id,
    i.product_id,
    i.quantity,
    i.unit_price,
    i.discount,
    ROUND(i.unit_price * i.quantity * (1 - COALESCE(i.discount, 0)), 2) AS item_amount,
    o.order_date
FROM ydsh_dwd.stg_order_item_clean i
LEFT JOIN ydsh_dwd.stg_order_merge o ON i.order_id = o.order_id;

-- ---------- 7. 用户行为事实表（动态分区：behavior_date） ----------
INSERT OVERWRITE TABLE ydsh_dwd.dwd_user_behavior PARTITION (behavior_date)
SELECT
    behavior_id,
    user_id,
    product_id,
    behavior_type,
    is_conversion,
    behavior_time,
    behavior_hour,
    session_id,
    behavior_date
FROM ydsh_dwd.stg_behavior_merge;

-- ---------- 8. 分桶表加载（按 user_id 分 8 桶） ----------
INSERT OVERWRITE TABLE ydsh_dwd.dwd_user_behavior_bucket PARTITION (behavior_date)
SELECT
    behavior_id,
    user_id,
    product_id,
    behavior_type,
    behavior_time,
    session_id,
    behavior_date
FROM ydsh_dwd.dwd_user_behavior;

-- ---------- 9. 加载验证 ----------
SELECT 'dim_user' AS tbl, COUNT(*) AS cnt FROM ydsh_dwd.dim_user
UNION ALL SELECT 'dim_product',       COUNT(*) FROM ydsh_dwd.dim_product
UNION ALL SELECT 'dim_store',         COUNT(*) FROM ydsh_dwd.dim_store
UNION ALL SELECT 'dim_date',          COUNT(*) FROM ydsh_dwd.dim_date
UNION ALL SELECT 'dwd_order',         COUNT(*) FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'dwd_order_item',    COUNT(*) FROM ydsh_dwd.dwd_order_item
UNION ALL SELECT 'dwd_user_behavior', COUNT(*) FROM ydsh_dwd.dwd_user_behavior
UNION ALL SELECT 'dwd_user_behavior_bucket', COUNT(*) FROM ydsh_dwd.dwd_user_behavior_bucket;

-- 分区数量（订单按天分区，期望 366 个）
SELECT 'dwd_order_partitions' AS item, COUNT(DISTINCT order_date) AS cnt FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'dwd_behavior_partitions', COUNT(DISTINCT behavior_date) FROM ydsh_dwd.dwd_user_behavior;

-- 分区裁剪演示：带分区条件查询 vs 全表扫描
SELECT COUNT(*) AS orders_2024q1
FROM ydsh_dwd.dwd_order
WHERE order_date >= '2024-01-01' AND order_date <= '2024-03-31';
