# 云购生活新零售企业——企业级数据仓库与经营分析可视化系统

课程：企业项目实战实训
阶段：第 1 周 · 项目启动 · 环境搭建 · Git 基础 · 数据导入与数据清洗（一）

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
| 第 2 周+ | 数据清洗（二）、维度建模、指标计算 | ⏳ 待开始 |
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

## 目录结构

```
ydsh-dw/
├── README.md                  # 项目说明与个人分工
├── .gitignore                 # 忽略数据文件、日志、密钥
├── docker-compose.yml         # Hive + MySQL 容器编排
├── docs/
│   ├── 环境搭建笔记.md        # 14 个真实问题与解决方案
│   ├── 数据质量预评估表.xlsx   # 五维度扫描结果（8 个工作表，主交付物）
│   ├── 数据质量预评估表.md     # 同内容的 Markdown 版（便于 Git diff）
│   ├── Hive查询速查手册.md     # 答辩演示查询与客户端连接
│   ├── 项目工作日志.md         # 10-26~10-30 每日过程记录
│   ├── 云购数仓组_第1周_AI协同日志.md  # AI 协同记录（9 条）
│   └── 执行结果/              # beeline 实测输出存档
├── sql/
│   ├── ods/
│   │   ├── create_ods.sql     # ODS 层建表脚本
│   │   └── load_ods.sql      # 数据加载与行数校验
│   ├── quality/
│   │   └── quality_check.sql  # 五维度质量扫描
│   └── clean/
│       ├── missing_values.sql # 缺失值处理
│       └── dedup.sql          # 重复值去重
├── tools/
│   ├── gen_mock_data.py       # 模拟数据生成（官方数据下发前的过渡方案）
│   └── run_pipeline.sh        # 一键跑完整流水线
├── jars/                      # MySQL JDBC 驱动（挂载进 Hive 容器）
└── data/                      # 官方模拟数据 CSV（不入库，见 .gitignore）
```

## 快速开始

```bash
docker compose up -d                       # 启动 MySQL + Hive Metastore + HiveServer2
docker cp sql/ods/create_ods.sql hive-server:/tmp/
docker exec hive-server beeline -u jdbc:hive2://localhost:10000 -f /tmp/create_ods.sql
# 其余脚本同理：load_ods.sql → quality_check.sql → missing_values.sql → dedup.sql
```

> Git Bash 下执行需先 `export MSYS_NO_PATHCONV=1`，否则容器内路径会被改写，详见环境搭建笔记。

## 环境说明

- Hive 4.0.0（Metastore 元数据存于 MySQL 8.0），通过 Docker Compose 编排
- 数据库名：`ydsh_ods`（ODS 贴源层）
- 建表均带 `tblproperties('skip.header.line.count'='1')` 跳过 CSV 表头

## 参考资源

- Git 官方文档：https://git-scm.com/doc
- Apache Hive：https://hive.apache.org/
- Docker：https://docs.docker.com/

## 提交规范（Conventional Commits）

- `feat:` 新功能 / 新脚本
- `fix:` 修复问题
- `docs:` 文档变更
- `chore:` 杂项维护
