-- ============================================================
-- 第 2 周 子任务 1：枚举字段标准化
-- ------------------------------------------------------------
-- 目标字段：
--   ods_user.gender        → 男 / 女 / 未知
--   ods_user.member_level  → 钻石会员 / 金卡会员 / 银卡会员 / 普通会员
--   ods_order.pay_type     → 微信支付 / 支付宝 / 银行卡 / 货到付款 / 其他
--   ods_order.order_status → 待支付 / 已支付 / 已完成 / 已取消 / 退款中 / 其他
--   ods_order.channel      → APP / 小程序 / PC官网 / 门店
--   ods_user_behavior.behavior_type → 浏览 / 加购 / 收藏 / 购买
--   ods_product.category / brand / sub_category → 去首尾空格、统一大小写
-- 输入：ydsh_ods.*（订单取第 1 周去重结果 ydsh_ods.dwd_order）
-- 输出：ydsh_dwd.stg_user_enum / stg_product_enum / stg_order_enum / stg_behavior_enum
-- 执行：docker exec hive-server beeline -u jdbc:hive2://localhost:10000 -f /sql/clean/standardize_enum.sql
-- 验证标准：各枚举字段 distinct 取值收敛到 2~5 个规范值
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;

-- ---------- 1. 清洗前诊断：列出各枚举字段全部取值 ----------
-- 说明：先 select distinct 全部取值，再逐一映射，避免 case when 分支遗漏
SELECT 'gender' AS field, gender AS raw_value, COUNT(*) AS cnt
FROM ydsh_ods.ods_user GROUP BY gender
UNION ALL SELECT 'member_level', member_level, COUNT(*) FROM ydsh_ods.ods_user GROUP BY member_level
ORDER BY field, cnt DESC;

SELECT 'pay_type' AS field, pay_type AS raw_value, COUNT(*) AS cnt
FROM ydsh_ods.dwd_order GROUP BY pay_type
UNION ALL SELECT 'order_status', order_status, COUNT(*) FROM ydsh_ods.dwd_order GROUP BY order_status
UNION ALL SELECT 'channel', channel, COUNT(*) FROM ydsh_ods.dwd_order GROUP BY channel
ORDER BY field, cnt DESC;

SELECT 'behavior_type' AS field, behavior_type AS raw_value, COUNT(*) AS cnt
FROM ydsh_ods.ods_user_behavior GROUP BY behavior_type ORDER BY cnt DESC;

SELECT 'category' AS field, CONCAT('[', category, ']') AS raw_value, COUNT(*) AS cnt
FROM ydsh_ods.ods_product GROUP BY category ORDER BY cnt DESC;

-- ---------- 2. 用户表枚举标准化 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_user_enum;
CREATE TABLE ydsh_dwd.stg_user_enum AS
SELECT
    user_id,
    user_name,
    CASE
        WHEN LOWER(TRIM(gender)) IN ('男', 'm', 'male')   THEN '男'
        WHEN LOWER(TRIM(gender)) IN ('女', 'f', 'female') THEN '女'
        ELSE '未知'
    END AS gender,
    age,
    city,
    province,
    register_date,
    CASE
        WHEN LOWER(TRIM(member_level)) IN ('钻石会员', '钻石', 'diamond') THEN '钻石会员'
        WHEN LOWER(TRIM(member_level)) IN ('金卡会员', '金卡', 'gold')    THEN '金卡会员'
        WHEN LOWER(TRIM(member_level)) IN ('银卡会员', '银卡', 'silver')  THEN '银卡会员'
        ELSE '普通会员'
    END AS member_level,
    phone,
    email
FROM ydsh_ods.ods_user;

-- ---------- 3. 商品表标准化（去首尾空格 / 统一大小写） ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_product_enum;
CREATE TABLE ydsh_dwd.stg_product_enum AS
SELECT
    product_id,
    product_name,
    TRIM(category)                          AS category,
    TRIM(sub_category)                      AS sub_category,
    -- 品牌：中文保持原样；英文统一为「首字母大写」形式（当前数据均为中文品牌，规则用于扩展数据）
    CASE
        WHEN brand RLIKE '^[a-zA-Z ]+$' THEN INITCAP(TRIM(brand))
        ELSE TRIM(brand)
    END                                     AS brand,
    price,
    cost,
    stock,
    TRIM(status)                            AS status,
    launch_date
FROM ydsh_ods.ods_product;

