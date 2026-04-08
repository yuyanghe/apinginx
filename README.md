# apinginx

在 Docker 中运行 **Nginx**，站点域名为 **`api.zxai.app`**，支持 **Let’s Encrypt** 正式 HTTPS。仓库内维护主配置、静态页与签发脚本，构建镜像推送到仓库后，可在服务器上 `pull` 并配合 `docker compose` 使用。

## 前置条件

- 已安装 **Docker** 与 **Docker Compose**（`docker compose` 命令可用）。
- **生产部署**：`api.zxai.app` 的 **DNS A 记录**指向服务器；安全组/防火墙放行 **80**（签发与跳转）、**443**（HTTPS）。

## 生产环境：首次部署与证书

1. 将本仓库放到服务器某目录，进入该目录。

2. 启动 Nginx（此时尚无正式证书，容器会先以 **仅 HTTP** 方式对外，用于 ACME 校验）：

   ```bash
   docker compose up -d nginx
   ```

   因为 Compose 里对 `nginx` 写了 `build: .`，**第一次（或镜像不存在时）执行上述命令会自动在本机构建镜像**，不必先单独跑 `docker build`。若想强制按当前 Dockerfile 重新构建再起容器，可以用：`docker compose up -d --build nginx`。

3. 申请 Let’s Encrypt 证书并**重启** Nginx（重启后入口脚本会生成 **80 → HTTPS 跳转** 与 **443 TLS** 配置）：

   ```bash
   export CERTBOT_EMAIL='你的邮箱'
   ./scripts/issue-cert.sh
   ```

