# 云购生活新零售企业——企业级数据仓库与经营分析可视化系统

课程：企业项目实战实训
阶段：第 1 周 · 项目启动 · 环境搭建 · Git 基础 · 数据导入与数据清洗（一）
　　　第 2 周 · 数据清洗进阶 · Hive 四层数仓建模 · 探索性分析

## 团队信息

- **团队名称**：云购数仓组
- **团队口号**：让每一行数据都可追溯
- **仓库地址**：GitHub `https://github.com/renyanqing0429/ydsh-dw` ｜ Gitee `https://gitee.com/ren-yanqing/ydsh-dw`

| 角色 | 成员 | 职责 | 对应交付物 |
|---|---|---|---|
| 项目经理 | 任宴庆 | 进度管理、任务拆解、文档组织、答辩组织 | `README.md`、`docs/` |
| 数据工程师 | 任宴庆 | 环境搭建、ODS 建表与数据导入、数据清洗 | `docker-compose.yml`、`sql/ods/`、`sql/clean/` |
| 数据分析师 | （待补充） | 五维度数据质量评估、SQL 分析 | `sql/quality/quality_check.sql`、`docs/数据质量预评估表.md` |
| 可视化工程师 | （待补充） | 第 2 周起的维度建模与可视化大屏 | 待第 2 周交付 |

> 说明：当前由任宴庆先行完成环境搭建、ODS 导入与清洗（一）等基础环节；数据分析师、可视化工程师两个角色待队友加入后承接，未加入前由任宴庆兼任。角色可一人多岗，请按实际情况更新本表。

### 第 1 周已完成工作（任宴庆）

1. **环境**：Docker Desktop + `apache/hive:4.0.0` + MySQL 8.0 三容器编排，完成 Metastore 初始化、JDBC 驱动挂载、端口冲突处理等全部排障（14 个真实问题记录于 `docs/环境搭建笔记.md`）。
2. **数据**：6 张官方模拟数据 CSV 全部导入 ODS 层，行数与操作手册预期逐表核对一致。
3. **质量**：以 SQL 完成完整性 / 唯一性 / 有效性 / 一致性 / 准确性五维度扫描，输出可复跑脚本与实测结果表。
4. **清洗**：缺失值（年龄均值填充、邮箱打标、上架日期按类目补全）与重复值（`ROW_NUMBER() OVER(PARTITION BY ...)` 保留最新）两类处理均在 Hive 中实测验证。

## 项目目标

基于"云购生活"新零售企业 6 张模拟业务数据表，构建企业级数据仓库（ODS → DWD → …），完成数据导入、质量评估与清洗，并最终搭建经营分析可视化系统。

## 阶段计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| 第 1 周 | 环境搭建、Git 规范、ODS 导入、质量预评估、清洗（缺失值/重复值） | ✅ 已完成 |
| 第 2 周 | 清洗（枚举/异常/格式）、四层架构设计、DWD 维度建模与加载、探索性分析 | ✅ 已完成 |
| 第 2 周（补充） | DWS 汇总层（4 张日汇总表）、ADS 应用层（7 张应用表） | ✅ 已完成 |
| 第 2 周（深化） | 口径下沉 DWD（`pay_amount_valid`）、ADS 扩至 11 张（RFM 2 张 + 行为覆盖 1 张 + 履约漏斗 1 张） | ✅ 已完成 |
| 第 3 周+ | 商品/门店/行为主题汇总、RFM 与履约漏斗、Superset 大屏 | ⏳ 待开始 |
| 后续 | Superset 可视化大屏、项目答辩 | ⏳ 待开始 |

## 第 1 周子任务与交付物

- [x] 子任务 1：团队组建与项目规划 → `README.md`（本文件）
- [x] 子任务 2：开发环境搭建 → `docker-compose.yml` + `docs/环境搭建笔记.md`
- [x] 子任务 3：Git 基础与版本管理规范 → 本仓库提交历史 + `.gitignore`
- [x] 子任务 4：数据导入 ODS 层 → `sql/ods/create_ods.sql`、`sql/ods/load_ods.sql`
- [x] 子任务 5：数据质量预评估 → `sql/quality/quality_check.sql` + `docs/数据质量预评估表.xlsx`
- [x] 子任务 6：缺失值诊断与处理 → `sql/clean/missing_values.sql`
- [x] 子任务 7：重复值检测与去重 → `sql/clean/dedup.sql`
- [x] 附加：AI 协同日志 → `docs/云购数仓组_第1周_AI协同日志.md`；项目过程记录 → `docs/项目工作日志.md`

