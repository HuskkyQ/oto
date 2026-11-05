# Oto

[English](README.md) | [简体中文](README.zh-CN.md)

一个为 [TeslaMate](https://github.com/teslamate-org/teslamate) 做的 iOS 应用：实时状态、充电和行程历史，由一个只读的小型 HTTP API 提供数据。

```
iPhone ──HTTPS + Bearer token──> Oto API ──┬─ MQTT（实时）
                                           └─ PostgreSQL（历史，只读）
```

本仓库包含 iOS 应用（`ios/`）和 API（`server/`），以及一个把 TeslaMate、Grafana 和 API 一起拉起来的部署包（`deploy/`）。Oto 只读取 TeslaMate 的数据，从不修改它。

## 部署到服务器

### 服务器要求

- Docker Engine 和 Compose v2 插件，amd64 或 arm64 均可
- 2 GB 内存，约 5 GB 可用磁盘（仅镜像就约 2 GB）
- 可访问外网，用于拉取镜像和访问 Tesla API
- 无需开放任何入站端口：所有服务都绑定在 `127.0.0.1`，只有你自己额外加的反向代理才会对外监听

### 部署

```bash
git clone https://github.com/Huskkyq/oto.git
cd oto && bash deploy/deploy.sh
```

这就是全部部署步骤。脚本会把所有密钥写进 `deploy/.env`（权限 600），启动 TeslaMate、Grafana 和 API，创建只读数据库角色，并打印 API token。重复执行是安全的：已有密钥会被保留，只会重启有变动的服务。

然后用 SSH 隧道完成车辆配对：

```bash
ssh -N -L 4000:127.0.0.1:4000 -L 3000:127.0.0.1:3000 -L 8080:127.0.0.1:8080 user@your-server
```

打开 <http://127.0.0.1:4000>，用你的 Tesla token 登录。Grafana 在 <http://127.0.0.1:3000>（首次登录为 `admin` / `admin`，请立即修改）。

### 配置

所有配置都在 `deploy/.env` 中，由脚本在第一次运行时生成：

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `ENCRYPTION_KEY` | 自动生成 | 加密 TeslaMate 保存的 Tesla token。**修改它会丢失这些 token。** |
| `DATABASE_PASS` | 自动生成 | Postgres 超级用户密码 |
| `RO_PASSWORD` | 自动生成 | API 使用的 `teslamate_ro` 只读角色密码 |
| `API_TOKEN` | 自动生成 | 应用发送的 Bearer token；用 `grep API_TOKEN deploy/.env` 查看 |
| `TESLAMATE_PORT` | `4000` | TeslaMate 网页界面，仅本机 |
| `GRAFANA_PORT` | `3000` | Grafana，仅本机 |
| `API_PORT` | `8080` | Oto API，仅本机 |

`API_TOKEN` 至少需要 24 个字符（生成的是 64 个）。如果端口已被占用，修改 `deploy/.env` 后重新执行脚本即可。

### 让手机访问 API

API 只绑定在本机回环地址，所以手机需要一条通路：

- **反向代理** —— 在同一台机器上用 Caddy、nginx 或 Traefik 终止 TLS，并转发到 `127.0.0.1:8080`。用 Caddy 只需要三行：

  ```
  api.example.com {
      reverse_proxy 127.0.0.1:8080
  }
  ```

  然后在应用中把基础 URL 填成 `https://api.example.com`。
- **Tailscale 或 WireGuard** —— 把手机加入同一网络，从主机上把回环端口暴露出去（Tailscale Serve，或本地 WireGuard 监听）。

不要直接把端口发布到公网：那样 Bearer token 会以明文传输。

### 升级

```bash
cd oto && git pull
docker compose -f deploy/compose.yml --env-file deploy/.env pull teslamate grafana database mosquitto
bash deploy/deploy.sh
```

## 本地运行

只运行 API，连接你已有的 TeslaMate 栈：

```bash
cp .env.example .env     # 填写 DATABASE_PASS 和 API_TOKEN，说明见文件内注释
docker compose up -d --build
curl -s localhost:8080/healthz
```

只读角色只需创建一次（部署脚本会自动完成这一步）：

```bash
docker compose exec -T database \
  psql -U teslamate -d teslamate -v ON_ERROR_STOP=1 -v pw="<角色密码>" <<'SQL'
SELECT format('CREATE ROLE teslamate_ro LOGIN PASSWORD %L', :'pw')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'teslamate_ro')\gexec
GRANT CONNECT ON DATABASE teslamate TO teslamate_ro;
GRANT USAGE ON SCHEMA public TO teslamate_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO teslamate_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO teslamate_ro;
SQL
```

`compose.yml` 以外部网络的方式加入 TeslaMate 的 compose 网络。如果你的网络名不是 `startfile_default`，请修改 `networks` 下的 `name:`（用 `docker network ls` 查看实际名称）。

## 运行 iOS 应用

需要 Xcode 15+ 和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
cd ios
xcodegen generate
open TeslaMateViewer.xcodeproj
```

在模拟器或真机上运行，打开 **设置**，填入 API 基础 URL（模拟器用 `http://127.0.0.1:8080`）和 API token。

从命令行构建：

```bash
cd ios
xcodebuild -project TeslaMateViewer.xcodeproj -scheme TeslaMateViewer \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

请妥善保管 token：任何拿到它的人都能读取你车辆的位置历史。

## 文档

- [API 参考](docs/API.zh-CN.md) —— 接口、参数、响应结构
- [技术栈](docs/TECH-STACK.zh-CN.md) —— API 如何读取 TeslaMate
- [界面设计](docs/UI-DESIGN.zh-CN.md) 和 [组件](docs/UI-COMPONENTS.zh-CN.md)
- `docs/mockups/index.html` —— 静态原型
