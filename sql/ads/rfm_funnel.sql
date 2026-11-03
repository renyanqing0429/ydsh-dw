-- ============================================================
-- 第 2 周 补充（二）：ADS 深化分析——RFM 用户分层 + 双漏斗
-- ------------------------------------------------------------
-- 背景：前一轮 ADS 已落地 7 张表，但用户只做了「按消费额三段分」，
--       缺少行为侧的转化视角。本脚本补三块：
--   1. RFM 模型：用 R（最近一次消费）/ F（消费频次）/ M（消费金额）
--      三维打分（NTILE 五分位），替代单维金额分层，识别「重要价值 / 重要保持 /
--      重要挽留 / 一般发展」等 8 类客群，回答「该对谁做运营」。
--   2. 行为覆盖分布：原计划做「浏览 → 加购 → 收藏 → 购买」转化漏斗，
--      实测 60,000 条行为只落在 58,132 个会话（1.03 条/会话），且四类行为的
--      去重用户数几乎都等于总用户数（1000/1000/995/1000），购买次数甚至大于加购，
--      不满足漏斗必须单调递减的前提 —— 该表是独立随机生成的事件流，不能支撑转化分析。
--      故改为输出「行为构成与覆盖」，并在表内标注 funnel_valid=0，作为数据质量问题证据。
--   3. 订单履约漏斗：提交订单 → 支付成功 → 履约完成，回答
--      「钱在哪一步漏」（源数据有 5,034 笔无效订单仍写了金额）。
-- 口径：
--   金额一律用 dwd 的 pay_amount_valid（无效订单已置 0）；
--   全订单口径的流失金额用原始 pay_amount，只用于说明「漏了多少」。
-- 幂等：全部 INSERT OVERWRITE，可重复执行。
-- ============================================================

CREATE DATABASE IF NOT EXISTS ydsh_ads;
USE ydsh_ads;

-- ---------- 1. RFM 用户明细（一行一用户） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_rfm_user;
CREATE TABLE ydsh_ads.ads_rfm_user (
    user_id          STRING COMMENT '用户ID',
    recency_days     INT    COMMENT 'R：距观测截止日（2024-12-31）的天数，越小越好',
    frequency        BIGINT COMMENT 'F：有效订单笔数',
    monetary         DOUBLE COMMENT 'M：有效订单累计金额',
    avg_order_amount DOUBLE COMMENT '客单价',
    r_score          INT    COMMENT 'R 得分 1~5（5=最近有消费）',
    f_score          INT    COMMENT 'F 得分 1~5（5=频次最高）',
    m_score          INT    COMMENT 'M 得分 1~5（5=金额最高）',
    rfm_code         STRING COMMENT 'RFM 组合码，如 555',
    rfm_seg          STRING COMMENT '客群标签（8 分类）',
    first_order_date STRING COMMENT '首单日期',
    last_order_date  STRING COMMENT '末单日期'
) COMMENT 'ADS RFM 用户明细'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_rfm_user
SELECT
    user_id, recency_days, frequency, monetary, avg_order_amount,
    r_score, f_score, m_score,
    CONCAT(CAST(r_score AS STRING), CAST(f_score AS STRING), CAST(m_score AS STRING)) AS rfm_code,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN '重要价值客户'
        WHEN r_score <  4 AND f_score >= 4 AND m_score >= 4 THEN '重要保持客户'
        WHEN r_score >= 4 AND f_score <  4 AND m_score >= 4 THEN '重要发展客户'
        WHEN r_score <  4 AND f_score <  4 AND m_score >= 4 THEN '重要挽留客户'
        WHEN r_score >= 4 AND f_score >= 4 AND m_score <  4 THEN '一般价值客户'
        WHEN r_score <  4 AND f_score >= 4 AND m_score <  4 THEN '一般保持客户'
        WHEN r_score >= 4 AND f_score <  4 AND m_score <  4 THEN '一般发展客户'
        ELSE '一般挽留客户'
    END AS rfm_seg,
    first_order_date, last_order_date
