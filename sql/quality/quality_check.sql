-- ============================================================
-- 数据质量预评估（五维度）：完整性 / 唯一性 / 有效性 / 一致性 / 准确性
-- 产出：《数据质量预评估表》（docs/数据质量预评估表.md）
-- ⚠️ 枚举合法值以数据字典为准，执行前请核对注释中的合法取值。
-- ============================================================

USE ydsh_ods;

-- ============================================================
-- 一、完整性：各表关键字段空值率
-- ============================================================

-- 1.1 用户表：年龄、邮箱空值数（任务书指定缺失点）
SELECT COUNT(*) AS total,
       SUM(CASE WHEN age   IS NULL OR age=''    THEN 1 ELSE 0 END) AS age_null_cnt,
       SUM(CASE WHEN email IS NULL OR email=''  THEN 1 ELSE 0 END) AS email_null_cnt
FROM ods_user;

-- 1.2 商品表：上架日期空值数（任务书指定缺失点）
SELECT COUNT(*) AS total,
       SUM(CASE WHEN launch_date IS NULL OR launch_date='' THEN 1 ELSE 0 END) AS launch_date_null_cnt
FROM ods_product;

-- 1.3 订单表：支付金额空值/为负
-- 注：pay_amount 为 DECIMAL，CSV 空串载入后即为 NULL，不要与 '' 比较
SELECT COUNT(*) AS total,
       SUM(CASE WHEN pay_amount IS NULL THEN 1 ELSE 0 END) AS pay_amount_null_cnt,
       SUM(CASE WHEN pay_amount < 0 THEN 1 ELSE 0 END)     AS pay_amount_neg_cnt
FROM ods_order;

-- ============================================================
-- 二、唯一性：主键重复率
-- ============================================================

-- 2.1 订单表主键重复（区分整行重复 / 主键重复但内容不同）
SELECT COUNT(*) AS dup_order_id_cnt
FROM (SELECT order_id FROM ods_order GROUP BY order_id HAVING COUNT(*) > 1) t;

SELECT COUNT(*) AS fully_duplicated_rows
FROM (
    SELECT order_id, user_id, store_id, order_date, order_time, pay_amount,
           discount_amount, pay_type, order_status, channel,
           COUNT(*) AS c
    FROM ods_order
    GROUP BY order_id, user_id, store_id, order_date, order_time, pay_amount,
             discount_amount, pay_type, order_status, channel
    HAVING COUNT(*) > 1
) t;

-- 2.2 用户表 / 商品表主键重复
SELECT COUNT(*) AS dup_user_id_cnt
FROM (SELECT user_id FROM ods_user GROUP BY user_id HAVING COUNT(*) > 1) t;

SELECT COUNT(*) AS dup_product_id_cnt
FROM (SELECT product_id FROM ods_product GROUP BY product_id HAVING COUNT(*) > 1) t;

-- ============================================================
-- 三、有效性：枚举取值合法性（先 GROUP BY 看全量取值分布，再对照数据字典判断非法值）
-- ============================================================

SELECT pay_type, COUNT(*) AS cnt FROM ods_order GROUP BY pay_type ORDER BY cnt DESC;
SELECT order_status, COUNT(*) AS cnt FROM ods_order GROUP BY order_status ORDER BY cnt DESC;
SELECT channel, COUNT(*) AS cnt FROM ods_order GROUP BY channel ORDER BY cnt DESC;
SELECT gender, COUNT(*) AS cnt FROM ods_user GROUP BY gender;
SELECT status, COUNT(*) AS cnt FROM ods_product GROUP BY status;
SELECT behavior_type, COUNT(*) AS cnt FROM ods_user_behavior GROUP BY behavior_type;

-- ============================================================
-- 四、一致性：格式是否统一（日期、手机号、省份等）
-- ============================================================

-- 4.1 日期格式非 yyyy-MM-dd 的记录数
SELECT COUNT(*) AS bad_date_cnt
FROM ods_order
WHERE order_date IS NOT NULL AND order_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$';

-- 4.2 手机号非 11 位数字的记录数
SELECT COUNT(*) AS bad_phone_cnt
FROM ods_user
WHERE phone IS NOT NULL AND phone NOT RLIKE '^1\\d{10}$';

-- 4.3 用户表城市/省份是否一一对应（抽查不一致）
SELECT city, province, COUNT(*) AS cnt
FROM ods_user
GROUP BY city, province
HAVING COUNT(DISTINCT province) > 1 OR province IS NULL
ORDER BY cnt DESC;

-- ============================================================
-- 五、准确性：取值是否合理
-- ============================================================

-- 5.1 年龄越界（<1 或 >120 或负数）
SELECT COUNT(*) AS bad_age_cnt
FROM ods_user
WHERE age IS NOT NULL AND (age < 1 OR age > 120);

-- 5.2 金额异常（支付金额为负 / 优惠金额大于支付金额）
SELECT COUNT(*) AS neg_pay_cnt FROM ods_order WHERE pay_amount < 0;

SELECT COUNT(*) AS discount_exceed_cnt
FROM ods_order
WHERE discount_amount > pay_amount;

-- 5.3 订单时间逻辑异常（下单日期晚于当前日期）
SELECT COUNT(*) AS future_order_cnt
FROM ods_order
WHERE order_date > DATE_FORMAT(CURRENT_DATE(), 'yyyy-MM-dd');
