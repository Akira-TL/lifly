# Lifly 主要依赖与许可边界

Lifly 第一方代码使用 PolyForm Noncommercial 1.0.0。第三方组件不因 Lifly 的第一方许可证而改变许可条件，仍以各自上游许可证为准。

提交材料只列和架构有关的主要依赖，不用把 lockfile 里的每个间接包都塞进 PPT。

| 组件 | 用途 |
|---|---|
| Flutter / Dart | Web、Android、Desktop 客户端 |
| FastAPI / SQLAlchemy | API 与服务端业务入口 |
| MCP SDK | Cloud / Local MCP |
| PowerSync + SQLCipher | 跨端同步与本地加密数据库 |
| PostgreSQL | 服务端持久化 |
| Redis | 服务协作与运行时基础设施 |
| MinIO | 附件对象存储 |
| Ollama | Personal Compute Node / 本地模型运行时 |
| Rust OPAQUE helper | 账号认证的 OPAQUE/aPAKE 客户端与服务端辅助运行时 |
| cryptography / Dart cryptography | E2EE 与设备间加密实现基础 |

Flutter release bundle 会生成依赖 notices；Node、Python、Rust 依赖的完整版本以 `pnpm-lock.yaml`、`services/api/uv.lock`、Cargo lockfile 与各 package manifest 为准。

对外材料不要写成“所有依赖都采用 Lifly License”。只有 Lifly 自己拥有版权的第一方代码适用仓库根 `LICENSE`。