### 第 1 周实测结论（Hive 真实执行）

| 环节 | 结果 |
|---|---|
| ODS 导入 | ods_user 1000 / ods_product 600 / ods_store 60 / ods_order 15600 / ods_order_item 37549 / ods_user_behavior 60000，与手册预期逐表一致 |
| 质量扫描 | email 缺失 193、枚举脏值 6,506 行、斜杠日期 1902 行、手机号不合格 102、负金额 310、优惠超支付 324、年龄越界 27 |
| 缺失值清洗 | `dwd_user` 年龄异常 78 → 0（均值 41 填充，邮箱缺失 193 条打标保留）；`dwd_product` 上架日期缺失 11 → 0 |
| 重复值去重 | `dwd_order` 15600 → 15000，移除 600 行重复，复检残留 0 |

执行明细见 `docs/执行结果/` 目录。

## 第 2 周子任务与交付物

- [x] 子任务 1：枚举字段标准化 → `sql/clean/standardize_enum.sql`
- [x] 子任务 2：异常值与格式标准化 → `sql/clean/outlier_format.sql`
- [x] 子任务 3：字段拆分合并与编码映射 → `sql/clean/split_merge.sql`（5 张 `dim_*_code` 映射表）
- [x] 子任务 4：数据质量对比报告 → `sql/quality/quality_compare.sql` + `docs/数据质量对比报告.docx`
- [x] 子任务 5：四层数仓架构设计 → `docs/数仓架构设计文档.md`
- [x] 子任务 6：DWD 维度建模与加载 → `sql/dwd/create_dwd.sql`、`sql/dwd/load_dwd.sql`
- [x] 子任务 7：探索性分析 → `sql/analysis/exploratory_analysis.sql` + `docs/探索性分析简报.md`
- [x] 附加：`docs/第2周总结.md`、`docs/第2周_AI协同日志.md`

### 第 2 周实测结论（Hive 真实执行）

| 环节 | 结果 |
|---|---|
| 枚举标准化 | gender 8→3、member_level 12→4、order_status 12→5、pay_type 7→4、channel 6→4、behavior_type 10→4，未命中映射 0 |
| 异常与格式 | 金额封顶 304 行（阈值 P95=4,745.32）、年龄均值 41 填充 78 行、日期/手机号/行为时间残留均 0 |
| 质量对比 | 五类脏数据 72,877 → 193（全部为邮箱空值，按策略保留打标），整体修复率 **99.74%**；剔除邮箱口径 100% |
| DWD 建模 | dim_user 1,000 / dim_product 600 / dim_store 60 / dim_date 366；dwd_order 15,000（366 分区）/ dwd_order_item 37,549 / dwd_user_behavior 60,000（92 分区）+ 分桶表 8 桶 |
| 探索性分析 | GMV 3,847.05 万、客单价 2,564.70、ARPU 38,470.43、订单有效率 66.44%；17% 高价值用户贡献 25% GMV |

## 目录结构

