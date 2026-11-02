-- ============================================================
-- 第 2 周 子任务 2：异常值与格式标准化
-- ------------------------------------------------------------
-- 处理内容：
--   A. 数值异常
--      1) 订单支付金额为负（疑似冲正负号错误） → 取绝对值修正
--      2) 订单支付金额超大（> 1 万元，业务阈值） → 封顶到正常区间 P95（缩尾处理）
--      3) 优惠金额为负 / 大于支付金额      → 负转 0、超过部分钳制到支付金额
--      4) 年龄 <1 或 >120（含空值）        → 用合理区间均值填充
--      5) 商品售价 <= 0 / 为空             → 用同类目平均售价填充
--      6) 明细单价为负 → 取绝对值；购买数量 <= 0 → 置为 1
--   B. 格式标准化
--      1) 日期统一 yyyy-MM-dd（兼容 yyyy/MM/dd 与 yyyyMMdd 两种脏格式）
--      2) 手机号去除分隔符，统一 11 位纯数字
--      3) 行为时间统一 yyyy-MM-dd HH:mm:ss（兼容 yyyy/MM/dd HH:mm 缺秒格式）
-- 输入：ydsh_dwd.stg_*_enum、ydsh_ods.ods_order_item / ods_store
-- 输出：ydsh_dwd.stg_*_clean + ydsh_dwd.tmp_* 阈值/均值辅助表（可追溯）
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;
USE ydsh_dwd;

-- ---------- 0. 动态计算修正基准值（避免硬编码，保证可追溯） ----------
-- 0.1 金额封顶值：正常区间（0 ~ 10000）内的 P95
DROP TABLE IF EXISTS ydsh_dwd.tmp_amount_cap;
CREATE TABLE ydsh_dwd.tmp_amount_cap AS
SELECT ROUND(PERCENTILE_APPROX(CAST(pay_amount AS DOUBLE), 0.95), 2) AS cap_value
FROM ydsh_dwd.stg_order_enum
WHERE pay_amount IS NOT NULL AND pay_amount >= 0 AND pay_amount <= 10000;

-- 0.2 年龄填充值：合理区间（1~120 岁）内的均值
DROP TABLE IF EXISTS ydsh_dwd.tmp_age_mean;
CREATE TABLE ydsh_dwd.tmp_age_mean AS
SELECT ROUND(AVG(age), 0) AS age_mean
FROM ydsh_dwd.stg_user_enum
WHERE age IS NOT NULL AND age BETWEEN 1 AND 120;

-- 0.3 商品同类目平均售价（供 price<=0 填充使用）
DROP TABLE IF EXISTS ydsh_dwd.tmp_category_avg_price;
CREATE TABLE ydsh_dwd.tmp_category_avg_price AS
SELECT category, ROUND(AVG(CAST(price AS DOUBLE)), 2) AS avg_price
FROM ydsh_dwd.stg_product_enum
WHERE price IS NOT NULL AND price > 0
GROUP BY category;

SELECT 'cap_value' AS item, cap_value AS val FROM ydsh_dwd.tmp_amount_cap
UNION ALL SELECT 'age_mean', age_mean FROM ydsh_dwd.tmp_age_mean;

-- ---------- 1. 用户表：年龄异常 + 日期/手机号格式 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_user_clean;
CREATE TABLE ydsh_dwd.stg_user_clean AS
SELECT
    u.user_id,
    u.user_name,
    u.gender,
    CAST(
        CASE
            WHEN u.age IS NULL OR u.age < 1 OR u.age > 120 THEN m.age_mean
            ELSE u.age
        END AS INT
    ) AS age,
    u.city,
    u.province,
    -- 注册日期统一 yyyy-MM-dd
    CASE
        WHEN u.register_date RLIKE '^\\d{4}-\\d{2}-\\d{2}$' THEN u.register_date
        WHEN u.register_date RLIKE '^\\d{4}/\\d{2}/\\d{2}$' THEN REGEXP_REPLACE(u.register_date, '/', '-')
        WHEN u.register_date RLIKE '^\\d{8}$' THEN
            CONCAT(SUBSTR(u.register_date, 1, 4), '-', SUBSTR(u.register_date, 5, 2), '-', SUBSTR(u.register_date, 7, 2))
        ELSE NULL
    END AS register_date,
    u.member_level,
    -- 手机号去分隔符，统一 11 位纯数字
    CASE
        WHEN LENGTH(REGEXP_REPLACE(COALESCE(u.phone, ''), '[^0-9]', '')) = 11
            THEN REGEXP_REPLACE(u.phone, '[^0-9]', '')
        ELSE NULL
    END AS phone,
    u.email,
    CASE WHEN u.email IS NULL OR TRIM(u.email) = '' THEN 1 ELSE 0 END AS is_email_missing
