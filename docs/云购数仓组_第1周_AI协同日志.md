# 云购数仓组_第 1 周_AI 协同日志

> 课程：企业项目实战实训　｜　项目：云购生活新零售企业数据仓库与经营分析可视化系统
> 周期：2026-10-26 ~ 2026-10-30　｜　记录人：任宴庆

## 一、基本信息

| 项目 | 内容 |
|---|---|
| 团队名称 | 云购数仓组 |
| 团队成员 | 任宴庆（项目经理 / 数据工程师，第 1 周全流程执行） |
| 使用场景 | 大数据环境搭建排障、HiveQL 脚本编写、数据质量分析、项目文档与版本管理 |
| 协同周期 | 2026-10-26 至 2026-10-30（第 1 周） |
| 协同记录数 | 9 条 |
| 项目仓库 | GitHub `github.com/renyanqing0429/ydsh-dw` ；Gitee `gitee.com/ren-yanqing/ydsh-dw` |

## 二、使用的工具与模型

| 类别 | 名称 | 用途 |
|---|---|---|
| AI 助手 | WorkBuddy（AI 编程助手，Agent 模式） | 环境排障、脚本编写与调试、SQL 设计与结果解读、文档撰写 |
| 大模型 | 对话式大语言模型（WorkBuddy 内置） | 方案推理、报错归因、代码生成与修改 |
| 开发环境 | Docker Desktop 29.9.2 / Docker Compose v5.6.1 / WSL 2 | 容器编排 |
| 数据平台 | Apache Hive 4.0.0（Metastore + HiveServer2）、MySQL 8.0 | 数仓存储与查询 |
| 脚本与语言 | HiveQL、Bash、Python | 建表导入、质量扫描、清洗、模拟数据生成 |
| 版本管理 | Git 2.55.0、GitHub、Gitee | 提交规范与远程备份 |
| 文档工具 | VS Code / Word / Excel（WPS 兼容） | 文档与预评估表产出 |

## 三、协同记录表

| 序号 | 日期 | 协同环节 | 提问 / 需求 | AI 输出 | 人工判断与调整 | 产出 |
|---|---|---|---|---|---|---|
| 1 | 10-26 | 环境方案设计 | 「按任务书要求设计一套 Docker + Hive + MySQL 的容器编排」 | 给出 MySQL 8.0 + `apache/hive:4.0.0`（metastore / hiveserver2）三容器 compose，含健康检查与 `depends_on` 启动顺序 | 补上宿主机端口规划与数据卷；确认 Hive 依赖 Metastore 必须先就绪，保留健康检查 | `docker-compose.yml` |
| 2 | 10-26 | 安装排障 | 「Docker Desktop 下载报 ERR_CONNECTION_RESET，装不上」 | 判断为浏览器/代理层问题，给出命令行 curl 直下 + 静默安装参数（`--quiet --accept-license --backend=wsl-2`） | 人工核对安装包大小为 641,758,128 字节与官方一致后才执行安装 | Docker 29.9.2 安装完成 |
| 3 | 10-26 | 镜像拉取 | 「docker pull 官方源超时，怎么在国内环境拉镜像」 | 给出国内镜像源前缀拉取 + `docker tag` 重新打标的方案（不改 Docker 配置、无需重启） | 逐个测速 7 个加速源，选 DaoCloud；拉完重新打标准 tag 保证 compose 引用不变 | mysql:8.0、apache/hive:4.0.0 镜像就位 |
| 4 | 10-26 | Metastore 启动失败 | 「hive-metastore 起不来，日志 ClassNotFoundException: com.mysql.cj.jdbc.Driver」 | 定位为官方镜像未内置 MySQL JDBC 驱动，给出下载 connector 并挂载到 `/opt/hive/lib` 的方案 | 自行确认版本兼容（mysql-connector-j 8.0.x 对 MySQL 8.0），挂载后 `--force-recreate` 重建 | 三容器全部 Up |
| 5 | 10-26 | SQL 脚本编写 | 「写 ODS 建表与导入脚本，要求跳表头、行数可校验」 | 生成 6 张表建表语句（含 `skip.header.line.count=1`）与 `LOAD DATA` + 逐表 `COUNT(*)` 校验脚本 | 人工补上字段注释与预期行数常量；导入后逐表比对，全部一致 | `create_ods.sql`、`load_ods.sql` |
| 6 | 10-27 | Schema 对齐 | 「官方数据字典到了，字段和我推断的不一样，怎么改」 | 逐表比对差异：`ods_store` 9 字段、`ods_order_item` 为折扣率、`ods_user_behavior` 增 `session_id` | 人工确认业务语义（折扣率 vs 小计金额），决定按官方字典重建而非追加字段，避免下游口径歧义 | 建表脚本 v2、官方数据重新导入 |
| 7 | 10-27 | 质量分析 | 「五维度扫描结果怎么解读？哪些要本周处理」 | 归类为完整/唯一/有效/一致/准确五类，指出枚举脏值（中英数字混用）与斜杠日期占比最高 | 人工判断：本周只处理缺失值与重复值（任务书范围），枚举与日期格式列入清洗（二）；据实修正「约 2500 行」为实测 6,506 行 | `quality_check.sql`、`数据质量预评估表` |
| 8 | 10-27 | 去重策略 | 「订单重复既有整行重复又有主键冲突，怎么去重才合理」 | 给出 `ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY order_time DESC)` 保留最新记录的方案，并区分整行重复与内容冲突统计 | 人工确认业务规则：同一订单以最后修改时间为准；并要求去重后复检 `residual_dup = 0` 才算通过 | `dedup.sql`（15600 → 15000） |
| 9 | 10-28 | 脚本调试 | 「dedup.sql 报 CONCAT_WS 类型错误、Git Bash 里 beeline -f 找不到文件」 | 定位为 Hive 不接受 decimal 入参（改 `CAST AS STRING`）与 MSYS 路径改写（加 `MSYS_NO_PATHCONV=1`） | 人工验证修复后整条流水线可一次跑通，并把两个坑写入环境搭建笔记 | 脚本修复提交 `3820e9b` |

