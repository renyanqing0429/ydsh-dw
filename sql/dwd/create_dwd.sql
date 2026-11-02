-- ============================================================
-- 第 2 周 子任务 5/6：DWD 明细层建模（维度表 + 事实表）
-- ------------------------------------------------------------
-- 建模方式：星型模型
--   事实表：dwd_order（订单事实，订单粒度）、dwd_order_item（订单明细事实，商品粒度）
--           dwd_user_behavior（用户行为事实，行为粒度）
--   维度表：dim_user / dim_product / dim_store / dim_date
--           + 编码映射维度：dim_*_code（见 sql/clean/split_merge.sql）
-- 存储：全部 STORED AS ORC（列式存储 + 压缩，减少 IO）
-- 分区：事实表按日期分区（订单按 order_date，行为按 behavior_date）
-- 分桶：dwd_user_behavior_bucket —— 按 user_id 分 8 桶，演示分桶表
-- 命名规范：库 ydsh_dwd；表前缀 dim_（维度）/ dwd_（事实）；stg_（清洗中间层）
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_dwd;
USE ydsh_dwd;

-- ---------- 1. 维度表 ----------
DROP TABLE IF EXISTS ydsh_dwd.dim_user;
CREATE TABLE ydsh_dwd.dim_user (
    user_id          STRING  COMMENT '用户ID（主键）',
    user_name        STRING  COMMENT '用户名',
    gender           STRING  COMMENT '性别：男/女/未知',
    age              INT     COMMENT '年龄（已修正到 1~120）',
    age_band         STRING  COMMENT '年龄段：18岁以下/18-25/26-35/36-45/46-60/60岁以上',
    province         STRING  COMMENT '省份',
    city             STRING  COMMENT '城市',
    region           STRING  COMMENT '地域（省份-城市，合并字段）',
    register_date    STRING  COMMENT '注册日期 yyyy-MM-dd',
    member_level     STRING  COMMENT '会员等级（标准化）',
    level_weight     INT     COMMENT '等级权重 1~4',
    phone            STRING  COMMENT '手机号（11位纯数字）',
    email            STRING  COMMENT '邮箱',
    is_email_missing INT     COMMENT '邮箱是否缺失 1=缺失'
) COMMENT '用户维度表'
STORED AS ORC;

DROP TABLE IF EXISTS ydsh_dwd.dim_product;
CREATE TABLE ydsh_dwd.dim_product (
    product_id    STRING  COMMENT '商品ID（主键）',
    product_name  STRING  COMMENT '商品名称',
    category      STRING  COMMENT '一级类目',
    sub_category  STRING  COMMENT '二级类目',
    brand         STRING  COMMENT '品牌',
    price         DOUBLE  COMMENT '售价（异常已修正）',
    price_band    STRING  COMMENT '价格带：0-100/100-500/500-2000/2000以上',
    cost          DOUBLE  COMMENT '成本价',
    stock         INT     COMMENT '库存',
    status        STRING  COMMENT '商品状态：在售/下架/缺货',
    launch_date   STRING  COMMENT '上架日期 yyyy-MM-dd'
) COMMENT '商品维度表'
STORED AS ORC;

DROP TABLE IF EXISTS ydsh_dwd.dim_store;
CREATE TABLE ydsh_dwd.dim_store (
    store_id   STRING  COMMENT '门店ID（主键）',
    store_name STRING  COMMENT '门店名称',
    province   STRING  COMMENT '省份',
    city       STRING  COMMENT '城市',
    district   STRING  COMMENT '区县',
    address    STRING  COMMENT '详细地址',
    open_date  STRING  COMMENT '开业日期 yyyy-MM-dd',
    area       DOUBLE  COMMENT '门店面积（平方米）',
    manager    STRING  COMMENT '店长'
) COMMENT '门店维度表'
STORED AS ORC;

DROP TABLE IF EXISTS ydsh_dwd.dim_date;
CREATE TABLE ydsh_dwd.dim_date (
    date_id     STRING  COMMENT '日期 yyyy-MM-dd（主键）',
    year        INT     COMMENT '年',
    quarter     INT     COMMENT '季度 1~4',
    month       INT     COMMENT '月 1~12',
    month_key   STRING  COMMENT '年月 yyyy-MM',
    day         INT     COMMENT '日',
    day_of_week INT     COMMENT '周几：1=周一 … 7=周日',
    is_weekend  INT     COMMENT '是否周末 1=是'
) COMMENT '时间维度表（2024 全年）'
STORED AS ORC;

