# Lifly 开发计划目录

本目录用于存放 Lifly 不同版本的开发计划文档。

`docs/59-version-control-plan.md` 负责版本号、分支、tag、release gate 规则。

`docs/60-major-version-roadmap.md` 负责 v0.1.0 到 v1.0.0 的大版本路线。

本目录下的文件负责把每个版本拆成可执行的开发范围、Issue 切片、验收标准和提交顺序。

## 文件命名规则

```text
v<版本号>-<版本主题>.md
```

示例：

```text
v0.1.0-foundation-baseline.md
v0.2.0-local-data-mvp.md
v0.3.0-cloud-sync-mvp.md
v0.4.0-ai-write-mvp.md
v0.5.0-assets-import-export-mvp.md
v0.6.0-private-alpha.md
v0.7.0-private-beta.md
v1.0.0-personal-production.md
```

## 当前开发分支

当前 v0.3 云同步开发分支：

```text
feat/v0.3-cloud-sync-mvp
```

该分支的职责是完成 `v0.3.x Cloud Sync MVP`，让 memo / task / expense 在单用户多端之间形成最小同步闭环；不扩大到 v0.4 的 AI 写入、复杂冲突解决或生产级账号体系。

## 当前计划文件

```text
v0.3.0-cloud-sync-mvp.md
```

## 维护规则

1. 每个大版本只维护一个主开发计划文件。
2. 同一版本内新增 Issue、验收标准或已知问题时，优先更新对应版本计划文件。
3. 版本结束前必须同步更新：
   - `docs/59-version-control-plan.md`
   - `docs/60-major-version-roadmap.md`
   - `docs/27-milestones.md`
   - `docs/28-issues-backlog.md`
   - `README.md`
   - `docs/README.md`
4. 开发计划文件只规划版本内要完成的内容，不记录每日流水账。
5. v0.1.0 的核心原则是收口工程基线，不新增 v0.2+ 范围。