```
ydsh-dw/
├── README.md                  # 项目说明与个人分工
├── .gitignore                 # 忽略数据文件、日志、密钥
├── docker-compose.yml         # Hive + MySQL 容器编排
├── docs/
│   ├── 第1周总结.md           # 独立总结报告（任务/数据/质量/清洗/计划）
│   ├── 第2周总结.md           # 第 2 周总结（清洗/建模/分析）
│   ├── 数仓架构设计文档.md/.docx  # 四层架构 + 星型模型 + 分区分桶 + 命名规范
│   ├── 数据质量对比报告.md/.docx  # 五类脏数据修复率（第 2 周，提交清单第 2 项）
│   ├── 探索性分析简报.md/.docx    # KPI 与多维分布分析（第 2 周，提交清单第 5 项）
│   ├── html/                  # 上述三份文档的排版 HTML（docx 的转换源）
│   ├── 环境搭建笔记.md        # 19 个真实问题与解决方案
│   ├── 数据质量预评估表.xlsx   # 五维度扫描结果（8 个工作表，主交付物）
│   ├── 数据质量预评估表.md     # 同内容的 Markdown 版（便于 Git diff）
│   ├── Hive查询速查手册.md     # 答辩演示查询与客户端连接
│   ├── 项目工作日志.md         # 每日过程记录（含第 2 周）
│   ├── 云购数仓组_第1周_AI协同日志.md  # AI 协同记录（9 条）
│   ├── 第2周_AI协同日志.md     # AI 协同记录（11 条，六部分模板）
│   └── 执行结果/              # beeline 实测输出存档（01~15，含 DWS/ADS/RFM 漏斗）
├── sql/
│   ├── ods/
│   │   ├── create_ods.sql     # ODS 层建表脚本
│   │   └── load_ods.sql      # 数据加载与行数校验
│   ├── quality/
│   │   ├── quality_check.sql  # 五维度质量扫描（第 1 周）
│   │   └── quality_compare.sql # 清洗前后质量对比与修复率（第 2 周）
│   ├── clean/
│   │   ├── missing_values.sql # 缺失值处理
│   │   ├── dedup.sql          # 重复值去重
│   │   ├── standardize_enum.sql # 枚举字段标准化（第 2 周）
│   │   ├── outlier_format.sql   # 异常值与格式标准化（第 2 周）
│   │   └── split_merge.sql      # 字段拆分合并 + 编码映射维度表（第 2 周）
│   ├── dwd/
│   │   ├── create_dwd.sql     # DWD 维度表 / 事实表建模（ORC + 分区）
│   │   └── load_dwd.sql       # DWD 层数据加载（含分桶表）
│   ├── dws/
│   │   └── create_dws_load.sql  # DWS 汇总层：订单/用户/品类/渠道 4 张日汇总表
│   ├── ads/
│   │   ├── create_ads_load.sql  # ADS 应用层：总览/趋势/品类/渠道/省份/分层/会员 7 张表
│   │   └── rfm_funnel.sql       # ADS 深化：RFM 明细/客群 + 行为覆盖 + 订单履约漏斗 4 张表
│   └── analysis/
│       └── exploratory_analysis.sql  # 探索性分析（第 2 周）
├── tools/
│   ├── gen_mock_data.py       # 模拟数据生成（官方数据下发前的过渡方案）
│   ├── md2html.py             # Markdown → 排版 HTML（封面 + A4 + 框图表格化）
│   ├── postprocess_docx.py    # docx 印刷细节后处理（A4/封面分页/表头重复）
│   └── run_pipeline.sh        # 一键跑完整流水线
├── jars/                      # MySQL JDBC 驱动（挂载进 Hive 容器）
└── data/                      # 官方模拟数据 CSV（不入库，见 .gitignore）
```

## 快速开始

```bash
docker compose up -d                       # 启动 MySQL + Hive Metastore + HiveServer2
bash tools/run_pipeline.sh all             # 第 1 周：建库建表 → 导入 → 质量扫描 → 清洗
bash tools/run_pipeline.sh week2           # 第 2 周：枚举 → 异常/格式 → 合并映射 → DWD 建模加载 → 质量对比 → 分析
bash tools/run_pipeline.sh analysis        # 单独重跑探索性分析
```

> Git Bash 下执行需先 `export MSYS_NO_PATHCONV=1`，否则容器内路径会被改写，详见环境搭建笔记。
> 所有写入均使用 `INSERT OVERWRITE` 幂等写入，脚本可重复执行（Hive 4 的 `CREATE TABLE` 默认为外部表，
> `DROP TABLE` 只删元数据，重复跑会数据翻倍，详见环境笔记问题 19）。

## 环境说明

- Hive 4.0.0（Metastore 元数据存于 MySQL 8.0），通过 Docker Compose 编排
- 数据库名：`ydsh_ods`（ODS 贴源层）、`ydsh_dwd`（DWD 明细层 + STG 清洗中间层）
- 建表均带 `tblproperties('skip.header.line.count'='1')` 跳过 CSV 表头
- DWD 层全部 `STORED AS ORC`，事实表按日期分区，行为表另建 8 桶分桶版本

## 参考资源

- Git 官方文档：https://git-scm.com/doc
- Apache Hive：https://hive.apache.org/
- Docker：https://docs.docker.com/

## 提交规范（Conventional Commits）

- `feat:` 新功能 / 新脚本
- `fix:` 修复问题
- `docs:` 文档变更
- `chore:` 杂项维护