4. 验证：浏览器访问 `https://api.zxai.app`，流量由 Nginx 反代到 **`new-api`**（即 [New-API](https://hub.docker.com/r/calciumion/new-api) 网关）；健康检查：`curl -sS https://api.zxai.app/health`（应返回 `ok`）。

`docker-compose.yml` 里已包含 **`new-api`** 服务，数据目录为仓库下 **`new-api-data/`**（已在 `.gitignore` 中）。默认不映射宿主 `3000` 端口，只对内网供 Nginx 访问；若要直连网关管理界面，可取消 compose 里 `new-api` 的 `ports` 注释。正式环境请按 [官方文档](https://github.com/QuantumNous/new-api-docs) 增加 **MySQL / Redis** 等依赖并配置 `SQL_DSN`、`REDIS_CONN_STRING`。

证书与私钥保存在 Compose 默认的命名卷 **`letsencrypt`**（挂载到容器内 `/etc/letsencrypt`），与 **certbot** 容器共用；**不要删卷**，否则需重新签发。

### 修改 Nginx / 反代后「不生效」

- **`docker-entrypoint.d/40-apzinginx-tls.sh` 会打进镜像**：改完脚本后必须 **重新构建** 再起容器，例如  
  `docker compose up -d --build nginx`  
  仅 `docker compose restart nginx` **不会**换新脚本。
- **不要用 `127.0.0.1` 当反代地址**：在容器里那是 Nginx 自己，连不到宿主机或其它容器上的 API。请用 **Compose 服务名**（如 `http://new-api:3000`），或后端在宿主机时用 **`http://host.docker.internal:端口`**（本 `docker-compose.yml` 已为 Linux 加了 `extra_hosts: host-gateway`）。
- 反代上游通过环境变量 **`APIS_UPSTREAM`** 注入（默认 `http://new-api:3000`）。**只改这个变量**时不必 `--build`，执行 `docker compose up -d nginx` 让容器用上新的环境即可。若改的是 **`40-apzinginx-tls.sh` 本身**，则必须带 **`--build`**。

### 证书续期

Let’s Encrypt 证书有效期约 90 天，建议在服务器加 **cron**，例如每天凌晨跑一次：

```bash
0 3 * * * cd /path/to/apinginx && ./scripts/renew-certs.sh
```

`renew-certs.sh` 在续期成功后会对 Nginx 执行 **`reload`**，无需重启容器。

### 仅用 Staging 测试（不占正式配额）

证书的 CA 为测试用，浏览器会提示不可信，仅用于调试流程：

```bash
export LE_STAGING=1
export CERTBOT_EMAIL='你的邮箱'
./scripts/issue-cert.sh
```

---

## 本地开发

### 使用自签名证书（模拟 HTTPS）

证书目录结构需与生产一致（`live/api.zxai.app/`），可用脚本生成：

```bash
./scripts/init-dev-certs.sh
```

`dev-certs/` 已写入 `.gitignore`。随后指定证书挂载并启动：

```bash
CERTS_MOUNT=./dev-certs docker compose up -d --build
```

浏览器访问 `https://api.zxai.app`（若设置了 `HTTPS_PORT`，则用对应端口）时，建议在 **`/etc/hosts`** 中将 `api.zxai.app` 指到本机；自签证书会触发浏览器警告，属正常现象。

若尚未有正式证书、又不指定 `CERTS_MOUNT`，Compose 默认使用空命名卷挂载到 `/etc/letsencrypt`，此时镜像入口逻辑会走 **仅 HTTP** 模式。

### 本机改端口映射

避免与宿主机已有 80/443 冲突时：

```bash
HTTP_PORT=8080 HTTPS_PORT=8443 docker compose up -d
```

---

## 单独构建镜像并推到仓库

在能执行 `docker build` 的环境：

```bash
docker build -t <registry>/apinginx:<tag> .
docker push <registry>/apinginx:<tag>
```

在服务器上准备 **同版本** 的 `docker-compose.yml`、`docker-entrypoint.d/`、`scripts/`（或改为仅挂载数据卷与 compose），然后：

```bash
docker pull <registry>/apinginx:<tag>
# 在 compose 中将 build 改为 image: <registry>/apinginx:<tag>，或保持 build 与上下文一致
docker compose up -d
```

注意：HTTPS 行为依赖镜像内的 **`/docker-entrypoint.d/40-apzinginx-tls.sh`** 与 **`nginx/nginx.conf`**；若只替换镜像而不同步 entrypoint，行为可能不一致。

---

## 目录说明

| 路径 | 说明 |
|------|------|
| `Dockerfile` | 基于 `nginx:1.27-alpine`，安装入口脚本与静态资源 |
| `docker-entrypoint.d/40-apzinginx-tls.sh` | 根据是否存在证书，生成 `conf.d` 下的 HTTP / HTTPS 片段 |
| `nginx/nginx.conf` | Nginx 主配置（含 `conf.d` 的 `include`） |
| `html/` | 默认站点根目录（`index.html` 等） |
| `docker-compose.yml` | `new-api`（网关）+ `nginx` + `certbot`；网关数据目录 `new-api-data/` |
| `scripts/issue-cert.sh` | 首次 `certbot certonly`（webroot）并 **restart** nginx |
| `scripts/renew-certs.sh` | `certbot renew` 并 **reload** nginx |
| `scripts/init-dev-certs.sh` | 本地自签，写入 `dev-certs/live/api.zxai.app/` |

站点虚拟主机与 TLS 路径写死在入口脚本中（`api.zxai.app` 与 `/etc/letsencrypt/live/api.zxai.app/`）。若要改域名或增加反代，需编辑 **`docker-entrypoint.d/40-apzinginx-tls.sh`** 中由 heredoc 写出的配置，并重新构建镜像。

---

## 环境变量一览

| 变量 | 说明 |
|------|------|
| `CERTS_MOUNT` | 证书挂载源。默认 `letsencrypt`（命名卷）；本地自签可设为 `./dev-certs` |
| `APIS_UPSTREAM` | HTTPS/HTTP 下 `/` 反代的完整 upstream（默认 `http://new-api:3000`，与 compose 内服务名一致）。只改此项时**不必** `--build`，执行 `docker compose up -d nginx` 带上新环境即可 |
| `NEW_API_TAG` | `new-api` 镜像标签，默认 `latest` |
| `NEW_API_PORT` | 仅在取消 `new-api` 的 `ports` 注释时使用，默认 `3000` |
| `TZ` | 容器时区，`new-api` 默认 `Asia/Shanghai` |
| `HTTP_PORT` / `HTTPS_PORT` | 宿主机映射端口，默认 `80` / `443` |
| `CERTBOT_EMAIL` | 运行 `issue-cert.sh` 时必填，Let’s Encrypt 账户邮箱 |
| `LE_STAGING` | 设为 `1` 或 `true` 时使用 Let’s Encrypt 测试环境 |

---

## 常见问题

**签发失败 / connection / timeout**  
确认域名已解析到本机、`docker compose` 中 Nginx 已监听宿主机 80，且外网能访问 `http://api.zxai.app/.well-known/acme-challenge/`（由 certbot 写入 webroot 后校验）。

**签发成功但浏览器仍只有 HTTP**  
首次签发后必须使用 **`docker compose restart nginx`**（`issue-cert.sh` 已包含），不能仅靠 `reload`，否则不会重新生成 443 配置。

**续期后证书已换但连接异常**  
可执行 `./scripts/renew-certs.sh` 或 `docker compose exec nginx nginx -s reload`，使 Nginx 重新加载磁盘上的证书文件。

---

## 许可

按你的项目需要自行补充。
