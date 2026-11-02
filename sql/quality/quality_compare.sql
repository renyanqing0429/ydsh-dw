-- ============================================================
-- 第 2 周 子任务 4：清洗前（ODS）vs 清洗后（DWD）数据质量对比
-- ------------------------------------------------------------
-- 五类脏数据：缺失值 / 重复值 / 格式错误 / 枚举不规范 / 数值异常
-- 修复率口径：修复率 = (清洗前问题数 - 清洗后问题数) / 清洗前问题数 × 100%
-- 口径说明：
--   清洗前 = ODS 原始表（订单 15,600 行）；清洗后 = DWD 结果表（订单去重后 15,000 行）
--   重复值按「重复多出行数」计量；邮箱为业务可选字段，策略是「保留空值 + 打标记」
--   不做物理填充，因此该项修复率按 0 计并在报告中单独说明。
-- 实现说明：按脏数据类别拆分为多条 INSERT，避免单条 UNION ALL 分支过多
--   触发 Tez 计数器上限（Too many counters: 121 max=120）。
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;

DROP TABLE IF EXISTS ydsh_dwd.tmp_quality_before;
CREATE TABLE ydsh_dwd.tmp_quality_before (
    dirty_type STRING COMMENT '脏数据类别',
    item       STRING COMMENT '问题项',
    cnt        BIGINT COMMENT '问题数'
) STORED AS ORC;

DROP TABLE IF EXISTS ydsh_dwd.tmp_quality_after;
CREATE TABLE ydsh_dwd.tmp_quality_after (
    dirty_type STRING COMMENT '脏数据类别',
    item       STRING COMMENT '问题项',
    cnt        BIGINT COMMENT '问题数'
) STORED AS ORC;

-- ---------- 1. 清洗前（ODS）问题计数 ----------
-- 1.1 缺失值
INSERT OVERWRITE TABLE ydsh_dwd.tmp_quality_before
SELECT '缺失值', 'age为空', COUNT(*) FROM ydsh_ods.ods_user WHERE age IS NULL
UNION ALL SELECT '缺失值', 'launch_date为空', COUNT(*)
FROM ydsh_ods.ods_product WHERE launch_date IS NULL OR TRIM(launch_date) = ''
UNION ALL SELECT '缺失值', 'email为空', COUNT(*)
FROM ydsh_ods.ods_user WHERE email IS NULL OR TRIM(email) = '';

-- 1.2 重复值
INSERT INTO TABLE ydsh_dwd.tmp_quality_before
SELECT '重复值', '订单重复多出行', COALESCE(SUM(cnt - 1), 0)
FROM (SELECT order_id, COUNT(*) AS cnt FROM ydsh_ods.ods_order GROUP BY order_id HAVING COUNT(*) > 1) t;

-- 1.3 格式错误
INSERT INTO TABLE ydsh_dwd.tmp_quality_before
SELECT '格式错误', 'register_date非yyyy-MM-dd', COUNT(*)
FROM ydsh_ods.ods_user WHERE register_date IS NULL OR register_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$'
UNION ALL SELECT '格式错误', 'order_date非yyyy-MM-dd', COUNT(*)
FROM ydsh_ods.ods_order WHERE order_date IS NULL OR order_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$'
UNION ALL SELECT '格式错误', 'phone含非数字字符(非11位纯数字)', COUNT(*)
FROM ydsh_ods.ods_user WHERE phone IS NULL OR phone NOT RLIKE '^\\d{11}$'
UNION ALL SELECT '格式错误', 'behavior_time非标准', COUNT(*)
FROM ydsh_ods.ods_user_behavior WHERE behavior_time IS NULL OR behavior_time NOT RLIKE '^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$';

-- 1.4 枚举不规范
INSERT INTO TABLE ydsh_dwd.tmp_quality_before
SELECT '枚举不规范', 'gender', COUNT(*)
FROM ydsh_ods.ods_user WHERE LOWER(TRIM(COALESCE(gender, ''))) NOT IN ('男', '女', '未知')
UNION ALL SELECT '枚举不规范', 'member_level', COUNT(*)
FROM ydsh_ods.ods_user WHERE member_level NOT IN ('钻石会员', '金卡会员', '银卡会员', '普通会员')
UNION ALL SELECT '枚举不规范', 'pay_type', COUNT(*)
FROM ydsh_ods.ods_order WHERE pay_type NOT IN ('微信支付', '支付宝', '银行卡', '货到付款');

INSERT INTO TABLE ydsh_dwd.tmp_quality_before
SELECT '枚举不规范', 'order_status', COUNT(*)
FROM ydsh_ods.ods_order WHERE order_status NOT IN ('待支付', '已支付', '已完成', '已取消', '退款中')
UNION ALL SELECT '枚举不规范', 'channel', COUNT(*)
FROM ydsh_ods.ods_order WHERE channel NOT IN ('APP', '小程序', 'PC官网', '门店')
UNION ALL SELECT '枚举不规范', 'behavior_type', COUNT(*)
FROM ydsh_ods.ods_user_behavior WHERE behavior_type NOT IN ('浏览', '加购', '收藏', '购买');