FROM ydsh_dwd.stg_user_enum u
LEFT JOIN ydsh_dwd.tmp_age_mean m ON 1 = 1;

-- ---------- 2. 商品表：售价异常 + 上架日期补全 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_product_clean;
CREATE TABLE ydsh_dwd.stg_product_clean AS
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.sub_category,
    p.brand,
    ROUND(CAST(
        CASE
            WHEN p.price IS NULL OR p.price <= 0 THEN COALESCE(a.avg_price, 0)
            ELSE p.price
        END AS DOUBLE
    ), 2) AS price,
    p.cost,
    p.stock,
    p.status,
    COALESCE(
        NULLIF(CASE
            WHEN p.launch_date RLIKE '^\\d{4}-\\d{2}-\\d{2}$' THEN p.launch_date
            WHEN p.launch_date RLIKE '^\\d{4}/\\d{2}/\\d{2}$' THEN REGEXP_REPLACE(p.launch_date, '/', '-')
            WHEN p.launch_date RLIKE '^\\d{8}$' THEN
                CONCAT(SUBSTR(p.launch_date, 1, 4), '-', SUBSTR(p.launch_date, 5, 2), '-', SUBSTR(p.launch_date, 7, 2))
            ELSE NULL
        END, ''),
        '2023-01-01'
    ) AS launch_date
FROM ydsh_dwd.stg_product_enum p
LEFT JOIN ydsh_dwd.tmp_category_avg_price a ON p.category = a.category;

-- ---------- 3. 门店表：开业日期格式统一 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_store_clean;
CREATE TABLE ydsh_dwd.stg_store_clean AS
SELECT
    store_id, store_name, province, city, district, address,
    CASE
        WHEN open_date RLIKE '^\\d{4}-\\d{2}-\\d{2}$' THEN open_date
        WHEN open_date RLIKE '^\\d{4}/\\d{2}/\\d{2}$' THEN REGEXP_REPLACE(open_date, '/', '-')
        WHEN open_date RLIKE '^\\d{8}$' THEN
            CONCAT(SUBSTR(open_date, 1, 4), '-', SUBSTR(open_date, 5, 2), '-', SUBSTR(open_date, 7, 2))
        ELSE NULL
    END AS open_date,
    area, manager
FROM ydsh_ods.ods_store;

-- ---------- 4. 订单表：金额异常修正 + 日期格式统一 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_order_clean;
CREATE TABLE ydsh_dwd.stg_order_clean AS
SELECT
    f.order_id,
    f.user_id,
    f.store_id,
    f.order_date,
    f.order_time,
    f.pay_amount,
    -- 优惠金额：负值归零；且不得超过「修正后的支付金额」（先封顶金额，再钳制优惠）
    ROUND(CAST(
        CASE
            WHEN f.discount_amount IS NULL OR f.discount_amount < 0 THEN 0
            WHEN f.discount_amount > f.pay_amount THEN f.pay_amount
            ELSE f.discount_amount
        END AS DOUBLE
    ), 2) AS discount_amount,
    f.pay_type,
    f.order_status,
    f.channel,
    f.is_amount_negative_fixed,
    f.is_amount_capped
FROM (
    SELECT
        o.order_id,
        o.user_id,
        o.store_id,
        -- 下单日期统一 yyyy-MM-dd
        CASE
            WHEN o.order_date RLIKE '^\\d{4}-\\d{2}-\\d{2}$' THEN o.order_date
            WHEN o.order_date RLIKE '^\\d{4}/\\d{2}/\\d{2}$' THEN REGEXP_REPLACE(o.order_date, '/', '-')
            WHEN o.order_date RLIKE '^\\d{8}$' THEN
                CONCAT(SUBSTR(o.order_date, 1, 4), '-', SUBSTR(o.order_date, 5, 2), '-', SUBSTR(o.order_date, 7, 2))
            ELSE NULL
        END AS order_date,
        o.order_time,
        -- 支付金额：负值取绝对值；超大值封顶到正常区间 P95
        ROUND(CAST(
            CASE
                WHEN o.pay_amount IS NULL THEN 0
                WHEN o.pay_amount < 0 THEN ABS(o.pay_amount)
                WHEN o.pay_amount > 10000 THEN c.cap_value
                ELSE o.pay_amount
            END AS DOUBLE
        ), 2) AS pay_amount,
        o.discount_amount,
        o.pay_type,
        o.order_status,
        o.channel,
        -- 修正标记位，便于质量报告追溯
        CASE WHEN o.pay_amount < 0 THEN 1 ELSE 0 END AS is_amount_negative_fixed,
        CASE WHEN o.pay_amount > 10000 THEN 1 ELSE 0 END AS is_amount_capped
    FROM ydsh_dwd.stg_order_enum o
    LEFT JOIN ydsh_dwd.tmp_amount_cap c ON 1 = 1
) f;

