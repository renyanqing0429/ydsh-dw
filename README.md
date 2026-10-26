# 云购生活新零售企业——企业级数据仓库与经营分析可视化系统

课程：企业项目实战实训
阶段：第 1 周 · 项目启动 · 环境搭建 · Git 基础 · 数据导入与数据清洗（一）

## 团队信息

- **团队名称**：（待定）
- **团队口号**：（待定）

| 角色 | 成员 | 职责 |
|---|---|---|
| 项目经理 | （待填） | 进度管理、任务拆解、答辩组织 |
| 数据工程师 | （待填） | 环境搭建、数据导入、数据清洗 |
| 数据分析师 | （待填） | 数据质量评估、SQL 分析 |
| 可视化工程师 | （待填） | 后续可视化大屏搭建 |

> 角色可一人多岗，请按实际情况填写。

## 项目目标

基于"云购生活"新零售企业 6 张模拟业务数据表，构建企业级数据仓库（ODS → DWD → …），完成数据导入、质量评估与清洗，并最终搭建经营分析可视化系统。

## 阶段计划

| 阶段 | 内容 | 状态 |
|---|---|---|
| 第 1 周 | 环境搭建、Git 规范、ODS 导入、质量预评估、清洗（缺失值/重复值） | 🚧 进行中 |
| 第 2 周+ | 数据清洗（二）、维度建模、指标计算 | ⏳ 待开始 |
| 后续 | Superset 可视化大屏、项目答辩 | ⏳ 待开始 |

## 第 1 周子任务与交付物

- [ ] 子任务 1：团队组建与项目规划 → `README.md`（本文件）
- [ ] 子任务 2：开发环境搭建 → `docker-compose.yml` + `docs/环境搭建笔记.md`
- [ ] 子任务 3：Git 基础与版本管理规范 → 本仓库提交历史 + `.gitignore`
- [ ] 子任务 4：数据导入 ODS 层 → `sql/ods/create_ods.sql`、`sql/ods/load_data.sql`
- [ ] 子任务 5：数据质量预评估 → `sql/quality/quality_check.sql` + `docs/数据质量预评估表.md`
- [ ] 子任务 6：缺失值诊断与处理 → `sql/clean/missing_values.sql`
- [ ] 子任务 7：重复值检测与去重 → `sql/clean/dedup.sql`

## 目录结构

```
ydsh-dw/
├── README.md                  # 团队信息与项目说明
├── .gitignore                 # 忽略数据文件、日志、密钥
├── docker-compose.yml         # Hive + MySQL 容器编排
├── docs/
│   ├── 环境搭建笔记.md        # 环境问题与解决方案记录
│   └── 数据质量预评估表.md    # 五维度扫描结果
├── sql/
│   ├── ods/
│   │   ├── create_ods.sql     # ODS 层建表脚本
│   │   └── load_data.sql      # 数据加载与行数校验
│   ├── quality/
│   │   └── quality_check.sql  # 五维度质量扫描
│   └── clean/
│       ├── missing_values.sql # 缺失值处理
│       └── dedup.sql          # 重复值去重
└── data/                      # 模拟数据 CSV（不入库，见 .gitignore）
```

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