-- 1.5 数值异常
INSERT INTO TABLE ydsh_dwd.tmp_quality_before
SELECT '数值异常', 'pay_amount<=0或>10000', COUNT(*)
FROM ydsh_ods.ods_order WHERE pay_amount IS NULL OR pay_amount <= 0 OR pay_amount > 10000
UNION ALL SELECT '数值异常', 'discount<0或>pay_amount', COUNT(*)
FROM ydsh_ods.ods_order WHERE discount_amount < 0 OR discount_amount > pay_amount
UNION ALL SELECT '数值异常', 'age不在1~120', COUNT(*)
FROM ydsh_ods.ods_user WHERE age IS NULL OR age < 1 OR age > 120
UNION ALL SELECT '数值异常', 'price<=0', COUNT(*)
FROM ydsh_ods.ods_product WHERE price IS NULL OR price <= 0;

INSERT INTO TABLE ydsh_dwd.tmp_quality_before
SELECT '数值异常', 'quantity<=0', COUNT(*)
FROM ydsh_ods.ods_order_item WHERE quantity IS NULL OR quantity <= 0
UNION ALL SELECT '数值异常', 'unit_price<0', COUNT(*)
FROM ydsh_ods.ods_order_item WHERE unit_price IS NULL OR unit_price < 0;

-- ---------- 2. 清洗后（DWD）问题计数 ----------
-- 2.1 缺失值
INSERT OVERWRITE TABLE ydsh_dwd.tmp_quality_after
SELECT '缺失值', 'age为空', COUNT(*) FROM ydsh_dwd.dim_user WHERE age IS NULL
UNION ALL SELECT '缺失值', 'launch_date为空', COUNT(*)
FROM ydsh_dwd.dim_product WHERE launch_date IS NULL OR TRIM(launch_date) = ''
UNION ALL SELECT '缺失值', 'email为空', COUNT(*)
FROM ydsh_dwd.dim_user WHERE email IS NULL OR TRIM(email) = '';

-- 2.2 重复值
INSERT INTO TABLE ydsh_dwd.tmp_quality_after
SELECT '重复值', '订单重复多出行', COALESCE(SUM(cnt - 1), 0)
FROM (SELECT order_id, COUNT(*) AS cnt FROM ydsh_dwd.dwd_order GROUP BY order_id HAVING COUNT(*) > 1) t;

-- 2.3 格式错误
INSERT INTO TABLE ydsh_dwd.tmp_quality_after
SELECT '格式错误', 'register_date非yyyy-MM-dd', COUNT(*)
FROM ydsh_dwd.dim_user WHERE register_date IS NULL OR register_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$'
UNION ALL SELECT '格式错误', 'order_date非yyyy-MM-dd', COUNT(*)
FROM ydsh_dwd.dwd_order WHERE order_date IS NULL OR order_date NOT RLIKE '^\\d{4}-\\d{2}-\\d{2}$'
UNION ALL SELECT '格式错误', 'phone含非数字字符(非11位纯数字)', COUNT(*)
FROM ydsh_dwd.dim_user WHERE phone IS NULL OR phone NOT RLIKE '^\\d{11}$'
UNION ALL SELECT '格式错误', 'behavior_time非标准', COUNT(*)
FROM ydsh_dwd.dwd_user_behavior WHERE behavior_time IS NULL OR behavior_time NOT RLIKE '^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}$';

-- 2.4 枚举不规范
INSERT INTO TABLE ydsh_dwd.tmp_quality_after
SELECT '枚举不规范', 'gender', COUNT(*)
FROM ydsh_dwd.dim_user WHERE LOWER(TRIM(COALESCE(gender, ''))) NOT IN ('男', '女', '未知')
UNION ALL SELECT '枚举不规范', 'member_level', COUNT(*)
FROM ydsh_dwd.dim_user WHERE member_level NOT IN ('钻石会员', '金卡会员', '银卡会员', '普通会员')
UNION ALL SELECT '枚举不规范', 'pay_type', COUNT(*)
FROM ydsh_dwd.dwd_order WHERE pay_type NOT IN ('微信支付', '支付宝', '银行卡', '货到付款');

INSERT INTO TABLE ydsh_dwd.tmp_quality_after
SELECT '枚举不规范', 'order_status', COUNT(*)
FROM ydsh_dwd.dwd_order WHERE order_status NOT IN ('待支付', '已支付', '已完成', '已取消', '退款中')
UNION ALL SELECT '枚举不规范', 'channel', COUNT(*)
FROM ydsh_dwd.dwd_order WHERE channel NOT IN ('APP', '小程序', 'PC官网', '门店')
UNION ALL SELECT '枚举不规范', 'behavior_type', COUNT(*)
FROM ydsh_dwd.dwd_user_behavior WHERE behavior_type NOT IN ('浏览', '加购', '收藏', '购买');

