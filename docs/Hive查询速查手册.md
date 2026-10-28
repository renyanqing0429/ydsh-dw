# Hive 查询速查手册（第 1 周成果验证 / 答辩演示用）

> 环境：三容器运行中，HiveServer2 端口 10000，库名 `ydsh_ods`。
> 所有语句在 beeline 中执行（进入方式见下）。

## 进入 beeline（三种任选其一）

```bash
# 方式一：Git Bash（推荐）
docker exec -it hive-server beeline -u jdbc:hive2://localhost:10000

# 方式二：Docker Desktop → hive-server 容器 → Exec 标签 → bash，再敲上一行

# 方式三：DBeaver 图形客户端（需另装），连接参数：
#   主机 localhost  端口 10000  用户名 hive  密码空
```

进入后提示符为 `0: jdbc:hive2://localhost:10000>`，每条语句以 `;` 结尾回车执行。
退出输入 `!q`。

## 一、看库看表

```sql
SHOW DATABASES;
USE ydsh_ods;
SHOW TABLES;                       -- 9 张表：6 ods + 3 dwd
DESC ods_order;                    -- 看表结构
SELECT * FROM ods_order LIMIT 10;  -- 抽样
```

## 二、行数核验（与手册对照）

| 表 | 预期 |
|---|---|
| ods_user / ods_product / ods_store | 1000 / 600 / 60 |
| ods_order / ods_order_item / ods_user_behavior | 15600 / 37549 / 60000 |
| dwd_user / dwd_product / dwd_order | 1000 / 600 / 15000 |

```sql
SELECT COUNT(*) FROM ods_order;
```

> ⚠️ 多张表 count 不要用一条大 union all 查——会触发 Tez 计数器上限（Too many counters: 121 max=120），逐表查即可。

## 三、答辩演示常用查询

```sql
-- 1. 清洗效果：清洗前 age 异常 78 条，清洗后 0
SELECT COUNT(*) FROM dwd_user WHERE age < 1 OR age > 120 OR age IS NULL;

-- 2. 去重效果：15600 → 15000，复检主键无重复
SELECT COUNT(*) AS residual_dup FROM
  (SELECT order_id FROM dwd_order GROUP BY order_id HAVING COUNT(*) > 1) t;

-- 3. 订单状态分布（可见脏值：数字 1~4 / 已完成 / cancelled 混用）
SELECT order_status, COUNT(*) cnt FROM ods_order
GROUP BY order_status ORDER BY cnt DESC;

-- 4. 支付方式分布（可见 微信/微信支付/支付宝/alipay 混用）
SELECT pay_type, COUNT(*) cnt FROM ods_order
GROUP BY pay_type ORDER BY cnt DESC;

-- 5. 日期格式混乱（斜杠日期 1902 行）
SELECT
  SUM(CASE WHEN order_date LIKE '____/__/__' THEN 1 ELSE 0 END) AS slash_date,
  SUM(CASE WHEN order_date LIKE '____-__-__' THEN 1 ELSE 0 END) AS dash_date
FROM ods_order;

-- 6. 每月订单量趋势（为下周指标计算做铺垫）
SELECT SUBSTR(order_date, 1, 7) AS month, COUNT(*) AS orders
FROM ods_order GROUP BY SUBSTR(order_date, 1, 7) ORDER BY month;

-- 7. 门店销售额 TOP10（join 演示）
SELECT s.store_name, COUNT(*) AS orders, ROUND(SUM(o.pay_amount), 2) AS gmv
FROM ods_order o JOIN ods_store s ON o.store_id = s.store_id
GROUP BY s.store_name ORDER BY gmv DESC LIMIT 10;
```

## 四、一键流水线

```bash
# Git Bash，在项目根目录
bash tools/run_pipeline.sh all      # 全流程：建表→导入→扫描→清洗
bash tools/run_pipeline.sh quality  # 只重跑质量扫描
```

> 前提：Docker Desktop 已启动。若 hive-server 报 "Stop it first"（陈旧 PID），
> 用 `docker compose down && docker compose up -d` 重建，不要用 restart。

## 五、下周待办（清洗二预告）

- 枚举归一化：pay_type / order_status / gender / behavior_type 约三个版本混用，共约 2500 行
- 日期统一：`2024/04/02` → `2024-04-02`，共 1902 行
