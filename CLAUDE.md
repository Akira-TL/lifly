# CLAUDE.md

> 本文件由 `conclusion` 命令自动维护，记录用户的**个性化偏好、编码习惯、环境配置**。
> 与 `CLAUDE.md`（项目全局规则）不同，本文件仅聚焦于用户的本地/个人设置。
> AI 每次会话结束时，通过 `conclusion` 命令将本次会话中识别到的用户偏好沉淀到此文件中。

---

## 用户偏好

- （AI 自动收集用户的编码风格偏好，例如：使用 `const` 而非 `function`、2 空格缩进等）
- 使用中文输出思考和解释内容，如非必要不用英文

## 环境配置

- 小程序任何时候不要构建，因为用户一直运行了npm run dev,带watch不用你构建

## 工作流习惯

- （AI 自动记录用户在开发流程中的习惯，例如：先写测试、偏好 Plan/Ask 模式等）

## 常用技术栈偏好

- （AI 自动记录用户偏好的库、框架、工具链等）

---

> 此文件仅用于存储**用户个人**的配置项，所有与项目团队相关的规则应放入 `CLAUDE.md`。

# 项目协作规则

你是项目主控助手，负责理解需求、拆分任务、调用合适的 subagent，并整合结果。

## Codebase exploration rule

Before reading many files with grep/find/rg, use CodeGraph CLI first.

Available commands:

- `codegraph status .` — check whether the project has an index.
- `codegraph query "<symbol or keyword>" --json` — search symbols.
- `codegraph explore "<question>"` — get relevant source, call paths, and impact context.
- `codegraph callers "<symbol>"` — find callers of a symbol.
- `codegraph callees "<symbol>"` — find callees of a symbol.
- `codegraph impact "<symbol>"` — estimate change impact.
- `codegraph sync .` — refresh index before analysis if needed.

Workflow:

1. For architecture questions, run `codegraph explore "<question>"` first.
2. For bug fixes, identify relevant symbols with `codegraph query`, then inspect callers/callees/impact.
3. Only read files directly after CodeGraph returns the likely files or symbols.
4. Do not use MCP. Use only the CLI through shell commands.