FROM (
    SELECT
        t.*,
        -- NTILE 五分位：R 按天数倒序（近的落 5 分），F/M 按升序（大的落 5 分）
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM (
        SELECT
            user_id,
            DATEDIFF('2024-12-31', MAX(order_date))         AS recency_days,
            COUNT(*)                                        AS frequency,
            ROUND(SUM(pay_amount_valid), 2)                 AS monetary,
            ROUND(SUM(pay_amount_valid) / COUNT(*), 2)      AS avg_order_amount,
            MIN(order_date)                                 AS first_order_date,
            MAX(order_date)                                 AS last_order_date
        FROM ydsh_dwd.dwd_order
        WHERE is_valid_order = 1
        GROUP BY user_id
    ) t
) s;

SELECT 'ads_rfm_user' AS tbl, COUNT(*) AS user_cnt,
       ROUND(AVG(recency_days), 1) AS avg_recency,
       ROUND(AVG(frequency), 2)    AS avg_freq,
       ROUND(AVG(monetary), 2)     AS avg_monetary
FROM ydsh_ads.ads_rfm_user;

-- ---------- 2. RFM 客群汇总（一行一客群，运营直接用） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_rfm_seg_summary;
CREATE TABLE ydsh_ads.ads_rfm_seg_summary (
    rfm_seg        STRING COMMENT '客群标签',
    user_cnt       BIGINT COMMENT '用户数',
    user_share     DOUBLE COMMENT '用户占比 %',
    avg_recency    DOUBLE COMMENT '平均最近消费间隔（天）',
    avg_frequency  DOUBLE COMMENT '平均消费频次',
    avg_monetary   DOUBLE COMMENT '平均累计消费',
    gmv            DOUBLE COMMENT 'GMV',
    gmv_share      DOUBLE COMMENT 'GMV 占比 %',
    gmv_per_user   DOUBLE COMMENT '人均贡献（= 该群 GMV / 用户数）'
) COMMENT 'ADS RFM 客群汇总'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_rfm_seg_summary
SELECT
    rfm_seg, user_cnt,
    ROUND(user_cnt * 100.0 / SUM(user_cnt) OVER (), 2) AS user_share,
    ROUND(avg_recency, 1), ROUND(avg_frequency, 2), ROUND(avg_monetary, 2),
    gmv,
    ROUND(gmv * 100.0 / SUM(gmv) OVER (), 2)           AS gmv_share,
    ROUND(gmv / NULLIF(user_cnt, 0), 2)                AS gmv_per_user
FROM (
    SELECT
        rfm_seg,
        COUNT(*)                    AS user_cnt,
        AVG(recency_days)           AS avg_recency,
        AVG(frequency)              AS avg_frequency,
        AVG(monetary)               AS avg_monetary,
        SUM(monetary)               AS gmv
    FROM ydsh_ads.ads_rfm_user
    GROUP BY rfm_seg
) t;

SELECT * FROM ydsh_ads.ads_rfm_seg_summary ORDER BY gmv DESC;

-- ---------- 3. 行为构成与覆盖（替代不可用的转化漏斗） ----------
DROP TABLE IF EXISTS ydsh_ads.ads_behavior_coverage;
CREATE TABLE ydsh_ads.ads_behavior_coverage (
    behavior_type   STRING COMMENT '行为类型',
    event_cnt       BIGINT COMMENT '事件次数',
    event_share_pct DOUBLE COMMENT '事件占比 %',
    uv              BIGINT COMMENT '触达用户数（去重）',
    uv_rate_pct     DOUBLE COMMENT '用户覆盖率 % = UV / 总用户数',
    avg_events_uv   DOUBLE COMMENT '人均事件次数',
    total_user_cnt  BIGINT COMMENT '总用户数（含未产生该行为的用户）',
    funnel_valid    INT    COMMENT '能否作为漏斗环节 0=否（不满足单调性）',
    remark          STRING COMMENT '判定说明'
) COMMENT 'ADS 行为构成与覆盖（含漏斗可用性判定）'
STORED AS ORC;