## 四、产出成果清单

| 类别 | 文件 | 说明 |
|---|---|---|
| 项目说明 | `README.md` | 团队信息、角色分工、项目目标、阶段计划、技术栈 |
| 环境文档 | `docs/环境搭建笔记.md` | 14 个真实问题的现象、原因、解决方案 |
| 数据质量 | `docs/数据质量预评估表.xlsx` / `.md` | 五维度量化扫描结果（8 个工作表） |
| SQL 脚本 | `sql/ods/create_ods.sql`、`sql/ods/load_ods.sql` | 6 张表建表 + 导入 + 行数校验 |
| 质量脚本 | `sql/quality/quality_check.sql` | 五维度扫描 SQL |
| 清洗脚本 | `sql/clean/missing_values.sql`、`sql/clean/dedup.sql` | 缺失值处理、`ROW_NUMBER()` 去重 |
| 工程化 | `docker-compose.yml`、`.gitignore`、`tools/run_pipeline.sh` | 一键编排与一键流水线 |
| 过程存档 | `docs/执行结果/01~05` | beeline 实测输出 |
| 版本管理 | Git 仓库（13 次 Conventional Commits） | 远程双平台同步 |

## 五、问题与解决

| 问题 | AI 协同方式 | 最终解决 |
|---|---|---|
| Docker Desktop 下载被重置 | AI 判断为浏览器/代理层问题，给命令行下载方案 | curl 下载 + 静默安装成功 |
| WSL 2 未安装，引擎起不来 | AI 给出 `wsl --install --no-distribution` 并说明不需装发行版 | 重启后引擎正常 |
| 由受限进程启动 Docker 导致 `Access is denied` | AI 从日志定位到继承的沙箱限制 | 改由本人从开始菜单手动启动 |
| 官方镜像缺 MySQL JDBC 驱动 | AI 从异常类名直接定位缺失依赖 | 挂载 connector jar 到 `/opt/hive/lib` |
| Git Bash 路径改写破坏 `beeline -f` | AI 指出 MSYS 路径转换机制 | `MSYS_NO_PATHCONV=1` + `docker cp` 入容器 |
| `CONCAT_WS` 传 decimal 报错 | AI 定位为参数类型不兼容 | `CAST(... AS STRING)` |
| 前期按推断建表导致返工 | AI 逐字段比对官方字典并列出差异 | 按官方字典重建 4 张表 |

## 六、反思与总结

**有效的协同方式**

1. **先给现象再给判断**：把完整报错、日志片段、版本信息一并提供给 AI，比只描述「起不来」能少走两三轮。例如 `ClassNotFoundException: com.mysql.cj.jdbc.Driver` 这条日志直接指向了驱动缺失，一次命中。
2. **让 AI 出方案，自己拍板**：去重策略、清洗范围、字段取舍这些涉及业务口径的决定，AI 给的是候选方案，最终按任务书范围和业务合理性选择。比如枚举脏值检测出来了但不在本周范围，主动推迟到清洗（二）而不是顺手改掉。
3. **把结论沉淀成文档**：每个坑解决后立刻写进《环境搭建笔记》，既避免重复踩坑，也让 AI 后续排查能引用自己的历史结论（例如容器 `Exited(255)` 与陈旧 PID 的处理方式被复用了三次）。

**不足与改进**

1. **过早让 AI 生成建表脚本**：在没拿到数据字典时就生成 6 张表结构，导致 4 张表返工。教训是——结构类产出必须先确认数据源，再让 AI 动笔。
2. **对 AI 输出的数字要保持怀疑**：早期把枚举脏值估成「约 2500 行」，后来按实测明细逐项相加才发现是 6,506 行（漏算了行为类型的 3,672 行）。凡是写进报告的数字，都必须能追溯到查询结果。
3. **环境类操作要区分权限边界**：AI 启动 Docker Desktop 会被策略拦截，这类需要 GUI 交互或系统权限的步骤应由人完成，AI 负责准备命令与验证方法，效率更高。

**后续协同计划**

第 2 周的清洗（二）与维度建模阶段，计划继续采用「AI 出脚本骨架 + 人工定口径 + Hive 实测验证」的方式，并保留每次 SQL 修改前后的执行结果对比，作为过程性证据。
