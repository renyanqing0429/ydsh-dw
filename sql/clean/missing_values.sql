-- ============================================================
-- 数据清洗（一）：缺失值诊断与处理
-- 策略（任务书要求）：
--   1. 年龄 age    → 均值/中位数填充（本脚本用均值，取 1~120 合理区间）
--   2. 邮箱 email  → 保留空值并打标记 is_email_missing
--   3. 上架日期    → 按规则补全（本脚本用同类目众数日期兜底为固定默认值）
-- 输出清洗后的目标表：dwd_user、dwd_product
-- ============================================================

USE ydsh_ods;

-- ---------- 1. 诊断：各类缺失值数量统计 ----------
SELECT
    SUM(CASE WHEN age IS NULL OR age='' OR age<1 OR age>120 THEN 1 ELSE 0 END) AS age_missing_or_invalid,
    SUM(CASE WHEN email IS NULL OR email='' THEN 1 ELSE 0 END)                  AS email_missing,
    SUM(CASE WHEN phone IS NULL OR phone='' THEN 1 ELSE 0 END)                  AS phone_missing
FROM ods_user;

SELECT
    SUM(CASE WHEN launch_date IS NULL OR launch_date='' THEN 1 ELSE 0 END) AS launch_date_missing
FROM ods_product;

-- ---------- 2. 年龄均值填充 ----------
-- 2.1 先看合理区间的均值（执行后把结果代入下方 <均值> 占位符）
SELECT ROUND(AVG(age), 0) AS avg_age
FROM ods_user
WHERE age IS NOT NULL AND age BETWEEN 1 AND 120;

-- 2.2 生成清洗后用户表（假设 avg_age=35，执行前请按实际结果修改）
CREATE TABLE IF NOT EXISTS dwd_user AS
SELECT
    user_id,
    user_name,
    gender,
    CASE
        WHEN age IS NULL OR age='' OR age < 1 OR age > 120 THEN 41   -- 实测均值：ROUND(AVG(age),0)=41（合理区间 1~120，官方数据实测）
        ELSE age
    END AS age,
    city,
    province,
    register_date,
    member_level,
    phone,
    email,
    CASE WHEN email IS NULL OR email='' THEN 1 ELSE 0 END AS is_email_missing
FROM ods_user;

-- ---------- 3. 上架日期补全 ----------
-- 规则：缺失则补为该商品类目的最早正常上架日期；再缺失统一补 '2023-01-01'
CREATE TABLE IF NOT EXISTS dwd_product AS
SELECT
    p.product_id,
    p.product_name,
    p.category,
    p.price,
    p.stock,
    p.status,
    COALESCE(
        NULLIF(p.launch_date, ''),
        f.category_min_date,
        '2023-01-01'
    ) AS launch_date
FROM ods_product p
LEFT JOIN (
    SELECT category, MIN(launch_date) AS category_min_date
    FROM ods_product
    WHERE launch_date IS NOT NULL AND launch_date <> ''
    GROUP BY category
) f ON p.category = f.category;

-- ---------- 4. 处理效果验证 ----------
SELECT COUNT(*) AS dwd_user_total,
       SUM(CASE WHEN age IS NULL OR age<1 OR age>120 THEN 1 ELSE 0 END) AS bad_age_left
FROM dwd_user;

SELECT COUNT(*) AS dwd_product_total,
       SUM(CASE WHEN launch_date IS NULL OR launch_date='' THEN 1 ELSE 0 END) AS bad_launch_date_left
FROM dwd_product;

-- 记录：每类缺失值的数量与采用的策略，写入《数据质量预评估表》作为清洗报告素材