-- ---------- 2. 事实表 ----------
DROP TABLE IF EXISTS ydsh_dwd.dwd_order;
CREATE TABLE ydsh_dwd.dwd_order (
    order_id        STRING  COMMENT '订单ID（主键）',
    user_id         STRING  COMMENT '用户ID → dim_user',
    store_id        STRING  COMMENT '门店ID → dim_store',
    order_timestamp STRING  COMMENT '下单时间戳 yyyy-MM-dd HH:mm:ss（合并字段）',
    order_month     STRING  COMMENT '下单月份 yyyy-MM',
    pay_amount      DOUBLE  COMMENT '支付金额（度量）',
    discount_amount DOUBLE  COMMENT '优惠金额（度量）',
    pay_type        STRING  COMMENT '支付方式（标准化）',
    order_status    STRING  COMMENT '订单状态（标准化）',
    channel         STRING  COMMENT '下单渠道（标准化）',
    is_valid_order  INT     COMMENT '是否有效订单（已完成/已支付=1）',
    is_amount_fixed INT     COMMENT '金额是否经过修正 1=是'
) COMMENT '订单事实表（订单粒度）'
PARTITIONED BY (order_date STRING COMMENT '下单日期，分区字段')
STORED AS ORC;

DROP TABLE IF EXISTS ydsh_dwd.dwd_order_item;
CREATE TABLE ydsh_dwd.dwd_order_item (
    item_id     STRING  COMMENT '明细ID（主键）',
    order_id    STRING  COMMENT '订单ID → dwd_order',
    user_id     STRING  COMMENT '用户ID → dim_user',
    product_id  STRING  COMMENT '商品ID → dim_product',
    quantity    INT     COMMENT '购买数量（度量）',
    unit_price  DOUBLE  COMMENT '单价（度量）',
    discount    DOUBLE  COMMENT '折扣率',
    item_amount DOUBLE  COMMENT '明细金额 = 单价 × 数量 × (1 - 折扣率)'
) COMMENT '订单明细事实表（商品粒度，含 product_id，供品类分析）'
PARTITIONED BY (order_date STRING COMMENT '下单日期，分区字段')
STORED AS ORC;

DROP TABLE IF EXISTS ydsh_dwd.dwd_user_behavior;
CREATE TABLE ydsh_dwd.dwd_user_behavior (
    behavior_id   STRING COMMENT '行为ID（主键）',
    user_id       STRING COMMENT '用户ID → dim_user',
    product_id    STRING COMMENT '商品ID → dim_product',
    behavior_type STRING COMMENT '行为类型（标准化）',
    is_conversion INT    COMMENT '是否转化行为（购买=1）',
    behavior_time STRING COMMENT '行为时间 yyyy-MM-dd HH:mm:ss',
    behavior_hour STRING COMMENT '行为小时 00~23',
    session_id    STRING COMMENT '会话ID'
) COMMENT '用户行为事实表（行为粒度）'
PARTITIONED BY (behavior_date STRING COMMENT '行为日期，分区字段')
STORED AS ORC;

-- 分桶表（演示）：按 user_id 分 8 桶，桶内按时间排序
DROP TABLE IF EXISTS ydsh_dwd.dwd_user_behavior_bucket;
CREATE TABLE ydsh_dwd.dwd_user_behavior_bucket (
    behavior_id   STRING COMMENT '行为ID',
    user_id       STRING COMMENT '用户ID',
    product_id    STRING COMMENT '商品ID',
    behavior_type STRING COMMENT '行为类型',
    behavior_time STRING COMMENT '行为时间',
    session_id    STRING COMMENT '会话ID'
) COMMENT '用户行为事实表（按 user_id 分 8 桶，用于用户级聚合与采样优化）'
PARTITIONED BY (behavior_date STRING COMMENT '行为日期，分区字段')
CLUSTERED BY (user_id) SORTED BY (behavior_time ASC) INTO 8 BUCKETS
STORED AS ORC;

-- ---------- 3. 建表验证 ----------
SHOW TABLES IN ydsh_dwd;
DESC ydsh_dwd.dwd_order;