INSERT OVERWRITE TABLE ydsh_ads.ads_behavior_coverage
SELECT
    behavior_type, event_cnt,
    ROUND(event_cnt * 100.0 / SUM(event_cnt) OVER (), 2) AS event_share_pct,
    uv,
    ROUND(uv * 100.0 / total_user_cnt, 2)                AS uv_rate_pct,
    ROUND(event_cnt * 1.0 / uv, 2)                       AS avg_events_uv,
    total_user_cnt,
    0 AS funnel_valid,
    CASE behavior_type
        WHEN '购买' THEN 'UV 覆盖率 100% 且次数(11,969)高于加购(8,286)，违反漏斗单调性'
        WHEN '加购' THEN 'UV 覆盖率 100%，与浏览用户完全重合，不构成独立环节'
        WHEN '收藏' THEN 'UV 995/1000，仅 5 人未收藏，区分度不足'
        ELSE 'UV 覆盖全部用户，漏斗首步无筛选作用'
    END AS remark
FROM (
    SELECT behavior_type, COUNT(*) AS event_cnt, COUNT(DISTINCT user_id) AS uv
    FROM ydsh_dwd.dwd_user_behavior
    GROUP BY behavior_type
) t
CROSS JOIN (SELECT COUNT(DISTINCT user_id) AS total_user_cnt FROM ydsh_dwd.dim_user) u;

SELECT * FROM ydsh_ads.ads_behavior_coverage ORDER BY event_cnt DESC;

-- ---------- 4. 订单履约漏斗（真实可用：提交 → 支付 → 完成） ----------
-- 说明：源数据里「待支付 / 已取消 / 退款中」同样写了 pay_amount，
--       用「原始金额 - 有效金额」可直接量化每一步漏掉多少钱，是本表的核心价值。
DROP TABLE IF EXISTS ydsh_ads.ads_order_funnel;
CREATE TABLE ydsh_ads.ads_order_funnel (
    step_no        INT    COMMENT '步骤序号',
    step_name      STRING COMMENT '阶段名',
    order_cnt      BIGINT COMMENT '订单数',
    order_amount   DOUBLE COMMENT '金额（原始口径）',
    rate_from_prev DOUBLE COMMENT '相对上一步转化率 %',
    rate_from_top  DOUBLE COMMENT '相对首步转化率 %',
    lost_cnt       BIGINT COMMENT '本步到下一步流失订单数',
    lost_amount    DOUBLE COMMENT '本步到下一步流失金额',
    remark         STRING COMMENT '流失构成说明'
) COMMENT 'ADS 订单履约漏斗'
STORED AS ORC;

-- 注：Hive 4 不支持 INSERT ... WITH ... SELECT，聚合子查询在三个分支内联（表仅 1.5 万行，代价可忽略）
INSERT OVERWRITE TABLE ydsh_ads.ads_order_funnel
SELECT
    step_no, step_name, order_cnt, order_amount,
    ROUND(rate_from_prev, 2) AS rate_from_prev,
    ROUND(rate_from_top, 2)  AS rate_from_top,
    lost_cnt, ROUND(lost_amount, 2) AS lost_amount, remark
