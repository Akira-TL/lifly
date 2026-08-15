# Lifly Nginx Gateway

`lifly.babelbeast.com` 的业务 Nginx 规则保存在 Lifly 项目目录，不复制到 `/etc/nginx/sites-available`。

## 公网路由

| URL | Upstream | 用途 |
|---|---:|---|
| `https://lifly.babelbeast.com/` | `127.0.0.1:8211` | Flutter Web |
| `https://lifly.babelbeast.com/api/*` | `127.0.0.1:8210` | FastAPI |
| `https://lifly.babelbeast.com/mcp` | `127.0.0.1:8210` | Cloud MCP Streamable HTTP |

PowerSync `8204`、PostgreSQL、Redis、MinIO 不通过该域名直接暴露公网。

## 配置布局

```text
infra/gateway/sites/
  lifly-http.conf          # ACME HTTP-01 + HTTP -> HTTPS
  lifly-https.conf         # Web/API/MCP reverse proxy

infra/gateway/sites-enabled/
  lifly-http.conf          # 版本控制的 HTTP 启用入口
  lifly-https.conf         # deploy-nginx.sh 在证书存在后创建的运行时 symlink
```

系统 `/etc/nginx/nginx.conf` 只增加：

```nginx
include /home/Akira/Projects/lifly/infra/gateway/sites-enabled/*.conf;
```

因此日常修改 Lifly 站点规则只修改本项目文件，然后执行 `sudo nginx -t && sudo systemctl reload nginx`。

## 首次部署 / 证书自动申请

DNS 的 `lifly.babelbeast.com` 必须先指向本机公网入口，然后执行：

```bash
bash scripts/deploy-nginx.sh --check
bash scripts/deploy-nginx.sh apply
```

脚本按两阶段工作：

1. 先只启用 HTTP ACME challenge；
2. 使用 Certbot `webroot` 自动申请证书；
3. 证书成功后启用 HTTPS 站点；
4. 启用 `certbot.timer`；
5. 安装 renewal deploy hook，在证书续期后执行 `nginx -t` 和 reload。

当前机器已有 Certbot account 时无需提供邮箱；全新服务器首次注册 Certbot account 时：

```bash
CERTBOT_EMAIL=you@example.com bash scripts/deploy-nginx.sh apply
```

## Web 的公网 API Base URL

通过域名访问 Flutter Web、且需要 API 模式时，Web 构建/启动必须使用公网同源 API：

```bash
LIFLY_DATA_MODE=api \
LIFLY_API_BASE_URL=https://lifly.babelbeast.com/api/v1 \
bash scripts/dev-web-start.sh
```

不要把浏览器端 API Base URL 配成 `127.0.0.1:8210`，因为那会指向访问者自己的设备。

## 检查

```bash
bash scripts/check-nginx-gateway.sh
curl -I http://lifly.babelbeast.com/
curl https://lifly.babelbeast.com/api/v1/health
```
