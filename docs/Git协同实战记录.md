# Git 协同实战记录（第 3 周 子任务 6）

**团队**：云购数仓组　**记录人**：任宴庆

> 任务书要求：实践 Fork 工作流、完成一次 Code Review、使用 Issue/tag、解决一次真实的合并冲突并记录过程。
> 当前阶段为单人开发（数据分析师/可视化工程师角色待队友加入），因此本记录采用「本地双分支 + 真实冲突 + 人工解决」完整演示协同机制；Fork/PR/Code Review 的团队实操指南见文末，队友加入后按指南执行即可无缝衔接。

## 一、本周实际执行的 Git 操作流水

| 步骤 | 操作 | 结果 |
|---|---|---|
| 1 | 主干 `main` 上按子任务拆分 5 个逻辑提交（ads/forecast/llm/nl2sql/insight） | 提交粒度可追溯，单提交单主题 |
| 2 | 从 `main` 拉出 `feature/sql-review` 分支（模拟开发者在 A 处提交 PR 评审意见） | 见下方冲突现场 |
| 3 | 同一基点再拉 `feature/sql-review-v2` 分支（模拟另一开发者同时修改同一小节） | 并行开发 |
| 4 | `feature/sql-review` 先合入 `main` | 无冲突 |
| 5 | `feature/sql-review-v2` 合入 `main` | **产生真实合并冲突**（同一文件同一行被两个分支改写） |
| 6 | 人工比对两个版本 → 合并保留双方信息 → `git add` → 完成合并提交 | 冲突解决 |
| 7 | 打版本标签 `v0.3.0-week3`（任务书：用 tag 标记版本发布） | 里程碑可寻址 |

## 二、冲突现场（真实记录）

**分支B补充（feature/sql-review-v2）**：建议冲突解决前先 git stash 保存现场，逐行比对语义后保留双方有效信息。

冲突文件：`docs/Git协同实战记录.md` 的「Code Review 记录」小节。
两个分支对同一行做了不同的增改，合并时 Git 输出冲突标记：

```
<<<<<<< HEAD
（feature/sql-review 已合入的评审意见）
=======
（feature/sql-review-v2 的评审意见）
>>>>>>> feature/sql-review-v2
```

**解决原则**：逐行比对语义，保留双方有效信息并统一表述；解决后先本地运行校验（内容完整、无残留 `<<<<<<<` 标记）再提交合并。

## 三、Code Review 记录

### 评审 1（feature/sql-review 分支模拟，评审人视角 A）

- **对象**：`src/nl2sql/executor.py` SQL 安全校验
- **意见**：黑名单正则需先剥除字符串字面量再匹配，否则 SQL 内含 `'drop'` 等词会误杀——已实现（`re.sub(r"'[^']*'", "", sql)`），确认逻辑正确；
- **建议**：`FORBIDDEN` 关键字中 `set` 命中面偏宽（会误伤 `offset` 之外的词边界场景），后续可改用显式语句开头匹配。**采纳，列入 Issue 跟进。**

### 评审 2（feature/sql-review-v2 分支模拟，评审人视角 B）

- **对象**：`sql/ads/kpi_extension.sql` 复购率口径
- **意见**：月度复购率必须使用「截至当月末累计」口径，分子分母若一个累计一个当月会虚高（实测曾出现 100% 的口径错位，已修正为累计/累计）；
- **确认**：口径已在建表注释中显式声明，复算 2024-12 月末累计 1000/1000，与全周期一致。**通过。**

## 四、Issue 追踪模拟（单人阶段用本文档代替 Issue 面板）

| 编号 | 标题 | 标签 | 状态 |
|---|---|---|---|
| #1 | FORBIDDEN 关键字 `set` 误杀面偏宽，改显式语句开头匹配 | `bug` `nl2sql` | open |
| #2 | NL2SQL 接入真实 API Key 后跑通端到端生成 | `enhancement` `nl2sql` | open（等 Key） |
| #3 | 预测模型引入节假日/大促日历特征 | `enhancement` `forecast` | open |
| #4 | dashboard 增加「预测带」展示（预测值 ± 1 RMSE） | `enhancement` `dashboard` | open |
| #5 | 复购率在真实数据上的分布验证（模拟数据饱和 100%） | `tech-debt` | open |

## 五、Fork 工作流 / PR / Code Review 团队实操指南（队友加入后执行）

```bash
# 1. Fork：在 GitHub/Gitee 仓库页面点 Fork，得到自己的远程仓库
# 2. 克隆自己的 Fork
git clone https://github.com/<你的用户名>/ydsh-dw.git
cd ydsh-dw
git remote add upstream https://github.com/renyanqing0429/ydsh-dw.git

# 3. 同步主干并开 feature 分支（分支名规范 feature/<主题>）
git fetch upstream && git checkout main && git merge upstream/main
git checkout -b feature/<你的主题>

# 4. 开发 + 提交（提交信息规范 feat/fix/docs(scope): 描述）
git add <文件> && git commit -m "feat(nl2sql): 实现xxx"

# 5. 推送到自己的 Fork，在 GitHub/Gitee 页面发起 Pull Request（base: main ← compare: feature/xxx）
git push origin feature/<你的主题>

# 6. Code Review：至少 1 名队友逐条评审（正确性/口径/规范），评审意见在 PR 内回复；
#    修改后重新 push（同分支追加提交即可），评审通过后由维护者 Squash merge。

# 7. 时机：合 PR 前先 git fetch upstream && git rebase upstream/main，
#    遇到冲突按「本文档第二节」的流程人工解决，解决记录写入本文档。
```

**Issue 规范**：标题 = 一句话说清问题；标签 = bug / enhancement / tech-debt / docs；正文含复现步骤（bug）或验收标准（enhancement）。

## 六、合规自查清单

- [x] `.gitignore` 覆盖 `.env` / `*.csv` / 日志（密钥零泄露）
- [x] 提交信息符合 `type(scope): 描述` 规范
- [x] 解决过一次真实合并冲突并留痕（第二节）
- [x] 版本标签：`v0.3.0-week3`
- [x] Issue 清单维护（第四节）
