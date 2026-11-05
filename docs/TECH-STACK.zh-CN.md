# Oto —— 技术栈

本文区分已有代码与规划中的工作。版本描述的是仓库配置，不代表部署已验证。功能进度见 [STATUS.zh-CN.md](STATUS.zh-CN.md)。

## 架构

```text
iPhone（SwiftUI）
  │ HTTPS + Bearer Token
  ▼
公网服务器（固定域名、HTTPS 反向代理）
  │ 通过 Tailscale 私有连接
  ▼
Mac 上的 Node.js 只读 API（Docker）
  ├── PostgreSQL：TeslaMate 历史数据，数据库角色仅有 SELECT 权限
  └── MQTT / Mosquitto：TeslaMate 实时数据
```

API 配置为监听 Mac 的回环地址，并加入 TeslaMate 已有的 Docker 网络。计划由公网反向代理通过 Tailscale 连接 Mac，iPhone 无需安装或连接 Tailscale。代理终止公网 TLS，并通过私有连接将 Bearer Token 转发给 API。代理及端到端部署尚未配置或验证；Mac、API 或私有连接不可用时，代理无法提供新的 API 数据。

## iOS 应用

| 技术 | 用途 | 状态 |
|---|---|---|
| Swift 5.9、SwiftUI、iOS 17+ | 原生 iPhone 界面和应用逻辑 | 已配置；可针对 iOS 模拟器构建。实时页面和共享外壳已有代码；四个 Tab 页面为占位。 |
| Xcode 15+、XcodeGen | 从 `ios/project.yml` 生成项目并构建 | 已配置或记录；生成的 Xcode 项目未纳入仓库。 |
| URLSession、async/await、Codable | HTTP 请求和 JSON 模型 | 已有代码。 |
| Security / Keychain | 存储 API Bearer Token | 已有代码。 |
| Swift Charts | 历史折线图和柱状图 | 已有图表组件；其余页面尚未完成。 |
| MapKit | 车辆位置和轨迹地图 | 规划中；地图页面尚未完成。WGS-84 到 GCJ-02 的转换已有代码但尚未接入。 |
| SwiftData | 缓存最近成功的响应，供离线查看 | 规划中，尚未实现。 |
| XCTest | iOS 单元测试 | 已配置测试目标；测试目录为空。 |

`ios/project.yml` 未声明第三方 iOS 包。3D 车辆方案已延后，其拟用的 RealityKit 和 USDZ 不是当前应用的必需技术。

## API 与数据

| 技术 | 用途 | 状态 |
|---|---|---|
| Node.js 22、JavaScript ES modules、`node:http` | 独立 JSON API，不使用 Web 框架 | 已有代码；`server/package.json` 要求 Node ≥22，Docker 镜像使用 Node 22 Alpine。 |
| `pg` ^8.23.1 | 查询 TeslaMate 的 PostgreSQL 数据 | 直接依赖；锁文件解析为 8.23.1。 |
| `mqtt` ^5.16.1 | 订阅 TeslaMate 实时 MQTT 主题 | 直接依赖；锁文件解析为 5.16.1。 |
| PostgreSQL | 行程、充电、位置和统计等历史数据 | TeslaMate 现有服务；Oto 计划使用仅有 SELECT 权限的角色。版本由实际 TeslaMate 部署决定。 |
| MQTT / Mosquitto | 车辆状态消息与内存实时缓存 | TeslaMate 现有服务；版本取决于实际部署。 |
| Node 内置测试运行器（`node --test`） | API 单元测试 | 已在 `server/package.json` 配置；已有测试结果记录见 STATUS。 |

API 使用 Bearer Token 认证；`/healthz` 公开，数据接口需要认证。接口约定见 [API.zh-CN.md](API.zh-CN.md)。

## 部署与设计

| 技术 | 用途 | 状态 |
|---|---|---|
| Docker、Docker Compose | 将 API 容器化并接入 TeslaMate 网络 | `compose.yml` 和 `server/Dockerfile` 中已有配置。 |
| 公网 HTTPS 反向代理 | 提供固定域名入口并转发请求 | 规划中；代理软件、服务器及配置尚未选定或部署。 |
| Tailscale HTTPS | 公网服务器到 Mac 的私有连接 | 规划中，尚未验证；iPhone 不需要 Tailscale。 |
| HTML、CSS、内联 SVG 和 JavaScript | 独立页面及组件视觉稿 | 已有 [mockups/index.html](mockups/index.html) 和 [mockups/components.html](mockups/components.html)；它们是设计参考，不是 iOS 运行时。 |

## 尚未决定的事项

- 第三方充电费用的手动录入已延后。本地存储会产生第二个数据源；写入 TeslaMate 会违反当前只读架构。尚未选定持久化技术，见 [PRD §10](PRD.zh-CN.md)。
- 现有应用尚未完成：四个 Tab 页面仍是占位；真机验证、离线缓存和地图接入仍未完成。

## 参考

- [API 契约](API.zh-CN.md) · [产品需求](PRD.zh-CN.md) · [UI 设计](UI-DESIGN.zh-CN.md) · [组件清单](UI-COMPONENTS.zh-CN.md) · [项目状态](STATUS.zh-CN.md)
- [服务端依赖](../server/package.json) · [iOS 项目配置](../ios/project.yml) · [部署配置](../compose.yml)
- English: [TECH-STACK.md](TECH-STACK.md)
