-- ============================================================
-- 第 2 周 子任务 3：字段拆分/合并 + 编码映射维度表
-- ------------------------------------------------------------
-- 1) 订单表 order_date + order_time 合并为完整时间戳 order_timestamp
-- 2) 用户表 province + city 合并为 region（地域）；同时拆出
--    省份 province_std / 城市 city_std 两个独立字段备用
-- 3) 建立编码映射维度表（会员等级、支付方式、订单状态、渠道、行为类型），
--    在 DWD 层通过 LEFT JOIN 完成「原始编码 → 规范中文名称」的转换
-- 输入：ydsh_dwd.stg_*_clean
-- 输出：ydsh_dwd.dim_*_code（编码映射维度表）、stg_order_merge、stg_user_merge
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;
USE ydsh_dwd;

-- ---------- 1. 编码映射维度表（维度表 = 编码 ↔ 中文名称对照） ----------
DROP TABLE IF EXISTS ydsh_dwd.dim_pay_type_code;
CREATE TABLE ydsh_dwd.dim_pay_type_code (
    pay_type_code STRING COMMENT '原始编码（统一小写）',
    pay_type_name STRING COMMENT '规范中文名称'
) STORED AS ORC;
INSERT OVERWRITE TABLE ydsh_dwd.dim_pay_type_code VALUES
('微信支付', '微信支付'), ('wechat', '微信支付'), ('微信', '微信支付'),
('支付宝', '支付宝'),     ('alipay', '支付宝'),   ('支付宝支付', '支付宝'),
('银行卡', '银行卡'),     ('bankcard', '银行卡'), ('card', '银行卡'),
('货到付款', '货到付款'), ('cod', '货到付款');

DROP TABLE IF EXISTS ydsh_dwd.dim_order_status_code;
CREATE TABLE ydsh_dwd.dim_order_status_code (
    order_status_code STRING COMMENT '原始编码（统一小写）',
    order_status_name STRING COMMENT '规范中文名称',
    is_valid_order    INT    COMMENT '是否计入有效订单（1=是）'
) STORED AS ORC;
INSERT OVERWRITE TABLE ydsh_dwd.dim_order_status_code VALUES
('已完成', '已完成', 1), ('完成', '已完成', 1),   ('4', '已完成', 1), ('finished', '已完成', 1),
('已支付', '已支付', 1), ('已付款', '已支付', 1), ('2', '已支付', 1), ('paid', '已支付', 1),
('待支付', '待支付', 0), ('1', '待支付', 0),      ('unpaid', '待支付', 0),
('已取消', '已取消', 0), ('3', '已取消', 0),      ('cancelled', '已取消', 0),
('退款中', '退款中', 0), ('5', '退款中', 0),      ('refunding', '退款中', 0);

DROP TABLE IF EXISTS ydsh_dwd.dim_channel_code;
CREATE TABLE ydsh_dwd.dim_channel_code (
    channel_code STRING COMMENT '原始编码（统一小写）',
    channel_name STRING COMMENT '规范中文名称'
) STORED AS ORC;
INSERT OVERWRITE TABLE ydsh_dwd.dim_channel_code VALUES
('app', 'APP'), ('小程序', '小程序'), ('mini', '小程序'),
('pc', 'PC官网'), ('pc官网', 'PC官网'), ('web', 'PC官网'),
('门店', '门店'), ('store', '门店');

DROP TABLE IF EXISTS ydsh_dwd.dim_member_level_code;
CREATE TABLE ydsh_dwd.dim_member_level_code (
    member_level_code STRING COMMENT '原始编码（统一小写）',
    member_level_name STRING COMMENT '规范中文名称',
    level_weight      INT    COMMENT '等级权重，便于排序（普通1/银2/金3/钻4）'
) STORED AS ORC;
INSERT OVERWRITE TABLE ydsh_dwd.dim_member_level_code VALUES
('钻石会员', '钻石会员', 4), ('钻石', '钻石会员', 4), ('diamond', '钻石会员', 4),
('金卡会员', '金卡会员', 3), ('金卡', '金卡会员', 3), ('gold', '金卡会员', 3),
('银卡会员', '银卡会员', 2), ('银卡', '银卡会员', 2), ('silver', '银卡会员', 2),
('普通会员', '普通会员', 1), ('普通', '普通会员', 1), ('normal', '普通会员', 1);