FROM (
    SELECT 1 AS step_no, '提交订单' AS step_name,
           total_cnt AS order_cnt, total_amount AS order_amount,
           CAST(NULL AS DOUBLE) AS rate_from_prev, 100.0 AS rate_from_top,
           total_cnt - paid_cnt AS lost_cnt, total_amount - paid_amount AS lost_amount,
           CONCAT('待支付 ', CAST(wait_pay_cnt AS STRING), ' 笔 + 已取消 ',
                  CAST(cancel_cnt AS STRING), ' 笔 + 退款中 ',
                  CAST(refund_cnt AS STRING), ' 笔') AS remark
    FROM (
            SELECT
                COUNT(*)                                                             AS total_cnt,
                ROUND(SUM(pay_amount), 2)                                            AS total_amount,
                SUM(CASE WHEN order_status IN ('已支付', '已完成') THEN 1 ELSE 0 END) AS paid_cnt,
                ROUND(SUM(pay_amount_valid), 2)                                      AS paid_amount,
                SUM(CASE WHEN order_status = '已完成' THEN 1 ELSE 0 END)             AS done_cnt,
                ROUND(SUM(CASE WHEN order_status = '已完成' THEN pay_amount ELSE 0 END), 2) AS done_amount,
                SUM(CASE WHEN order_status = '待支付' THEN 1 ELSE 0 END)             AS wait_pay_cnt,
                SUM(CASE WHEN order_status = '已取消' THEN 1 ELSE 0 END)             AS cancel_cnt,
                SUM(CASE WHEN order_status = '退款中' THEN 1 ELSE 0 END)             AS refund_cnt
            FROM ydsh_dwd.dwd_order
        ) a
    UNION ALL
    SELECT 2, '支付成功',
           paid_cnt, paid_amount,
           paid_cnt * 100.0 / total_cnt, paid_cnt * 100.0 / total_cnt,
           paid_cnt - done_cnt, paid_amount - done_amount,
           CONCAT('已支付但未完成履约 ', CAST(paid_cnt - done_cnt AS STRING), ' 笔')
    FROM (
            SELECT
                COUNT(*)                                                             AS total_cnt,
                ROUND(SUM(pay_amount), 2)                                            AS total_amount,
                SUM(CASE WHEN order_status IN ('已支付', '已完成') THEN 1 ELSE 0 END) AS paid_cnt,
                ROUND(SUM(pay_amount_valid), 2)                                      AS paid_amount,
                SUM(CASE WHEN order_status = '已完成' THEN 1 ELSE 0 END)             AS done_cnt,
                ROUND(SUM(CASE WHEN order_status = '已完成' THEN pay_amount ELSE 0 END), 2) AS done_amount,
                SUM(CASE WHEN order_status = '待支付' THEN 1 ELSE 0 END)             AS wait_pay_cnt,
                SUM(CASE WHEN order_status = '已取消' THEN 1 ELSE 0 END)             AS cancel_cnt,
                SUM(CASE WHEN order_status = '退款中' THEN 1 ELSE 0 END)             AS refund_cnt
            FROM ydsh_dwd.dwd_order
        ) b
    UNION ALL
    SELECT 3, '履约完成',
           done_cnt, done_amount,
           done_cnt * 100.0 / paid_cnt, done_cnt * 100.0 / total_cnt,
           0, 0.00, '已完成，视为最终成交'
    FROM (
            SELECT
                COUNT(*)                                                             AS total_cnt,
                ROUND(SUM(pay_amount), 2)                                            AS total_amount,
                SUM(CASE WHEN order_status IN ('已支付', '已完成') THEN 1 ELSE 0 END) AS paid_cnt,
                ROUND(SUM(pay_amount_valid), 2)                                      AS paid_amount,
                SUM(CASE WHEN order_status = '已完成' THEN 1 ELSE 0 END)             AS done_cnt,
                ROUND(SUM(CASE WHEN order_status = '已完成' THEN pay_amount ELSE 0 END), 2) AS done_amount,
                SUM(CASE WHEN order_status = '待支付' THEN 1 ELSE 0 END)             AS wait_pay_cnt,
                SUM(CASE WHEN order_status = '已取消' THEN 1 ELSE 0 END)             AS cancel_cnt,
                SUM(CASE WHEN order_status = '退款中' THEN 1 ELSE 0 END)             AS refund_cnt
            FROM ydsh_dwd.dwd_order
        ) c
) s;

SELECT * FROM ydsh_ads.ads_order_funnel ORDER BY step_no;

-- ---------- 5. 补充结果校验 ----------
SELECT 'ads_rfm_user'           AS tbl, COUNT(*) AS cnt FROM ydsh_ads.ads_rfm_user
UNION ALL SELECT 'ads_rfm_seg_summary',   COUNT(*) FROM ydsh_ads.ads_rfm_seg_summary
UNION ALL SELECT 'ads_behavior_coverage', COUNT(*) FROM ydsh_ads.ads_behavior_coverage
UNION ALL SELECT 'ads_order_funnel',      COUNT(*) FROM ydsh_ads.ads_order_funnel;

SHOW TABLES IN ydsh_ads;

-- 三处 GMV 交叉校验：RFM 汇总 / DWD 有效金额 / ADS 总览 必须完全一致
SELECT 'RFM汇总_GMV' AS metric, ROUND(SUM(gmv), 2) AS val FROM ydsh_ads.ads_rfm_seg_summary
UNION ALL SELECT 'DWD有效_GMV', ROUND(SUM(pay_amount_valid), 2) FROM ydsh_dwd.dwd_order
UNION ALL SELECT 'ADS总览_GMV', ROUND(gmv, 2) FROM ydsh_ads.ads_gmv_summary;