-- ---------- 4. 订单表枚举标准化（基于第 1 周去重结果 dwd_order） ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_order_enum;
CREATE TABLE ydsh_dwd.stg_order_enum AS
SELECT
    order_id,
    user_id,
    store_id,
    order_date,
    order_time,
    pay_amount,
    discount_amount,
    -- 支付方式：英文编码与中文简称统一到规范中文名
    CASE
        WHEN LOWER(TRIM(pay_type)) IN ('微信支付', 'wechat', '微信') THEN '微信支付'
        WHEN LOWER(TRIM(pay_type)) IN ('支付宝', 'alipay', '支付宝支付') THEN '支付宝'
        WHEN LOWER(TRIM(pay_type)) IN ('银行卡', 'bankcard', 'card')  THEN '银行卡'
        WHEN LOWER(TRIM(pay_type)) IN ('货到付款', 'cod')             THEN '货到付款'
        ELSE '其他'
    END AS pay_type,
    -- 订单状态：数字编码 1/2/3/4 与英文 cancelled 统一到规范中文名
    CASE
        WHEN LOWER(TRIM(order_status)) IN ('已完成', '完成', '4', 'finished') THEN '已完成'
        WHEN LOWER(TRIM(order_status)) IN ('已支付', '已付款', '2', 'paid')   THEN '已支付'
        WHEN LOWER(TRIM(order_status)) IN ('待支付', '1', 'unpaid')           THEN '待支付'
        WHEN LOWER(TRIM(order_status)) IN ('已取消', '3', 'cancelled')        THEN '已取消'
        WHEN LOWER(TRIM(order_status)) IN ('退款中', '5', 'refunding')        THEN '退款中'
        ELSE '其他'
    END AS order_status,
    -- 渠道：大小写统一
    CASE
        WHEN LOWER(TRIM(channel)) IN ('app')   THEN 'APP'
        WHEN LOWER(TRIM(channel)) IN ('pc', 'pc官网', 'web') THEN 'PC官网'
        WHEN LOWER(TRIM(channel)) IN ('小程序', 'mini')       THEN '小程序'
        WHEN LOWER(TRIM(channel)) IN ('门店', 'store')        THEN '门店'
        ELSE '其他'
    END AS channel
FROM ydsh_ods.dwd_order;

-- ---------- 5. 用户行为表枚举标准化 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_behavior_enum;
CREATE TABLE ydsh_dwd.stg_behavior_enum AS
SELECT
    behavior_id,
    user_id,
    product_id,
    CASE
        WHEN LOWER(TRIM(behavior_type)) IN ('浏览', 'pv', 'view')      THEN '浏览'
        WHEN LOWER(TRIM(behavior_type)) IN ('加购', 'cart')            THEN '加购'
        WHEN LOWER(TRIM(behavior_type)) IN ('收藏', 'fav', 'favorite') THEN '收藏'
        WHEN LOWER(TRIM(behavior_type)) IN ('购买', 'buy')             THEN '购买'
        ELSE '其他'
    END AS behavior_type,
    behavior_time,
    session_id
FROM ydsh_ods.ods_user_behavior;

-- ---------- 6. 标准化效果验证（取值集合应收敛） ----------
SELECT 'gender' AS field, gender AS std_value, COUNT(*) AS cnt
FROM ydsh_dwd.stg_user_enum GROUP BY gender
UNION ALL SELECT 'member_level', member_level, COUNT(*) FROM ydsh_dwd.stg_user_enum GROUP BY member_level
ORDER BY field, cnt DESC;

SELECT 'pay_type' AS field, pay_type AS std_value, COUNT(*) AS cnt
FROM ydsh_dwd.stg_order_enum GROUP BY pay_type
UNION ALL SELECT 'order_status', order_status, COUNT(*) FROM ydsh_dwd.stg_order_enum GROUP BY order_status
UNION ALL SELECT 'channel', channel, COUNT(*) FROM ydsh_dwd.stg_order_enum GROUP BY channel
ORDER BY field, cnt DESC;

SELECT 'behavior_type' AS field, behavior_type AS std_value, COUNT(*) AS cnt
FROM ydsh_dwd.stg_behavior_enum GROUP BY behavior_type ORDER BY cnt DESC;

-- 类目是否已无首尾空格残留（期望返回 0 行）
SELECT 'category_blank' AS chk, COUNT(*) AS cnt
FROM ydsh_dwd.stg_product_enum
WHERE category <> TRIM(category) OR sub_category <> TRIM(sub_category) OR brand <> TRIM(brand);
