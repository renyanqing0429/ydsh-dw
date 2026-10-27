-- ============================================================
-- 云购生活新零售企业数仓 —— ODS 贴源层建表脚本
-- 数据库：ydsh_ods
-- 说明：
--   1. 所有表字段以《项目总说明与模拟数据字典》为准；
--      ⚠️ 若与数据字典有出入，请以字典为准修改后重新执行。
--   2. CSV 为逗号分隔、首行为表头，建表统一 skip.header.line.count=1。
--   3. 执行方式（beeline 内）：source /sql/ods/create_ods.sql;
--      或逐条复制执行。
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_ods;
USE ydsh_ods;

-- 1. 用户表 --------------------------------------------------
CREATE TABLE IF NOT EXISTS ods_user (
    user_id        STRING COMMENT '用户ID',
    user_name      STRING COMMENT '用户名',
    gender         STRING COMMENT '性别',
    age            INT    COMMENT '年龄（含脏数据：空/负/超120）',
    city           STRING COMMENT '城市',
    province       STRING COMMENT '省份',
    register_date  STRING COMMENT '注册日期',
    member_level   STRING COMMENT '会员等级',
    phone          STRING COMMENT '手机号',
    email          STRING COMMENT '邮箱（可能缺失）'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count'='1');

-- 2. 商品表 --------------------------------------------------
CREATE TABLE IF NOT EXISTS ods_product (
    product_id    STRING          COMMENT '商品ID',
    product_name  STRING          COMMENT '商品名称',
    category      STRING          COMMENT '商品类目',
    sub_category  STRING          COMMENT '子类目',
    brand         STRING          COMMENT '品牌',
    price         DECIMAL(10,2)   COMMENT '售价（可能空/负）',
    cost          DECIMAL(10,2)   COMMENT '成本价',
    stock         INT             COMMENT '库存',
    status        STRING          COMMENT '商品状态（在售/下架/缺货，含非法值）',
    launch_date   STRING          COMMENT '上架日期（可能缺失）'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count'='1');

-- 3. 门店表 --------------------------------------------------
CREATE TABLE IF NOT EXISTS ods_store (
    store_id    STRING          COMMENT '门店ID',
    store_name  STRING          COMMENT '门店名称',
    province    STRING          COMMENT '省份',
    city        STRING          COMMENT '城市',
    district    STRING          COMMENT '区县',
    address     STRING          COMMENT '详细地址',
    open_date   STRING          COMMENT '开业日期',
    area        DECIMAL(10,2)   COMMENT '门店面积（平方米）',
    manager     STRING          COMMENT '店长'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count'='1');

-- 4. 订单表 --------------------------------------------------
CREATE TABLE IF NOT EXISTS ods_order (
    order_id         STRING         COMMENT '订单ID（主键，含重复）',
    user_id          STRING         COMMENT '用户ID',
    store_id         STRING         COMMENT '门店ID',
    order_date       STRING         COMMENT '下单日期',
    order_time       STRING         COMMENT '下单时间',
    pay_amount       DECIMAL(10,2)  COMMENT '支付金额（可能空/负）',
    discount_amount  DECIMAL(10,2)  COMMENT '优惠金额',
    pay_type         STRING         COMMENT '支付方式（枚举校验点）',
    order_status     STRING         COMMENT '订单状态（枚举校验点）',
    channel          STRING         COMMENT '下单渠道（枚举校验点）'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count'='1');

-- 5. 订单明细表 ----------------------------------------------
CREATE TABLE IF NOT EXISTS ods_order_item (
    item_id     STRING         COMMENT '明细ID',
    order_id    STRING         COMMENT '订单ID',
    product_id  STRING         COMMENT '商品ID',
    quantity    INT            COMMENT '购买数量',
    unit_price  DECIMAL(10,2)  COMMENT '单价',
    discount    DECIMAL(5,2)   COMMENT '折扣率（如 0.12）'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count'='1');

-- 6. 用户行为表 ----------------------------------------------
CREATE TABLE IF NOT EXISTS ods_user_behavior (
    behavior_id    STRING COMMENT '行为ID',
    user_id        STRING COMMENT '用户ID',
    product_id     STRING COMMENT '商品ID',
    behavior_type  STRING COMMENT '行为类型（buy/view/加购/收藏等，中英混合，枚举校验点）',
    behavior_time  STRING COMMENT '行为时间 yyyy-MM-dd HH:mm:ss',
    session_id     STRING COMMENT '会话ID'
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
TBLPROPERTIES ('skip.header.line.count'='1');

-- 建表验证 ----------------------------------------------------
SHOW TABLES IN ydsh_ods;
DESC ydsh_ods.ods_user;