-- ---------- 5. 订单明细表：数量与单价异常 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_order_item_clean;
CREATE TABLE ydsh_dwd.stg_order_item_clean AS
SELECT
    item_id,
    order_id,
    product_id,
    CASE WHEN quantity IS NULL OR quantity <= 0 THEN 1 ELSE quantity END AS quantity,
    ROUND(CAST(CASE WHEN unit_price IS NULL THEN 0 WHEN unit_price < 0 THEN ABS(unit_price) ELSE unit_price END AS DOUBLE), 2) AS unit_price,
    discount
FROM ydsh_ods.ods_order_item;

-- ---------- 6. 用户行为表：行为时间格式统一 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_behavior_clean;
CREATE TABLE ydsh_dwd.stg_behavior_clean AS
SELECT
    behavior_id,
    user_id,
    product_id,
    behavior_type,
    CASE
        -- yyyy/MM/dd HH:mm（缺秒）→ 补 :00
        WHEN behavior_time RLIKE '^\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2}$' THEN
            CONCAT(REGEXP_REPLACE(SUBSTR(behavior_time, 1, 10), '/', '-'), ' ', SUBSTR(behavior_time, 12, 5), ':00')
        -- yyyy-MM-dd HH:mm:ss 原样保留
        WHEN behavior_time RLIKE '^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$' THEN behavior_time
        -- yyyy/MM/dd HH:mm:ss → 日期部分改横线
        WHEN behavior_time RLIKE '^\\d{4}/\\d{2}/\\d{2} \\d{2}:\\d{2}:\\d{2}$' THEN
            CONCAT(REGEXP_REPLACE(SUBSTR(behavior_time, 1, 10), '/', '-'), SUBSTR(behavior_time, 11))
        ELSE NULL
    END AS behavior_time,
    session_id
FROM ydsh_dwd.stg_behavior_enum;

-- ---------- 7. 标准化效果验证 ----------
SELECT 'discount' AS chk,
       SUM(CASE WHEN discount_amount < 0 OR discount_amount > pay_amount THEN 1 ELSE 0 END) AS bad_discount
FROM ydsh_dwd.stg_order_clean;

SELECT 'pay_amount' AS chk,
       SUM(CASE WHEN pay_amount < 0 THEN 1 ELSE 0 END) AS negative_left,
       SUM(CASE WHEN pay_amount > 10000 THEN 1 ELSE 0 END) AS oversize_left,
       SUM(is_amount_capped) AS capped_rows
FROM ydsh_dwd.stg_order_clean;

SELECT 'order_date_fmt' AS chk, COUNT(*) AS bad_rows
FROM ydsh_dwd.stg_order_clean
WHERE order_date IS NULL OR order_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$';

SELECT 'user_fmt' AS chk,
       SUM(CASE WHEN phone IS NULL OR phone NOT RLIKE '^\\d{11}$' THEN 1 ELSE 0 END) AS bad_phone,
       SUM(CASE WHEN age IS NULL OR age < 1 OR age > 120 THEN 1 ELSE 0 END) AS bad_age,
       SUM(CASE WHEN register_date IS NULL OR register_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$' THEN 1 ELSE 0 END) AS bad_regdate
FROM ydsh_dwd.stg_user_clean;

SELECT 'behavior_fmt' AS chk, COUNT(*) AS bad_rows
FROM ydsh_dwd.stg_behavior_clean
WHERE behavior_time IS NULL OR behavior_time NOT RLIKE '^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$';

SELECT 'product_price' AS chk, SUM(CASE WHEN price IS NULL OR price <= 0 THEN 1 ELSE 0 END) AS bad_price
FROM ydsh_dwd.stg_product_clean;
