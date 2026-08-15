# Lifly 端口命名空间

Lifly 的宿主机端口统一限定在 `8200–8299`。本规范只约束 Host Port；PostgreSQL、Redis、MinIO、PowerSync 等容器内部端口保持各自标准值。

## Common

Common 服务不随 Dev / Blue / Green 切换，生命周期属于整个 Lifly 项目：

| Host Port | 服务 |
| --- | --- |
| 8200 | PostgreSQL |
| 8201 | Redis |
| 8202 | MinIO API |
| 8203 | MinIO Console |
| 8204 | PowerSync |
| 8205–8209 | Reserved |

当前 Lifly 只有一套共享 PostgreSQL，PowerSync 设计上直接连接这套共享数据库，因此 PowerSync 也归入 Common。不要同时部署 Shared PowerSync 与 slot PowerSync。

当前 PowerSync 自托管配置仍是旧版结构，尚未完成与新版 PowerSync Service 的运行契约迁移，因此 `scripts/dev-start.sh` 默认不启动 PowerSync；`8204` 的 Host Port 归属已经固定。启用前应先完成独立的 PowerSync 配置、源库逻辑复制、bucket storage 与 client auth 校验。

## Dev / Blue / Green

统一公式：

```text
port = 8200 + slot_offset + service_id

dev   offset = 10
blue  offset = 40
green offset = 70
```

当前 service_id：

| service_id | 服务 | Dev | Blue | Green |
| --- | --- | --- | --- | --- |
| 00 | API / Backend | 8210 | 8240 | 8270 |
| 01 | Web | 8211 | 8241 | 8271 |
| 02 | MCP 网络服务预留 | 8212 | 8242 | 8272 |
| 03 | PowerSync slot 预留 | 8213 | 8243 | 8273 |

`service_id 03` 目前只用于保持编号语义稳定，不实际监听；PowerSync 的实际 Host Port 是 Common `8204`。

## MCP 边界

当前仓库中的 `services/local-mcp` 使用 stdio，不监听 Host Port。Cloud MCP 则由 FastAPI 进程内挂载，因此跟随 API 端口，不是独立的 `service_id 02` 网络服务。

`8212 / 8242 / 8272` 仅保留给未来真正独立部署的 MCP 网络服务。在该服务出现前，不应为了“填满端口表”启动占位监听器。

## 运行时来源

Shell 启动脚本统一读取：

```text
scripts/lib/lifly-ports.sh
```

`LIFLY_DEPLOY_SLOT` 仅允许：

```text
dev
blue
green
```

开发脚本固定使用 Dev；Blue / Green 后续部署脚本必须复用同一 service_id 定义，不能重新分配尾号。

## 生产槽语义

Blue 和 Green 是完全对称的生产接替槽，不分别等同于 production / staging。正式 nginx 只应指向当前 active slot；下一次发布使用另一槽验证后再切换。

当前仓库尚无正式 nginx、systemd 或 Blue/Green deployment 配置，因此本次只建立端口语义和可复用计算入口，不虚构尚不存在的生产部署层。