-- 2.5 数值异常
INSERT INTO TABLE ydsh_dwd.tmp_quality_after
SELECT '数值异常', 'pay_amount<=0或>10000', COUNT(*)
FROM ydsh_dwd.dwd_order WHERE pay_amount IS NULL OR pay_amount <= 0 OR pay_amount > 10000
UNION ALL SELECT '数值异常', 'discount<0或>pay_amount', COUNT(*)
FROM ydsh_dwd.dwd_order WHERE discount_amount < 0 OR discount_amount > pay_amount
UNION ALL SELECT '数值异常', 'age不在1~120', COUNT(*)
FROM ydsh_dwd.dim_user WHERE age IS NULL OR age < 1 OR age > 120
UNION ALL SELECT '数值异常', 'price<=0', COUNT(*)
FROM ydsh_dwd.dim_product WHERE price IS NULL OR price <= 0;

INSERT INTO TABLE ydsh_dwd.tmp_quality_after
SELECT '数值异常', 'quantity<=0', COUNT(*)
FROM ydsh_dwd.dwd_order_item WHERE quantity IS NULL OR quantity <= 0
UNION ALL SELECT '数值异常', 'unit_price<0', COUNT(*)
FROM ydsh_dwd.dwd_order_item WHERE unit_price IS NULL OR unit_price < 0;

-- ---------- 3. 明细对比表（问题清单 + 修复率） ----------
SELECT
    b.dirty_type,
    b.item,
    b.cnt AS before_cnt,
    COALESCE(a.cnt, 0) AS after_cnt,
    CASE WHEN b.cnt = 0 THEN 100.00
         ELSE ROUND((b.cnt - COALESCE(a.cnt, 0)) * 100.0 / b.cnt, 2)
    END AS fix_rate_pct
FROM ydsh_dwd.tmp_quality_before b
LEFT JOIN ydsh_dwd.tmp_quality_after a
       ON b.dirty_type = a.dirty_type AND b.item = a.item
ORDER BY b.dirty_type, before_cnt DESC;

-- ---------- 4. 五类汇总（答辩主表） ----------
SELECT
    b.dirty_type,
    SUM(b.cnt) AS before_cnt,
    SUM(COALESCE(a.cnt, 0)) AS after_cnt,
    ROUND((SUM(b.cnt) - SUM(COALESCE(a.cnt, 0))) * 100.0 / SUM(b.cnt), 2) AS fix_rate_pct
FROM ydsh_dwd.tmp_quality_before b
LEFT JOIN ydsh_dwd.tmp_quality_after a
       ON b.dirty_type = a.dirty_type AND b.item = a.item
GROUP BY b.dirty_type
ORDER BY before_cnt DESC;

-- ---------- 4.2 补充口径：缺失值（不含邮箱）修复率 ----------
-- 邮箱为业务可选字段，策略为「保留空值 + 打标记 is_email_missing」，不做物理填充，
-- 因此单独给出剔除邮箱后的缺失值修复率。
SELECT
    '缺失值(不含email)' AS dirty_type,
    SUM(b.cnt) AS before_cnt,
    SUM(COALESCE(a.cnt, 0)) AS after_cnt,
    ROUND((SUM(b.cnt) - SUM(COALESCE(a.cnt, 0))) * 100.0 / SUM(b.cnt), 2) AS fix_rate_pct
FROM ydsh_dwd.tmp_quality_before b
LEFT JOIN ydsh_dwd.tmp_quality_after a
       ON b.dirty_type = a.dirty_type AND b.item = a.item
WHERE b.dirty_type = '缺失值' AND b.item <> 'email为空';

-- ---------- 5. 总量与留存行数对比 ----------
-- 说明：拆成 UNION ALL 单表计数，避免多标量子查询触发 Tez 计数器上限
SELECT 'order_before' AS item, COUNT(*) AS cnt FROM ydsh_ods.ods_order
UNION ALL SELECT 'order_after',     COUNT(*) FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'user_before',     COUNT(*) FROM ydsh_ods.ods_user
UNION ALL SELECT 'user_after',      COUNT(*) FROM ydsh_dwd.dim_user
UNION ALL SELECT 'product_before',  COUNT(*) FROM ydsh_ods.ods_product
UNION ALL SELECT 'product_after',   COUNT(*) FROM ydsh_dwd.dim_product
UNION ALL SELECT 'behavior_before', COUNT(*) FROM ydsh_ods.ods_user_behavior
UNION ALL SELECT 'behavior_after',  COUNT(*) FROM ydsh_dwd.dwd_user_behavior;