DROP TABLE IF EXISTS ydsh_dwd.dim_behavior_type_code;
CREATE TABLE ydsh_dwd.dim_behavior_type_code (
    behavior_type_code STRING COMMENT '原始编码（统一小写）',
    behavior_type_name STRING COMMENT '规范中文名称',
    is_conversion      INT    COMMENT '是否转化类行为（购买=1）'
) STORED AS ORC;
INSERT OVERWRITE TABLE ydsh_dwd.dim_behavior_type_code VALUES
('浏览', '浏览', 0), ('pv', '浏览', 0), ('view', '浏览', 0),
('加购', '加购', 0), ('cart', '加购', 0),
('收藏', '收藏', 0), ('fav', '收藏', 0), ('favorite', '收藏', 0),
('购买', '购买', 1), ('buy', '购买', 1);

-- ---------- 2. 订单表：时间字段合并（order_date + order_time → order_timestamp） ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_order_merge;
CREATE TABLE ydsh_dwd.stg_order_merge AS
SELECT
    o.order_id,
    o.user_id,
    o.store_id,
    -- 合并为完整时间戳 yyyy-MM-dd HH:mm:ss
    CONCAT(o.order_date, ' ', o.order_time) AS order_timestamp,
    o.order_date,
    SUBSTR(o.order_date, 1, 7)  AS order_month,
    o.pay_amount,
    o.discount_amount,
    -- 通过编码映射维度表完成「编码 → 规范中文名称」转换
    COALESCE(t.pay_type_name,     '其他') AS pay_type,
    COALESCE(s.order_status_name, '其他') AS order_status,
    COALESCE(c.channel_name,      '其他') AS channel,
    s.is_valid_order,
    o.is_amount_negative_fixed,
    o.is_amount_capped
FROM ydsh_dwd.stg_order_clean o
LEFT JOIN ydsh_dwd.dim_pay_type_code     t ON LOWER(TRIM(o.pay_type))     = t.pay_type_code
LEFT JOIN ydsh_dwd.dim_order_status_code s ON LOWER(TRIM(o.order_status)) = s.order_status_code
LEFT JOIN ydsh_dwd.dim_channel_code      c ON LOWER(TRIM(o.channel))      = c.channel_code;

-- ---------- 3. 用户表：province + city 合并为 region ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_user_merge;
CREATE TABLE ydsh_dwd.stg_user_merge AS
SELECT
    u.user_id,
    u.user_name,
    u.gender,
    u.age,
    u.city      AS city_std,
    u.province  AS province_std,
    -- 合并字段：region = 省份 + 城市
    CONCAT(u.province, '-', u.city) AS region,
    u.register_date,
    COALESCE(m.member_level_name, '普通会员') AS member_level,
    m.level_weight,
    u.phone,
    u.email,
    u.is_email_missing
FROM ydsh_dwd.stg_user_clean u
LEFT JOIN ydsh_dwd.dim_member_level_code m ON LOWER(TRIM(u.member_level)) = m.member_level_code;

-- ---------- 4. 行为表：关联行为编码映射表 + 拆出日期/小时 ----------
DROP TABLE IF EXISTS ydsh_dwd.stg_behavior_merge;
CREATE TABLE ydsh_dwd.stg_behavior_merge AS
SELECT
    b.behavior_id,
    b.user_id,
    b.product_id,
    COALESCE(t.behavior_type_name, '其他') AS behavior_type,
    t.is_conversion,
    b.behavior_time,
    SUBSTR(b.behavior_time, 1, 10) AS behavior_date,
    SUBSTR(b.behavior_time, 12, 2) AS behavior_hour,
    b.session_id
FROM ydsh_dwd.stg_behavior_clean b
LEFT JOIN ydsh_dwd.dim_behavior_type_code t ON LOWER(TRIM(b.behavior_type)) = t.behavior_type_code;

-- ---------- 5. 验证 ----------
SELECT 'order_timestamp_fmt' AS chk, COUNT(*) AS bad_rows
FROM ydsh_dwd.stg_order_merge
WHERE order_timestamp IS NULL
   OR order_timestamp NOT RLIKE '^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$';

SELECT 'code_map_null' AS chk,
       SUM(CASE WHEN pay_type = '其他' THEN 1 ELSE 0 END)     AS pay_type_unmapped,
       SUM(CASE WHEN order_status = '其他' THEN 1 ELSE 0 END) AS status_unmapped,
       SUM(CASE WHEN channel = '其他' THEN 1 ELSE 0 END)      AS channel_unmapped
FROM ydsh_dwd.stg_order_merge;

SELECT behavior_type, COUNT(*) AS cnt FROM ydsh_dwd.stg_behavior_merge GROUP BY behavior_type ORDER BY cnt DESC;
SELECT 'region_sample' AS chk, region, COUNT(*) AS cnt FROM ydsh_dwd.stg_user_merge GROUP BY region ORDER BY cnt DESC LIMIT 10;
