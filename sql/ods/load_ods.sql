-- ============================================================
-- ODS 层数据加载与行数校验
-- 前提：6 张 CSV 已放入宿主机 ./data/ 目录（容器内为 /data/）
--   数据路径（容器内）：/data/ods_user.csv 等
-- 预期行数（不含表头）：
--   ods_user           1000
--   ods_product         600
--   ods_store            60
--   ods_order         15600
--   ods_order_item    37549
--   ods_user_behavior 60000
-- ============================================================

USE ydsh_ods;

-- 1. 加载数据（容器内路径 /data 对应宿主机 ./data）-----------
LOAD DATA LOCAL INPATH '/data/ods_user.csv'          INTO TABLE ods_user;
LOAD DATA LOCAL INPATH '/data/ods_product.csv'       INTO TABLE ods_product;
LOAD DATA LOCAL INPATH '/data/ods_store.csv'         INTO TABLE ods_store;
LOAD DATA LOCAL INPATH '/data/ods_order.csv'         INTO TABLE ods_order;
LOAD DATA LOCAL INPATH '/data/ods_order_item.csv'    INTO TABLE ods_order_item;
LOAD DATA LOCAL INPATH '/data/ods_user_behavior.csv' INTO TABLE ods_user_behavior;

-- 2. 行数校验（与上方预期行数逐一对比，允许脏数据少量偏差）----
SELECT 'ods_user'           AS tbl, COUNT(*) AS cnt FROM ods_user
UNION ALL SELECT 'ods_product',       COUNT(*) FROM ods_product
UNION ALL SELECT 'ods_store',         COUNT(*) FROM ods_store
UNION ALL SELECT 'ods_order',         COUNT(*) FROM ods_order
UNION ALL SELECT 'ods_order_item',    COUNT(*) FROM ods_order_item
UNION ALL SELECT 'ods_user_behavior', COUNT(*) FROM ods_user_behavior;

-- 3. 抽样查看 --------------------------------------------------
SELECT * FROM ods_user  LIMIT 5;
SELECT * FROM ods_order LIMIT 5;
